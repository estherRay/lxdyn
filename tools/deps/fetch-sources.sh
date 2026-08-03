#!/bin/sh
# Fetch every upstream source once into libcxx-src/, shared by all three flavors. yaml-cpp is
# absent on purpose: it comes from this repo's own external/ submodule, not from upstream.
set -e
FLAVOR=${1:-x86_64-linux-gnu}
. "$(dirname "$0")/common.sh"

clone() {  # $1 = url, $2 = tag, $3 = directory
  [ -d "$SRC/$3" ] || git clone --depth 1 --branch "$2" "$1" "$SRC/$3"
}

clone https://github.com/google/googletest v1.15.2 googletest
clone https://github.com/HDFGroup/hdf5 hdf5_1.14.6 hdf5

# gRPC vendors abseil, protobuf, re2, c-ares, upb, boringssl and zlib. The closure builds all of
# them rather than resolving any from the host, so the submodules are not optional.
[ -d "$SRC/grpc" ] || git clone --depth 1 --branch v1.78.1 \
  --recurse-submodules --shallow-submodules https://github.com/grpc/grpc "$SRC/grpc"

[ -d "$SRC/boost_1_89_0" ] || \
  curl -fsSL https://archives.boost.io/release/1.89.0/source/boost_1_89_0.tar.bz2 | tar xj -C "$SRC"

# b2 is bootstrapped here rather than in build-boost.sh: the source tree is shared, so
# bootstrapping per flavor would have the flavors race. b2 itself is a host tool.
[ -x "$SRC/boost_1_89_0/b2" ] || (cd "$SRC/boost_1_89_0" && ./bootstrap.sh >/dev/null)
