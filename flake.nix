{
  # Second lane for the CMake build, independent of the frozen Sirehna docker images.
  #
  #   nix develop            CMake + g++, and the zig the tools/deps/ recipes call
  #   nix develop .#cross    the above + qemu-user and wine, to *run* the cross test suites
  #
  #   mise run configure && mise run build && mise run test
  #   mise run cross
  #
  # This shell provisions CMake's dependencies, so it is transitional: it exists to prove the
  # tree builds outside docker, and it goes away with CMake itself. yaml-cpp and websocketpp
  # are deliberately absent — both are submodules built in-tree, so that the docker lane and
  # this one compile the same sources.
  description = "xdyn — CMake build environment, second lane alongside docker";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      hdf5Cxx     = pkgs.hdf5.override  { cppSupport   = true; };  # FIND_PACKAGE(HDF5 COMPONENTS C CXX HL)
      boostStatic = pkgs.boost.override { enableStatic = true; };  # CMakeLists sets Boost_USE_STATIC_LIBS ON
      # These are libstdc++ builds, and mkShell puts every one of their dev outputs on CPATH,
      # which zig cc honours. tools/deps/ is immune only because it always names an explicit
      # -target, which switches zig to its own bundled headers and nothing else.
      cxxLibs = [
        boostStatic hdf5Cxx
        pkgs.eigen_5 pkgs.gtest                       # eigen_5 clears an Eigen -Werror=uninitialized false positive
        pkgs.protobuf pkgs.grpc pkgs.abseil-cpp
        pkgs.openssl pkgs.re2 pkgs.c-ares pkgs.zlib   # named in grpc++.pc Requires, so pkg-config needs them present
      ];
    in {
      devShells.${system} = rec {
        default = (pkgs.mkShell.override { stdenv = pkgs.gcc16Stdenv; }) {
          nativeBuildInputs = [
            pkgs.cmake pkgs.ninja pkgs.pkg-config pkgs.git pkgs.mise
            pkgs.gfortran                                 # CMakeLists links gfortran for SSC's f2c
            pkgs.zig pkgs.curl                            # tools/deps/ recipes; not used by the CMake lane
            pkgs.gdb                                      # mise run gdb. Without it the task silently
                                                          # falls through to whatever gdb the host has,
                                                          # or to none. .gdbinit needs one built with
                                                          # Python for $_regex.
          ];
          buildInputs = cxxLibs;

          # CMAKE_PREFIX_PATH must be set by hand. nixpkgs only passes it during a derivation's
          # cmakeConfigurePhase, and this shell invokes cmake directly — leave it unset and
          # find_package(HDF5) resolves to the host's /usr/lib64/cmake/hdf5, a libstdc++ build
          # being linked into a gcc16Stdenv compile.
          shellHook = ''
            export CMAKE_PREFIX_PATH="${pkgs.lib.concatMapStringsSep ":" pkgs.lib.getDev cxxLibs}"
            echo "xdyn devShell: $(g++ --version | head -1)"
          '';
        };

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
