#!/bin/sh
# Takes the raw App Store screenshots in a simulator, with the sound
# off: the demo game (title, talk, Ember's in-game menu, the game's
# menu), the library and the import screen with Wi-Fi on. One set
# per language. scripts/compose-screenshots.swift then frames them.
#
# Usage: scripts/store-screenshots.sh <simulator udid> <out dir> [lang ...]
#   The simulator should be a clean iPhone 17 Pro Max (6.9", 1320×2868)
#   with only the demo game, so no other game shows up in the shots.
#   Langs default to pt-BR en es.
set -u

DEV="${1:?usage: store-screenshots.sh <udid> <out dir> [lang ...]}"
OUT="${2:?usage: store-screenshots.sh <udid> <out dir> [lang ...]}"
shift 2
[ "$#" -eq 0 ] && set -- pt-BR en es
APP=com.alexandrethadeu.ember
DEMO="A Última Brasa"
LOG="$OUT/.run.log"
mkdir -p "$OUT"

xcrun simctl status_bar "$DEV" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" >/dev/null 2>&1
xcrun simctl spawn "$DEV" defaults write "$APP" settings.gameSound -bool false
xcrun simctl spawn "$DEV" defaults write "$APP" settings.hideWithController -bool false

# Runs the app with the given environment (NAME=value ...), waits until
# the key script has sent `keys` keys (0: just wait), lets things
# settle for `settle` seconds, and saves a screenshot.
shot() {
    lang=$1 name=$2 keys=$3 settle=$4
    shift 4
    : > "$LOG"
    env "$@" xcrun simctl launch --console-pty --terminate-running-process "$DEV" "$APP" \
        -AppleLanguages "($lang)" -AppleLocale "$lang" > "$LOG" 2>&1 &
    launcher=$!
    if [ "$keys" -gt 0 ]; then
        i=0
        while [ $i -lt 90 ] && [ "$(grep -ac 'ember-keys' "$LOG")" -lt "$keys" ]; do
            sleep 0.5; i=$((i + 1))
        done
    fi
    sleep "$settle"
    xcrun simctl io "$DEV" screenshot "$OUT/$lang/$name.png" >/dev/null 2>&1
    xcrun simctl terminate "$DEV" "$APP" >/dev/null 2>&1
    kill $launcher 2>/dev/null
    wait $launcher 2>/dev/null
    echo "  $lang/$name"
}

for lang in "$@"; do
    mkdir -p "$OUT/$lang"
    echo "== $lang"
    # The game's title screen (a harmless key marks when it is up).
    shot "$lang" 1-game-title 1 1.5 \
        SIMCTL_CHILD_EMBER_AUTOLAUNCH="$DEMO" SIMCTL_CHILD_EMBER_KEYS="13:left"
    # Talking to the cat by the fire.
    shot "$lang" 2-game-talk 7 2.5 \
        SIMCTL_CHILD_EMBER_AUTOLAUNCH="$DEMO" \
        SIMCTL_CHILD_EMBER_KEYS="12:enter,3:up,0.6:up,0.6:up,0.6:left,0.6:left,0.8:enter"
    # Ember's own menu over the paused game (this also saves the cover).
    shot "$lang" 3-ember-menu 3 4 \
        SIMCTL_CHILD_EMBER_AUTOLAUNCH="$DEMO" SIMCTL_CHILD_EMBER_KEYS="12:enter,3:up,0.6:left" \
        SIMCTL_CHILD_EMBER_AUTOMENU=18
    # The game's own menu.
    shot "$lang" 4-game-menu 4 1.5 \
        SIMCTL_CHILD_EMBER_AUTOLAUNCH="$DEMO" SIMCTL_CHILD_EMBER_KEYS="12:enter,3:up,0.6:up,1:esc"
    # The library and the import screen with Wi-Fi on.
    shot "$lang" 5-library 0 7
    shot "$lang" 6-import 0 7 SIMCTL_CHILD_EMBER_SHOW=import SIMCTL_CHILD_EMBER_WIFI=1
done
rm -f "$LOG"
