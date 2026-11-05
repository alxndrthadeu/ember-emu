#!/bin/sh
# Copies what the engine reads at run time into the app bundle, the
# same tree the fork's tools/build-test-host-ios.sh assembles:
#
#   Assets.bundle/  shaders, fallback fonts, preload/postload scripts,
#                   controller db, CA bundle
#   Ruby/           the Ruby standard library subsets
#
# Games are not bundled: they are imported in the app (Files app).
#
# Runs as an Xcode build phase. rsync keeps rebuilds fast.
set -eu

ENGINE="${EMBER_ENGINE:?}"
TREE="${EMBER_DEPS:?}"
APP="${TARGET_BUILD_DIR:?}/${UNLOCALIZED_RESOURCES_FOLDER_PATH:?}"

if [ ! -d "$TREE/ruby-stdlib" ]; then
    echo "error: engine not built for ${PLATFORM_NAME}. Run in $ENGINE:" >&2
    echo "error:   tools/build-deps-ios.sh ${PLATFORM_NAME}" >&2
    echo "error:   (cd deps && make -f ${PLATFORM_NAME}.make mkxp-merged mkxp-core)" >&2
    exit 1
fi

ASSETS="$APP/Assets.bundle"
mkdir -p "$ASSETS/Shaders" "$ASSETS/Fonts" "$ASSETS/Preload" "$ASSETS/Postload"

rsync -a --include='*.frag' --include='*.vert' --include='*.h' --exclude='*' \
    "$ENGINE/shader/" "$ASSETS/Shaders/"
rsync -a "$ENGINE/assets/liberation.ttf" "$ENGINE/assets/wqymicrohei.ttf" "$ASSETS/Fonts/"
rsync -a "$ENGINE/assets/gamecontrollerdb.txt" "$ENGINE/assets/icon.png" \
    "$ENGINE/assets/cacert.pem" "$ASSETS/"
rsync -a --delete --include='*.rb' --exclude='*' "$ENGINE/scripts/preload/" "$ASSETS/Preload/"
rsync -a --delete --include='*.rb' --exclude='*' "$ENGINE/scripts/postload/" "$ASSETS/Postload/"

rsync -a --delete "$TREE/ruby-stdlib/" "$APP/Ruby/"

# The engine's license notices, for Ajustes > Licenças.
rsync -a "$TREE/licenses.json" "$APP/EngineLicenses.json"

# MIDI: the soundfont FluidSynth plays (scripts/build-fluidsynth.sh
# downloads it). Without it the game runs with MIDI music silent.
SOUNDFONT="$ENGINE/deps/downloads/GeneralUser-GS.sf2"
if [ -f "$SOUNDFONT" ]; then
    rsync -a "$SOUNDFONT" "$APP/GeneralUser-GS.sf2"
else
    echo "warning: no soundfont; MIDI music will be silent. Run scripts/build-fluidsynth.sh" >&2
fi

# Builds from before the import flow bundled games/ here.
rm -rf "$APP/Games"

# The app ships no game and no RTP: stop the build if any game data
# (test corpus, RTP) ever ends up in the bundle.
leak=$(find "$APP" \( -iname '*.rxdata' -o -iname '*.rvdata' -o -iname '*.rvdata2' \
    -o -iname '*.rgssad' -o -iname '*.rgss2a' -o -iname '*.rgss3a' -o -iname 'Game.ini' \) -print -quit)
if [ -n "$leak" ]; then
    echo "error: game data inside the app bundle: $leak" >&2
    exit 1
fi
