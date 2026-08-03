{
  # The development shell for the zig/libc++ build.
  #
  #   nix develop            zig, mise, and the tools the lanes shell out to
  #   nix develop .#cross    the above + qemu-user and wine, to *run* the cross test suites
  #
  #   zig build test         916 unit tests
  #   mise run cross         both cross suites
  #
  # This shell provides TOOLS. It provides no C++ library, and adding one is the mistake this
  # whole toolchain exists to make impossible — see the boxed warning below.
  description = "xdyn — zig/libc++ development shell";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in {
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
            pkgs.git                                      # gen.sh stamps the sha into the binary
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
                                                          # (Hazard R). The llvm tools are
                                                          # target-agnostic. See the second
                                                          # boxed warning below before reaching
                                                          # for pkgs.binutils to get `nm`.
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
        # (Hazard A), and getting one in by accident risks two libc++ versions in a single
        # graph (Hazard B), which fails at link time if you are lucky and at runtime if you
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
