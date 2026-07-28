{
  # Second lane for the CMake build, independent of the frozen Sirehna docker images.
  #
  #   nix develop
  #   mise run configure && mise run build && mise run test
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
      cxxLibs = [
        boostStatic hdf5Cxx
        pkgs.eigen_5 pkgs.gtest                       # eigen_5 clears an Eigen -Werror=uninitialized false positive
        pkgs.protobuf pkgs.grpc pkgs.abseil-cpp
        pkgs.openssl pkgs.re2 pkgs.c-ares pkgs.zlib   # named in grpc++.pc Requires, so pkg-config needs them present
      ];
    in {
      devShells.${system}.default = (pkgs.mkShell.override { stdenv = pkgs.gcc16Stdenv; }) {
        nativeBuildInputs = [
          pkgs.cmake pkgs.ninja pkgs.pkg-config pkgs.git pkgs.mise
          pkgs.gfortran                                 # CMakeLists links gfortran for SSC's f2c
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
    };
}
