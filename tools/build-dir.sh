#!/bin/sh
# Print the build tree build.zig installed into for this host: build/<arch>-<os>-<abi>.
#
#   sh tools/build-dir.sh            -> /path/to/repo/build/x86_64-linux-gnu
#
# Those are *zig's* target names, not uname's (uname says arm64/Darwin, zig says
# aarch64/macos). Rather than reimplement zig's triple logic, derive the plausible candidates
# from uname and pick whichever was actually built — that also settles gnu-vs-musl without
# having to detect the libc. Hardcoding x86_64-linux-gnu instead is what makes a task point
# silently at nothing on any other host.
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case $(uname -m) in
    x86_64 | amd64)  arch=x86_64 ;;
    arm64 | aarch64) arch=aarch64 ;;
    *)               arch=$(uname -m) ;;
esac

case $(uname -s) in
    Darwin) candidates="$arch-macos-none" ;;
    Linux)  candidates="$arch-linux-gnu $arch-linux-musl" ;;
    *)      candidates="$arch-linux-gnu" ;;
esac

for c in $candidates; do
    if [ -d "$repo/build/$c" ]; then
        printf '%s' "$repo/build/$c"
        exit 0
    fi
done

# Nothing built for this host. Print the first candidate anyway, so the caller's "no such
# file" names the path that was expected instead of failing on an empty string.
set -- $candidates
printf '%s' "$repo/build/$1"
