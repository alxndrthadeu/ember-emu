#!/bin/sh
# Applies Ember's engine patches (engine-patches/*.patch) to the
# engine checkout. Safe to run again: a patch already in place is
# skipped. Rebuild the core afterwards: (cd deps && make -f <sdk>.make mkxp-core).
set -eu

ENGINE="${EMBER_ENGINE:-$HOME/Developer/ember-engine}"
PATCHES="$(cd "$(dirname "$0")/.." && pwd)/engine-patches"

for patch in "$PATCHES"/*.patch; do
    name=$(basename "$patch")
    if git -C "$ENGINE" apply --reverse --check "$patch" 2>/dev/null; then
        echo "engine: $name already applied"
    else
        git -C "$ENGINE" apply "$patch"
        echo "engine: $name applied"
    fi
done
