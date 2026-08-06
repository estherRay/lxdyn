#!/bin/sh
# Fails with a pointer to bootstrap instead of letting the build die deep in a compile or
# hand protoc a literal '*.proto'. Deliberately not `depends = ["setup"]`: setup resets every
# submodule to its committed pin, which would discard a checkout being tested.
set -e
for path in "$@"; do
    [ -e "$path" ] && continue
    echo "missing: $path" >&2
    echo "The submodules are not checked out. Run:  mise run bootstrap" >&2
    exit 1
done
