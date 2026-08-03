#!/bin/sh
# Every recipe for one flavor, in order. Hours, and no step is incremental beyond what the
# underlying build system caches: re-running is cheap only where ninja and b2 make it cheap.
set -e
FLAVOR=${1:-x86_64-linux-gnu}
HERE=$(dirname "$0")

for step in fetch-sources build-yaml-cpp build-gtest build-hdf5 build-boost build-grpc merge-deps; do
  echo "### $FLAVOR: $step"
  "$HERE/$step.sh" "$FLAVOR"
done
