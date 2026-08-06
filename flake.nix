{
  # The development shell for the zig/libc++ build.
  #
  #   nix develop            zig, mise, and the tools the lanes shell out to
  #   nix develop .#cross    the above + qemu-user and wine, to *run* the cross test suites
  #   nix develop .#deps     the above + cmake and ninja, to *build* a dependency closure
  #
  #   zig build test         916 unit tests
  #   mise run cross         both cross suites
  #
  # This shell provides TOOLS. It provides no C++ library, and adding one is the mistake this
  # whole toolchain exists to make impossible — see the boxed warning below.
  description = "xdyn — zig/libc++ development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # The dependency closure's upstream sources, pinned in flake.lock by content hash.
    # tools/deps/fetch-sources.sh clones the same five versions for the standalone path, and
    # the two lists have to be changed together -- there is no mechanism that couples them.
    #
    # `refs/tags/` is spelled out on purpose: a bare `ref=v1.78.1` resolves as refs/heads/, so
    # Nix asks for a *branch* of that name and silently pins one if it exists. That is the same
    # trust `git clone --branch` places in a movable name, which pinning is meant to remove.
    src-yaml-cpp   = { url = "github:jbeder/yaml-cpp/yaml-cpp-0.9.0"; flake = false; };
    src-googletest = { url = "github:google/googletest/v1.15.2";      flake = false; };
    src-hdf5       = { url = "github:HDFGroup/hdf5/hdf5_1.14.6";      flake = false; };
    src-grpc       = { url = "git+https://github.com/grpc/grpc?ref=refs/tags/v1.78.1&submodules=1"; flake = false; };
    src-boost      = { url = "tarball+https://archives.boost.io/release/1.89.0/source/boost_1_89_0.tar.bz2"; flake = false; };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # ===================================================================================
      # The dependency closure, as a derivation per target triple.
      #
      # This does NOT reimplement tools/deps/. The recipes stay the source of truth and keep
      # working standalone, which is what anyone without Nix uses; all this adds is pinned
      # sources and a sandbox. What the sandbox buys is the thing -Ddeps could never give:
      # the closure gets an identity. Today "which closure is this?" has no better answer
      # than a directory name and an mtime.
      #
      # stdenvNoCC, never a cc stdenv and never libcxxStdenv: Nix must put no compiler and no
      # libstdc++ anywhere near this, and a derivation reaching for nixpkgs' libc++ would put
      # a *second* libc++ in the graph. zig owns the whole graph or none of it.
      #
      # src is tools/deps/ rather than the repository: $REPO is only ever a default for the
      # three variables set below, so nothing else is read -- and with `src = self` every
      # edit to an xdyn .cpp would invalidate a multi-hour build.
      # ===================================================================================
      # Everything a sandboxed recipe run needs before the recipes start: writable homes and
      # caches for tools that assume one, and the pinned sources copied in. Shared by the
      # closures and by the host tools, which run the same recipes under the same constraints.
      sandboxPrelude = ''
        export HOME=$TMPDIR/home
        export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig XDG_CACHE_HOME=$TMPDIR/cache
        export WINEPREFIX=$TMPDIR/wine WINEDEBUG=-all
        mkdir -p $HOME $ZIG_GLOBAL_CACHE_DIR $XDG_CACHE_HOME $WINEPREFIX

        # The recipes write into $SRC -- b2 bootstraps there and BUILD is $SRC/build/<triple>
        # -- so the pinned store paths are copied rather than referenced, and made writable.
        export XDYN_DEPS_SRC=$TMPDIR/src
        mkdir -p $XDYN_DEPS_SRC
        cp -r ${inputs.src-yaml-cpp}   $XDYN_DEPS_SRC/yaml-cpp
        cp -r ${inputs.src-googletest} $XDYN_DEPS_SRC/googletest
        cp -r ${inputs.src-hdf5}       $XDYN_DEPS_SRC/hdf5
        cp -r ${inputs.src-grpc}       $XDYN_DEPS_SRC/grpc
        cp -r ${inputs.src-boost}      $XDYN_DEPS_SRC/boost_1_89_0
        # u+w, not --no-preserve=mode: store paths are read-only and the recipes write here,
        # but stripping modes also strips the executable bit, and Boost bootstraps b2 by
        # running ./build.sh.
        chmod -R u+w $XDYN_DEPS_SRC
      '';

      # The protoc and grpc_cpp_plugin every closure's gRPC build runs, static so they need no
      # interpreter. A separate derivation and not a step inside mkClosure, because all four
      # flavors share one -- including the host-matching one, whose own protoc a sandbox cannot
      # run either.
      hostTools = pkgs.stdenvNoCC.mkDerivation {
        pname = "lxdyn-deps-host-tools";
        version = "1.78.1";
        src = ./tools/deps;
        nativeBuildInputs = [ pkgs.zig pkgs.cmake pkgs.ninja pkgs.git pkgs.llvm ];
        dontFixup = true;
        buildPhase = ''
          runHook preBuild
          ${sandboxPrelude}
          # Both, and XDYN_DEPS is not redundant: fetch-sources.sh runs first and takes common.sh's
          # $REPO fallback for it, which inside a derivation resolves to / -- src is tools/deps/,
          # so $HERE/../.. escapes the build directory entirely.
          export XDYN_DEPS=$out XDYN_DEPS_HOST=$out
          sh ./fetch-sources.sh
          sh ./build-host-tools.sh
          runHook postBuild
        '';
        installPhase = "runHook preInstall; runHook postInstall";
        meta.description = "protoc and grpc_cpp_plugin for the build machine, static";
      };

      mkClosure = { triple, host ? null, emulators ? [ ], steps ? null }:
        pkgs.stdenvNoCC.mkDerivation {
          pname = "libcxx-deps-${triple}";
          version = "1.78.1-1.89.0-1.14.6";   # grpc-boost-hdf5, the three that move
          src = ./tools/deps;

          # llvm for llvm-nm: build-boost.sh and build-grpc.sh both assert that what came out
          # carries libc++ mangling. The devShell has always had it, which is why nothing declared
          # it -- the same omission 320ebd1a fixed for cmake, ninja and zstd.
          nativeBuildInputs = [ pkgs.zig pkgs.cmake pkgs.ninja pkgs.git pkgs.llvm ] ++ emulators;

          # The archives are the product. Fixup would strip them with binutils, which is built
          # for one architecture, no-ops per member on a foreign archive and still exits 0 --
          # the defect that made an aarch64 asset 264 MB instead of 44.
          dontFixup = true;

          buildPhase = ''
            runHook preBuild
            ${sandboxPrelude}

            # fetch-sources.sh runs, but every clone is guarded by [ -d ] || and short-circuits
            # on the copies above, so nothing reaches the network. Its b2 bootstrap does run,
            # which is deliberate: that step is zig-built and needs no host compiler.
            export XDYN_DEPS=$out
            ${if host == null then "" else "export XDYN_DEPS_HOST=${host}"}
            ${if steps == null then "" else "export XDYN_DEPS_STEPS='${steps}'"}
            sh ./build-all.sh ${triple}
            runHook postBuild
          '';

          # common.sh creates $out and the recipes install into it directly.
          installPhase = "runHook preInstall; runHook postInstall";

          meta.description = "xdyn C++ dependency closure, libc++, ${triple}";
        };

      closures = rec {
        host-tools = hostTools;

        # A sandbox smoke test, not a closure. The step list is chosen for coverage rather than
        # for cheapness, which is the correction: a version running only yaml-cpp and gtest
        # exercised nothing but CMake, and could not have found llvm-nm undeclared -- the two
        # steps that assert on its output are boost's and gRPC's. Boost is the cheaper of those
        # and the only one driven by b2 rather than CMake, so it earns its minutes twice.
        # What is left out is gRPC, which is the hours.
        probe = mkClosure {
          triple = "x86_64-linux-gnu";
          host = hostTools;
          steps = "fetch-sources build-yaml-cpp build-gtest build-boost";
        };

        # Every flavor takes the same host tools, the host-matching one included: codegen runs on
        # the build machine whatever the target is, and the protoc a native build would produce
        # for itself is dynamically linked, so a sandbox with no /lib64 cannot run it either.
        # The closures are therefore independent of each other -- none of them is "the native one"
        # that the rest wait for.
        libcxx-deps-x86_64-linux-gnu = mkClosure {
          triple = "x86_64-linux-gnu";
          host = hostTools;
        };
        libcxx-deps-x86_64-linux-musl = mkClosure {
          triple = "x86_64-linux-musl";
          host = hostTools;
        };
        # b2 runs its configure probes by *executing* what it compiles, so the two foreign
        # targets need their emulator. Both were measured working inside a build sandbox.
        libcxx-deps-aarch64-linux-musl = mkClosure {
          triple = "aarch64-linux-musl";
          host = hostTools;
          emulators = [ pkgs.qemu ];
        };
        libcxx-deps-x86_64-windows-gnu = mkClosure {
          triple = "x86_64-windows-gnu";
          host = hostTools;
          emulators = [ pkgs.wine64 ];
        };
      };
    in {
      packages.${system} = closures;

      devShells.${system} = rec {
        # mkShellNoCC, not mkShell: mkShell wires in a cc-wrapper whose setup hook exports
        # NIX_CFLAGS_COMPILE and CPATH for every dev output in scope. zig cc honours CPATH,
        # so that wrapper is a route for nixpkgs headers — and behind them nixpkgs' libstdc++
        # — to reach a compile that is supposed to see only zig's own libc++ and the closure.
        # There is no host C or C++ compiler in this shell because nothing needs one: zig cc
        # compiles every C and C++ source, including SSC's f2c, which is C rather than Fortran.
        default = pkgs.mkShellNoCC {
          packages = [
            pkgs.zig                                      # the compiler and the build system
            pkgs.mise                                     # task runner only — it pins no tool
                                                          # versions, nix does that here
            pkgs.git                                      # build.zig stamps the commit into the
                                                          # binaries; -Dgit-sha= overrides
            pkgs.curl.bin                                 # tools/deps/fetch.sh. The .bin output
                                                          # only: the full package puts its dev
                                                          # closure — openssl, krb5, nghttp2,
                                                          # zstd and eight more — on
                                                          # PKG_CONFIG_PATH, for a program this
                                                          # shell only ever *runs*.
            pkgs.pkg-config                               # build.zig's fourth eigen probe

            pkgs.uv                                       # owns the Python envs, interpreters
                                                          # included. No pkgs.python* beside it:
                                                          # a nixpkgs interpreter exports its own
                                                          # PYTHONPATH into every other
                                                          # interpreter in the shell, which once
                                                          # made a 3.10 venv report a cpython-313
                                                          # ABI tag.
            pkgs.gdb                                      # mise run gdb. Without it the task
                                                          # silently falls through to whatever
                                                          # gdb the host has, or to none.
                                                          # .gdbinit needs one built with Python
                                                          # for $_regex.
            pkgs.doxygen                                  # mise run doc:cpp
            pkgs.llvm                                     # llvm-strip and llvm-nm, for
                                                          # tools/deps/, deploy:stage and the
                                                          # wheel. Their binutils equivalents are
                                                          # built for one architecture: on the
                                                          # aarch64 and Windows archives strip
                                                          # fails per member and still exits 0
                                                          # The llvm tools are
                                                          # target-agnostic. See the second
                                                          # boxed warning below before reaching
                                                          # for pkgs.binutils to get `nm`.
            pkgs.zstd                                     # tools/deps/fetch.sh unpacks with it,
                                                          # and pack.sh compresses with it. In
                                                          # *this* shell rather than .#deps
                                                          # because fetching a closure is the
                                                          # common path and building one is not.
            pkgs.hdf5.bin                                 # h5dump, which the CLI integration
                                                          # tests diff against. The .bin output
                                                          # ONLY: pkgs.hdf5 itself is a C++
                                                          # library and belongs nowhere near this
                                                          # list.
          ];

          # Header-only, so it carries no compiled std ABI and is not a bucket-3 dependency.
          # In buildInputs rather than packages so pkg-config's setup hook puts it on
          # PKG_CONFIG_PATH, which is how build.zig's probe finds it. eigen_5 specifically:
          # it clears an Eigen -Werror=uninitialized false positive.
          buildInputs = [ pkgs.eigen_5 ];

          shellHook = ''
            echo "xdyn devShell: $(zig version), $(uv --version)"
          '';
        };

        # ⛔ Do not add pkgs.boost / pkgs.grpc / pkgs.hdf5 / pkgs.yaml-cpp / pkgs.gtest here.
        # They are libstdc++ builds. Linking one against a zig cc object fails on mangling
        # and getting one in by accident risks two libc++ versions in a single
        # graph, which fails at link time if you are lucky and at runtime if you
        # are not. Every C++ library xdyn links comes from the closure in tools/deps/, built
        # by zig cc against zig's libc++. That is the rule the first attempt at this migration
        # died for.

        # ⛔ Do not add pkgs.binutils either, however much `nm` or `ld` is wanted. Its setup hook
        # exports NIX_LDFLAGS and puts a *wrapped* ld and as on PATH ahead of /usr/bin, so a host
        # cc compiles against host headers and then links against the nix store. The executables
        # that come out abort before main. Nothing in this repo compiles with a host cc — but uv
        # does, whenever it fills an interpreter for which a dependency publishes no wheel
        # (numpy 1.26.4 on 3.13 and 3.15), and that is how this was found: green here, red in CI.
        # llvm-nm is already in the list and reads every flavor.

        # zig cross-*compiles* with nothing added; these only *run* the results, which is why they
        # are a separate shell rather than part of the default one — wine alone drags in a
        # multimedia and X11 graph larger than everything above put together.
        #
        # `zig build test -Dtarget=…` also runs a foreign binary transparently wherever binfmt_misc
        # is registered for it, which is why -fqemu/-fwine are passed explicitly by `mise run cross`:
        # relying on the host's binfmt registration would make the lane pass here and nowhere else.
        # Building a closure *from source*, as opposed to fetching one. Extends `cross` rather
        # than `default` because b2 runs its configure probes by *executing* what it compiles, so
        # the aarch64 and Windows closures need qemu and wine (see tools/deps/build-boost.sh).
        #
        # cmake and ninja live here and not in `default` on purpose: `zig build` invokes neither,
        # they exist only for tools/deps/, and fetching a closure is what almost everyone does.
        # tools/deps/common.sh checks for them and names this shell, so the failure is legible.
        deps = cross.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.cmake pkgs.ninja ];
          shellHook = old.shellHook + ''
            echo "  closure toolchain: $(cmake --version | head -1), ninja $(ninja --version)"
          '';
        });

        cross = default.overrideAttrs (old: {
          nativeBuildInputs = old.nativeBuildInputs ++ [
            pkgs.qemu      # qemu-aarch64, user-mode
            pkgs.wine64    # the *package* is wine64, the *binary* is plain `wine` — Wine 11 merged
                           # the two and there is no wine64 executable any more
          ];
          shellHook = old.shellHook + ''
            echo "  cross runners: $(qemu-aarch64 --version | head -1), $(wine --version)"
          '';
        });
      };
    };
}
