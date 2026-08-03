#!/bin/sh
# Download a prebuilt dependency closure into libcxx-<triple>/, instead of spending hours
# building it with build-all.sh.
#
#   tools/deps/fetch.sh x86_64-linux-gnu   # or: mise run deps:fetch x86_64-linux-gnu
#
# The asset is not content-addressed by its name, so the hash in assets.sha256 is what
# identifies it -- a moved tag or a re-uploaded file is caught here rather than by a
# mysterious link error later. Verification is not optional and has no override.
#
# Overridable for a fork or a local mirror:
#   XDYN_DEPS_REPO=owner/name  XDYN_DEPS_TAG=closures-v1  XDYN_DEPS_URL=file:///path/to/dir
set -e
FLAVOR=${1:-x86_64-linux-gnu}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)

# The published assets still carry the pre-rename names. Renaming a closure's *directory*
# does not change its bytes, and the rule in assets.sha256 is that a new name means a new tag
# and a re-upload -- not worth spending on a rename. The next tag bump, whenever a recipe or
# the zig version or the floor actually changes, publishes them under the triple and this
# table goes away.
case $FLAVOR in
    x86_64-linux-gnu)    ASSET=lxdyn-deps-native.tar.zst ;;
    aarch64-linux-musl)  ASSET=lxdyn-deps-aarch64.tar.zst ;;
    x86_64-windows-gnu)  ASSET=lxdyn-deps-win.tar.zst ;;
    *)
        echo "fetch: unknown flavor '$FLAVOR' -- expected one of:" >&2
        echo "  x86_64-linux-gnu  aarch64-linux-musl  x86_64-windows-gnu" >&2
        exit 1 ;;
esac

SUMS=$HERE/assets.sha256

# One file is the source of truth for both the tag and the hashes, so they cannot drift apart.
TAG=${XDYN_DEPS_TAG:-$(sed -n 's/^# tag: *//p' "$SUMS")}
[ -n "$TAG" ] || { echo "fetch: no '# tag:' line in $SUMS" >&2; exit 1; }
grep -q " $ASSET\$" "$SUMS" || {
    echo "fetch: $SUMS has no entry for $ASSET" >&2
    echo "       tools/deps/pack.sh $FLAVOR prints the line to add." >&2
    exit 1
}

SLUG=${XDYN_DEPS_REPO:-naval-group/lxdyn}
BASE=${XDYN_DEPS_URL:-https://github.com/$SLUG/releases/download/$TAG}
DEST=${XDYN_DEPS:-$REPO/libcxx-$FLAVOR}

# Refuse to overwrite: a closure here may be one someone is midway through testing, and the
# recipes take hours to reproduce it. Moving it aside is the caller's decision, not ours.
[ -e "$DEST" ] && {
    echo "fetch: $DEST already exists -- move it aside first" >&2
    exit 1
}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/xdyn-fetch-XXXXXX")
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

echo "fetching $BASE/$ASSET"
curl --fail --location --progress-bar --output "$WORK/$ASSET" "$BASE/$ASSET"

# -c against the committed sums, filtered to this asset so the other flavors' absence is
# not a failure. --status is deliberately not used: the mismatch line is the diagnostic.
( cd "$WORK" && grep " $ASSET\$" "$SUMS" | sha256sum -c - )

# Unpack beside the destination and rename, so an interrupted run cannot leave a half
# closure at a path build.zig would happily link against.
mkdir -p "$WORK/unpack"
zstd -d -q -c "$WORK/$ASSET" | tar -C "$WORK/unpack" -xf -
mv "$WORK/unpack" "$DEST"

echo "OK -> $DEST"
