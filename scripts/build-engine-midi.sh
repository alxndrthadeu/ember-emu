#!/bin/sh
# Rebuilds the engine core with MIDI: SHARED_FLUID makes it call the
# static FluidSynth (scripts/build-fluidsynth.sh) instead of dlopening
# a dylib. No engine source changes: the core build takes
# EXTRA_CORE_CFLAGS.
#
# Flags alone do not trigger a rebuild, so the objects that include the
# FluidSynth headers are removed first.
#
# Usage: scripts/build-engine-midi.sh [iphonesimulator|iphoneos ...]
#   (default: iphonesimulator)
set -eu

ENGINE="${EMBER_ENGINE:-$HOME/Developer/ember-engine}"
[ "$#" -eq 0 ] && set -- iphonesimulator

for SDK in "$@"; do
    TREE="$ENGINE/deps/build-$SDK-arm64"
    if [ ! -f "$TREE/lib/libfluidsynth.a" ]; then
        echo "error: no FluidSynth for $SDK. Run scripts/build-fluidsynth.sh $SDK" >&2
        exit 1
    fi
    for name in alstream audio fluid-fun midisource sharedstate; do
        rm -f "$TREE/engine-obj/core/audio__$name.o" "$TREE/engine-obj/core/$name.o"
    done
    rm -f "$TREE/lib/libmkxpz-core.a"
    (cd "$ENGINE/deps" && EXTRA_CORE_CFLAGS=-DSHARED_FLUID make -f "$SDK.make" mkxp-core)
    if nm "$TREE/lib/libmkxpz-core.a" 2>/dev/null | grep -q " U _new_fluid_synth"; then
        echo "engine core ($SDK): MIDI on"
    else
        echo "error: the core does not call FluidSynth directly" >&2
        exit 1
    fi
done
