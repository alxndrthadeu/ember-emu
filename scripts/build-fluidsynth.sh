#!/bin/sh
# Builds FluidSynth (LGPL-2.1) as a static library for iOS, next to the
# engine's other dependencies, so the engine plays MIDI.
#
# The engine normally dlopens @rpath/libfluidsynth.dylib, and the App
# Store takes no loose dylibs. With FluidSynth in the deps tree,
# scripts/patch-engine.sh compiles the core with SHARED_FLUID, which
# calls FluidSynth directly, and the app links libfluidsynth.a.
#
# Usage: scripts/build-fluidsynth.sh [iphonesimulator|iphoneos ...]
#   (default: both). Then run scripts/patch-engine.sh and rebuild
#   the core: (cd deps && make -f <sdk>.make mkxp-core)
set -eu

ENGINE="${EMBER_ENGINE:-$HOME/Developer/ember-engine}"
VERSION=v2.5.7
SRC="$ENGINE/deps/sources/fluidsynth"

if [ ! -d "$SRC" ]; then
    git clone -q --depth 1 --branch "$VERSION" https://github.com/FluidSynth/fluidsynth.git "$SRC"
fi

# The General MIDI instruments the synthesizer plays (GeneralUser GS,
# free to redistribute; license in Ember/Resources/Licenses). Too big
# for git: scripts/embed-engine.sh copies it into the app.
SOUNDFONT="$ENGINE/deps/downloads/GeneralUser-GS.sf2"
if [ ! -f "$SOUNDFONT" ]; then
    curl -sfL -o "$SOUNDFONT" "https://raw.githubusercontent.com/mrbumpy409/GeneralUser-GS/main/GeneralUser-GS.sf2"
fi

# Memory: the engine starts two synthesizers, and by default each one
# holds every sample of the soundfont. With dynamic sample loading a
# synthesizer loads only the instruments a song selects. The engine
# sets no such option, so the default changes here, in the copy of
# FluidSynth Ember builds (the check stops the build if the line moves).
SYNTH_C="$SRC/src/synth/fluid_synth.c"
DEFAULT_OFF='"synth.dynamic-sample-loading", 0, 0, 1'
DEFAULT_ON='"synth.dynamic-sample-loading", 1, 0, 1'
if grep -qF "$DEFAULT_OFF" "$SYNTH_C"; then
    sed -i '' "s/$DEFAULT_OFF/$DEFAULT_ON/" "$SYNTH_C"
fi
grep -qF "$DEFAULT_ON" "$SYNTH_C" || { echo "error: dynamic-sample-loading default not found in $SYNTH_C" >&2; exit 1; }

[ "$#" -eq 0 ] && set -- iphonesimulator iphoneos

for SDK in "$@"; do
    PREFIX="$ENGINE/deps/build-$SDK-arm64"
    BUILD="$ENGINE/deps/build-fluidsynth-$SDK"
    if [ "$SDK" = iphonesimulator ]; then
        TARGET=arm64-apple-ios26.0-simulator
    else
        TARGET=arm64-apple-ios26.0
    fi
    rm -rf "$BUILD"
    # Only the synthesizer: no audio drivers (the engine renders the
    # samples itself and plays them through OpenAL), no file output,
    # no network, no shell. cpp11 OSAL: no GLib.
    cmake -S "$SRC" -B "$BUILD" -G "Unix Makefiles" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT="$SDK" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=26.0 \
        -DCMAKE_C_FLAGS="-target $TARGET" \
        -DCMAKE_CXX_FLAGS="-target $TARGET" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$PREFIX" \
        -DBUILD_SHARED_LIBS=OFF -DCMAKE_MACOSX_BUNDLE=OFF \
        -Dosal=cpp11 \
        -Denable-framework=OFF \
        -Denable-coreaudio=OFF -Denable-coremidi=OFF \
        -Denable-sdl3=OFF -Denable-libsndfile=OFF -Denable-aufile=OFF \
        -Denable-network=OFF -Denable-ipv6=OFF -Denable-readline=OFF \
        -Denable-openmp=OFF -Denable-ladspa=OFF -Denable-libinstpatch=OFF \
        -Denable-dbus=OFF -Denable-jack=OFF -Denable-pulseaudio=OFF \
        -Denable-pipewire=OFF -Denable-alsa=OFF -Denable-oss=OFF \
        -Denable-midishare=OFF -Denable-systemd=OFF -Denable-portaudio=OFF \
        -Denable-native-dls=OFF \
        -DCMAKE_DISABLE_FIND_PACKAGE_PkgConfig=ON \
        > "$BUILD.log" 2>&1 || { tail -30 "$BUILD.log"; exit 1; }
    cmake --build "$BUILD" --target libfluidsynth -j 8 >> "$BUILD.log" 2>&1 || { tail -30 "$BUILD.log"; exit 1; }
    mkdir -p "$PREFIX/lib" "$PREFIX/include/fluidsynth"
    lib=$(find "$BUILD" -name 'libfluidsynth*.a' | head -1)
    cp "$lib" "$PREFIX/lib/libfluidsynth.a"
    # fluidsynth.h and version.h are generated; the rest are sources.
    cp "$BUILD/include/fluidsynth.h" "$PREFIX/include/"
    cp "$SRC"/include/fluidsynth/*.h "$PREFIX/include/fluidsynth/"
    cp "$BUILD"/include/fluidsynth/*.h "$PREFIX/include/fluidsynth/"
    echo "fluidsynth: $SDK -> $PREFIX/lib/libfluidsynth.a"
done
