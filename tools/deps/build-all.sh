#!/bin/sh
# Every recipe for one flavor, in order. Hours, and no step is incremental beyond what the
# underlying build system caches: re-running is cheap only where ninja and b2 make it cheap.
set -e
FLAVOR=${1:-x86_64-linux-gnu}
HERE=$(dirname "$0")

# $XDYN_DEPS_STEPS names a subset, for probing an environment without paying for gRPC: the
# expensive steps are the last three, and everything that makes a *sandbox* fail -- an absent
# /usr/bin/env, no network, a read-only $HOME, a zig cache with nowhere to go -- fails in the
# first two.
for step in ${XDYN_DEPS_STEPS:-fetch-sources build-host-tools build-yaml-cpp build-gtest build-hdf5 build-boost build-grpc merge-deps}; do
  echo "### $FLAVOR: $step"
  # Through `sh`, not directly: a recipe's executable bit is one more thing that has to survive
  # git's index and a store copy, and this loop does not need it to.
  sh "$HERE/$step.sh" "$FLAVOR"
done
