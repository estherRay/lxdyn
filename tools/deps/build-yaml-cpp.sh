#!/bin/sh
# yaml-cpp comes from this repo's external/ submodule so that the closure and the CMake lane
# compile the same sources. It is also what ties a closure to one clone: change the submodule
# pin and the closure is stale.
set -e
FLAVOR=${1:-native}
. "$(dirname "$0")/common.sh"

[ -f "$REPO/external/yaml-cpp/CMakeLists.txt" ] || {
  echo "external/yaml-cpp is empty -- run 'mise run setup' first" >&2
  exit 1
}

cmake_build "$REPO/external/yaml-cpp" yaml-cpp \
  -DYAML_CPP_BUILD_TESTS=OFF \
  -DYAML_CPP_BUILD_TOOLS=OFF \
  -DYAML_BUILD_SHARED_LIBS=OFF
