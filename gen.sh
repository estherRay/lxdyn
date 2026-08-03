#!/bin/sh
# Codegen prerequisite for the build: produces generated
# sources into the gitignored build/gen/, plus the SSC umbrella headers in-tree via
# SSC's own script. Run before `zig build`. Idempotent.
set -e
REPO=$(cd "$(dirname "$0")" && pwd)
cd "$REPO"
# Host closure, NOT the target one: protoc/grpc_cpp_plugin run on this machine, and the
# code they emit is target-independent. So this stays the native closure even when
# build.zig is pointed elsewhere with -Ddeps/$XDYN_DEPS for a cross build.
#
# In-repo, like build.zig's default and where tools/deps/ builds it. It used to say
# $REPO/../libcxx-native, one level up, which resolves only on a machine that happens to
# keep a closure beside the checkout -- and silently picks a different one from the build.
DEPS="${XDYN_DEPS_HOST:-$REPO/libcxx-native}"
GEN=build/gen
mkdir -p "$GEN/proto"

# 1. SSC umbrella headers — SSC's own generator, output in-tree (SSC unmodified).
( cd external/ssc/ssc && sh generate_module_header.sh )

# 2. git SHA stamp (the over-built GitShaGenStep, demoted to a tiny script).
SHA=$(git rev-parse HEAD)
cat > "$GEN/get_git_sha.c" <<EOF
#include "xdyn/get_git_sha/get_git_sha.h"
const char* get_git_sha()
{
    return "$SHA";
}
EOF

# 3. protobuf / gRPC — host protoc + grpc_cpp_plugin from the libc++ deps build,
#    version-matched to the linked libprotobuf/libgrpc.
PROTOC="$DEPS/install/bin/protoc"
PLUGIN="$DEPS/install/bin/grpc_cpp_plugin"
if [ ! -x "$PROTOC" ] || [ ! -x "$PLUGIN" ]; then
  echo "gen.sh: protoc/grpc_cpp_plugin not found under $DEPS/install/bin" >&2
  echo "        set \$XDYN_DEPS_HOST to the native libc++ closure root." >&2
  exit 1
fi
for p in wave_types wave_grpc force controller cosimulation model_exchange; do
  "$PROTOC" --grpc_out="$GEN/proto" --cpp_out="$GEN/proto" -Iinterfaces/proto \
    --plugin=protoc-gen-grpc="$PLUGIN" "interfaces/proto/$p.proto"
done

# The demo embedding used to be step 4 here (tools/embed_demo.py). It is gone: the
# scripts are #embed-ed by xdyn/observers_and_api/demo_scripts.cpp, which is a normal
# TU with real dependency tracking. That was also this script's last `python3` — the
# build now needs no interpreter at all.

echo "GEN_OK -> $GEN"
