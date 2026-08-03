#!/bin/sh
# The whole gRPC stack, including the abseil, protobuf, re2, c-ares, upb, boringssl and zlib it
# vendors. Every one of them exports mangled std:: symbols, so none may come from the host.
set -e
FLAVOR=${1:-x86_64-linux-gnu}
. "$(dirname "$0")/common.sh"

# CMAKE_DISABLE_FIND_PACKAGE_systemd: gRPC picks up a host libsystemd if one is installed, and
# every binary in the closure then needs it at link time.
# The plugin toggles: xdyn generates C++ only, and the other six languages' plugins are a
# significant fraction of the build.
cmake_build "$SRC/grpc" grpc \
  -DgRPC_BUILD_TESTS=OFF \
  -DgRPC_INSTALL=ON \
  -DABSL_PROPAGATE_CXX_STD=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_systemd=ON \
  -DZLIB_BUILD_EXAMPLES=OFF \
  -DgRPC_BUILD_GRPC_CPP_PLUGIN=ON \
  -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF \
  $GRPC_EXTRA

if ! llvm-nm "$DEPS/install/lib/libgrpc++.a" | grep -q 'St3__1'; then
  echo "grpc: no libc++ mangling in the output" >&2
  exit 1
fi
