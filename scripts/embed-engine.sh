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

# Builds from before the import flow bundled games/ here.
rm -rf "$APP/Games"
