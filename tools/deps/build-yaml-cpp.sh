#!/bin/sh
# yaml-cpp comes from libcxx-src/ like every other upstream, pinned to a tag by
# fetch-sources.sh. It used to be an external/ submodule; see that script for why it is not.
set -e
FLAVOR=${1:-x86_64-linux-gnu}
. "$(dirname "$0")/common.sh"

cmake_build "$SRC/yaml-cpp" yaml-cpp \
  -DYAML_CPP_BUILD_TESTS=OFF \
  -DYAML_CPP_BUILD_TOOLS=OFF \
  -DYAML_BUILD_SHARED_LIBS=OFF
