#!/bin/sh
# protoc and grpc_cpp_plugin for the BUILD machine, linked statically against musl.
#
# gRPC generates C++ from its own .proto files during its build, so it needs a protoc it can
# *run*. Today the three cross flavors borrow the native closure's, which makes that closure a
# build dependency of every other one and quietly assumes an x86_64 glibc build host. It also
# does not survive a build sandbox: a dynamically linked protoc names /lib64/ld-linux-x86-64.so.2
# as its interpreter, a sandbox root has no /lib64, and it dies before main -- which is true of
# the native flavor too, so this is not a cross-only concern.
#
# Static musl answers both. The target follows `uname -m` rather than naming x86_64, the same way
# fetch-sources.sh bootstraps b2: these are host tools and the host is whatever is running. Built
# from the same grpc tree every flavor compiles against, so the gencode matches the libprotobuf
# it will be compiled against -- which is the reason a system protoc cannot be used here.
set -e
_here=$(cd "$(dirname "$0")" && pwd)
XDYN_DEPS_HOST=${XDYN_DEPS_HOST:-$(cd "$_here/../.." && pwd)/host-tools}
export XDYN_DEPS_HOST

# Idempotent, like fetch-sources.sh's clones: build-all.sh lists this step for the standalone
# path, where nothing else would produce it, while under Nix it is its own derivation and
# $XDYN_DEPS_HOST already names a finished one. Same script, both ways, no branch in the caller.
if [ -x "$XDYN_DEPS_HOST/install/bin/protoc" ]; then
  echo "host-tools: already present at $XDYN_DEPS_HOST"
  exit 0
fi

FLAVOR=host-tools
XDYN_DEPS=$XDYN_DEPS_HOST
export XDYN_DEPS
. "$_here/common.sh"

# $SRC/build/host-tools rather than $SRC/build/$FLAVOR: FLAVOR is not a target triple here, and
# these objects are a different target from every closure sharing this source tree.
BUILD=$SRC/build/host-tools
mkdir -p "$BUILD"

# No -DgRPC_INSTALL: nothing here is installed or linked into a closure, and asking for the
# install tree would build the whole runtime stack rather than the two binaries.
cmake -S "$SRC/grpc" -B "$BUILD/grpc" -G Ninja $CMAKE_COMMON \
  -DgRPC_BUILD_TESTS=OFF \
  -DABSL_PROPAGATE_CXX_STD=ON \
  -DCMAKE_DISABLE_FIND_PACKAGE_systemd=ON \
  -DgRPC_BUILD_GRPC_CPP_PLUGIN=ON \
  -DgRPC_BUILD_GRPC_PYTHON_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_CSHARP_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_NODE_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_OBJECTIVE_C_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_PHP_PLUGIN=OFF \
  -DgRPC_BUILD_GRPC_RUBY_PLUGIN=OFF

cmake --build "$BUILD/grpc" -j"$(nproc)" --target protoc grpc_cpp_plugin

mkdir -p "$XDYN_DEPS_HOST/install/bin"
cp "$BUILD/grpc/grpc_cpp_plugin" "$XDYN_DEPS_HOST/install/bin/grpc_cpp_plugin"
# -L: protobuf installs protoc as a symlink to protoc-<version>.
cp -L "$BUILD/grpc/third_party/protobuf/protoc" "$XDYN_DEPS_HOST/install/bin/protoc"

# The assertion that matters is not "is it static" but "does it run *here*" -- here being
# whatever restricted environment the closure build will run in.
"$XDYN_DEPS_HOST/install/bin/protoc" --version
"$XDYN_DEPS_HOST/install/bin/grpc_cpp_plugin" --version 2> /dev/null || true
