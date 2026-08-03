#!/bin/sh
# googletest through its own CMake build, for every flavor.
#
# An earlier native-only recipe compiled gtest-all.cc and gmock-all.cc by hand instead:
# googletest hands gtest's include directory to gmock as -isystem, and a zig cc with no -target
# puts CPATH ahead of any -isystem directory. Inside `nix develop` that meant gmock compiled
# against the flake's gtest 1.17 headers, which lack the macros 1.15's sources expect. Naming
# the target removes CPATH from the search path entirely, so there is nothing left to work
# around -- which is also why the cross flavors never had the problem.
#
# The *_main archives this installs are dropped at merge time: run_all_tests defines its own.
set -e
FLAVOR=${1:-x86_64-linux-gnu}
. "$(dirname "$0")/common.sh"

cmake_build "$SRC/googletest" googletest -DBUILD_GMOCK=ON -DINSTALL_GTEST=ON
