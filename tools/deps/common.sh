# Sourced by the recipes; does nothing on its own. The caller sets FLAVOR first.
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

FLAVOR=${FLAVOR:-x86_64-linux-gnu}

# Every flavor names an explicit target, including the native one. That is what makes the build
# hermetic: with no -target, zig treats the compile as native and honours CPATH, which inside
# `nix develop` means glibc 2.42 plus every libstdc++ C++ library in the flake's buildInputs.
# An explicit target switches zig to its own bundled headers and nothing else.
#
# glibc 2.28 is the floor because it is the oldest still in service — Debian 10, RHEL 8,
# Ubuntu 18.04. It also fixes what a published closure can link against: build against a newer
# glibc and its headers redirect to symbols (__isoc23_strtol and friends) that older systems
# do not have, so the final link fails on the user's machine rather than here.
# A flavor IS its target triple. Two-thirds of one does not identify a closure: x86_64-linux-gnu
# and x86_64-linux-musl differ only in the libc, which is exactly what a closure carries. The
# directory, the release asset, the mise task and build.zig's default all use this name.
case $FLAVOR in
  x86_64-linux-gnu)
    ZIG_TARGET=x86_64-linux-gnu.2.28
    B2_ARGS="architecture=x86 address-model=64"
    ;;
  x86_64-linux-musl)
    ZIG_TARGET=x86_64-linux-musl
    B2_ARGS="architecture=x86 address-model=64"
    CMAKE_SYSTEM=Linux CMAKE_PROCESSOR=x86_64
    ;;
  aarch64-linux-musl)
    ZIG_TARGET=aarch64-linux-musl
    B2_ARGS="architecture=arm address-model=64"
    CMAKE_SYSTEM=Linux CMAKE_PROCESSOR=aarch64
    ;;
  x86_64-windows-gnu)
    ZIG_TARGET=x86_64-windows-gnu
    B2_ARGS="target-os=windows threadapi=win32 architecture=x86 address-model=64"
    CMAKE_SYSTEM=Windows CMAKE_PROCESSOR=AMD64
    # boringssl's Windows assembly is NASM syntax and would need a nasm on the host. The
    # pure-C fallback costs nothing for xdyn's localhost gRPC.
    GRPC_EXTRA=-DOPENSSL_NO_ASM=ON
    ;;
  *)
    echo "unknown flavor '$FLAVOR' -- expected one of:" >&2
    echo "  x86_64-linux-gnu  x86_64-linux-musl  aarch64-linux-musl  x86_64-windows-gnu" >&2
    echo "A macOS flavor is deliberately absent: it needs a real Apple SDK, because gRPC's" >&2
    echo "cf_engine and abseil's timezone lookup use CoreFoundation. See docs." >&2
    exit 1
    ;;
esac
export ZIG_TARGET

# b2 keys its object directories off the toolset name, so each flavor needs its own -- but the
# triple's dashes cannot go in one: b2 splits `toolset=name-version` on the first dash. Strip
# them. (The `zig` prefix is separate and also load-bearing; see build-boost.sh.)
B2_TAG=$(echo "$FLAVOR" | tr -d -- '-')

# Sources are shared by every flavor; only the install tree and the merged archives are per-flavor.
# Keeping build trees out of $DEPS leaves it holding exactly what gets published.
SRC=${XDYN_DEPS_SRC:-$REPO/libcxx-src}
DEPS=${XDYN_DEPS:-$REPO/libcxx-$FLAVOR}
BUILD=$SRC/build/$FLAVOR
mkdir -p "$SRC" "$BUILD" "$DEPS/install/lib" "$DEPS/install/include"

# Checked here rather than three components in, when cmake is missing and the error is a
# shell's. `nix develop` alone carries neither cmake nor ninja: C22 deleted the CMake lane and
# C23 stopped provisioning its tools, and nothing in `zig build` wants them. They live in the
# .#deps shell, together with the emulators b2's cross configure probes need.
for tool in cmake ninja zig; do
  command -v "$tool" > /dev/null 2>&1 || {
    echo "tools/deps needs '$tool', which this shell does not provide." >&2
    echo "Building a closure needs:  nix develop .#deps" >&2
    exit 1
  }
done

# cmake and b2 both exec these by name.
PATH=$HERE/bin:$PATH

# gRPC find_program()s a HOST protoc and grpc_cpp_plugin for its own build-time codegen. The
# native closure's must win: it is built from the same v1.78.1 tree, so its gencode matches.
# A system protoc fails the version assertion the generated sources carry.
if [ "$FLAVOR" != x86_64-linux-gnu ]; then
  # $XDYN_DEPS_HOST names the *host* closure, the same variable build.zig reads for codegen.
  # A derivation cannot use the in-repo default -- its host closure is a store path -- so the
  # coupling has to be nameable rather than hardcoded.
  NATIVE_BIN=${XDYN_DEPS_HOST:-$REPO/libcxx-x86_64-linux-gnu}/install/bin
  [ -x "$NATIVE_BIN/protoc" ] || {
    echo "$FLAVOR needs the native closure first: no protoc under $NATIVE_BIN" >&2
    echo "run 'mise run deps:x86_64-linux-gnu'" >&2
    exit 1
  }
  PATH=$NATIVE_BIN:$PATH
fi
export PATH

# find_program consults $CMAKE_PREFIX_PATH before $PATH, and `nix develop` exports one naming
# every C++ library in the flake. That beats the prepend above: gRPC took the flake's protoc 35.1,
# generated its sources with it, and compiled them against the closure's protobuf 31.1 headers.
# A closure may not discover anything through the shell that happens to be running it.
unset CMAKE_PREFIX_PATH CMAKE_PROGRAM_PATH CMAKE_INCLUDE_PATH CMAKE_LIBRARY_PATH CMAKE_FRAMEWORK_PATH

# The host-matching flavor deliberately gets no toolchain file. Setting CMAKE_SYSTEM_NAME turns CMAKE_CROSSCOMPILING
# on even when it names the host, and gRPC then hunts for a host protoc instead of building one.
if [ -n "$CMAKE_SYSTEM" ]; then
  TOOLCHAIN=$BUILD/toolchain.cmake
  sed -e "s|@SYSTEM@|$CMAKE_SYSTEM|" -e "s|@PROCESSOR@|$CMAKE_PROCESSOR|" \
      -e "s|@BIN@|$HERE/bin|" -e "s|@PREFIX@|$DEPS/install|" \
      "$HERE/toolchain.cmake.in" > "$TOOLCHAIN"
  CMAKE_TARGET="-DCMAKE_TOOLCHAIN_FILE=$TOOLCHAIN"
else
  CMAKE_TARGET="-DCMAKE_C_COMPILER=$HERE/bin/zig-cc -DCMAKE_CXX_COMPILER=$HERE/bin/zig-cxx"
fi

# CMAKE_POLICY_VERSION_MINIMUM: CMake 4 refuses the pre-3.5 cmake_minimum_required that
# HDF5 1.14, yaml-cpp and gRPC's bundled zlib still declare.
#
# CMAKE_INSTALL_LIBDIR: an explicit -target leaves CMAKE_LIBRARY_ARCHITECTURE empty, and
# GNUInstallDirs then falls back to lib64 on any 64-bit target. b2 installs to lib regardless,
# so leaving this unset splits the closure across two directories and merge-deps.sh silently
# merges Boost alone.
CMAKE_COMMON="$CMAKE_TARGET \
 -DCMAKE_CXX_STANDARD=17 \
 -DCMAKE_BUILD_TYPE=Release \
 -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
 -DBUILD_SHARED_LIBS=OFF \
 -DCMAKE_INSTALL_LIBDIR=lib \
 -DCMAKE_INSTALL_PREFIX=$DEPS/install"

cmake_build() {  # $1 = source dir, $2 = build subdir name, $3... = extra -D flags
  cmake_src=$1 cmake_name=$2
  shift 2
  # A build directory remembers the source directory it was configured from, and refuses to be
  # reused for another one. That is a correct thing for CMake to do and an unhelpful thing to
  # hit: a dependency moving between external/ and libcxx-src/ is a repository change, not a
  # user error, and $BUILD outlives it because the source tree is shared between flavors. The
  # cache is disposable -- drop it rather than making everyone delete it by hand.
  if [ -f "$BUILD/$cmake_name/CMakeCache.txt" ] && ! grep -qxF \
       "CMAKE_HOME_DIRECTORY:INTERNAL=$cmake_src" "$BUILD/$cmake_name/CMakeCache.txt"; then
    echo "$cmake_name: cached source directory has moved -- reconfiguring from scratch"
    rm -rf "$BUILD/$cmake_name"
  fi
  cmake -S "$cmake_src" -B "$BUILD/$cmake_name" -G Ninja $CMAKE_COMMON "$@"
  cmake --build "$BUILD/$cmake_name" -j"$(nproc)"
  cmake --install "$BUILD/$cmake_name"
}
