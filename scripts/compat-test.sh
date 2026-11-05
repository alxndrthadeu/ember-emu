#!/bin/sh
# Smoke-tests every game in the simulator's Ember library: boots it with
# the sound off, waits for the title, presses Enter a few times to start
# a new game, takes screenshots, quits, and writes a report.
#
# Usage: scripts/compat-test.sh <out dir> [game id ...]
#   Without ids, tests every folder in the simulator's Documents/Games.
#   Needs a Debug build of Ember installed in the booted simulator
#   (EMBER_AUTOLAUNCH / EMBER_KEYS / EMBER_METRICS hooks).
#
# Runs only on this Mac's simulator: it never builds for or installs on
# a device, and the test games stay outside the project and the app.
set -u

OUT="${1:?usage: compat-test.sh <out dir> [game id ...]}"
shift
DEV="${EMBER_SIM:-booted}"
APP=com.alexandrethadeu.ember
BOOT_WAIT="${EMBER_BOOT_WAIT:-20}"
PLAY_WAIT="${EMBER_PLAY_WAIT:-30}"

if [ "$DEV" = booted ]; then
    if ! xcrun simctl list devices booted | grep -q Booted; then
        echo "compat-test: nenhum simulador aberto. Abra um ou passe EMBER_SIM=<udid>." >&2
        exit 1
    fi
elif ! xcrun simctl list devices | grep -q "($DEV)"; then
    echo "compat-test: $DEV não é um simulador deste Mac; o teste só roda no simulador." >&2
    exit 1
fi

mkdir -p "$OUT"
DATA=$(xcrun simctl get_app_container "$DEV" "$APP" data)
GAMES="$DATA/Documents/Games"
LOGS="$DATA/Library/Application Support/Logs"

# Never play music through the Mac while testing.
xcrun simctl spawn "$DEV" defaults write "$APP" settings.gameSound -bool false
xcrun simctl spawn "$DEV" defaults write "$APP" settings.hideWithController -bool false

if [ "$#" -eq 0 ]; then
    set -- $(ls "$GAMES" | tr ' ' '\037')
fi

REPORT="$OUT/report.md"
printf '| Jogo | RGSS | Ruby | Título | Jogo novo | FPS | Erros | Arquivos faltando |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n' > "$REPORT"

for raw in "$@"; do
    id=$(printf '%s' "$raw" | tr '\037' ' ')
    safe=$(printf '%s' "$id" | tr ' /' '__')
    echo "== $id"
    keys="$BOOT_WAIT:enter"
    i=0
    while [ $i -lt 14 ]; do keys="$keys,1.5:enter"; i=$((i + 1)); done

    log="$OUT/$safe.console.log"
    SIMCTL_CHILD_EMBER_AUTOLAUNCH="$id" SIMCTL_CHILD_EMBER_KEYS="$keys" SIMCTL_CHILD_EMBER_METRICS=1 \
        xcrun simctl launch --console-pty --terminate-running-process "$DEV" "$APP" > "$log" 2>&1 &
    launcher=$!
    sleep "$BOOT_WAIT"
    xcrun simctl io "$DEV" screenshot "$OUT/$safe.1-title.png" >/dev/null 2>&1
    sleep "$PLAY_WAIT"
    xcrun simctl io "$DEV" screenshot "$OUT/$safe.2-play.png" >/dev/null 2>&1
    xcrun simctl terminate "$DEV" "$APP" >/dev/null 2>&1
    kill $launcher 2>/dev/null
    wait $launcher 2>/dev/null

    session=$(ls -t "$LOGS/$id/"*.log 2>/dev/null | head -1)
    [ -n "$session" ] && cp "$session" "$OUT/$safe.session.log"
    rgss=$(grep -aoE "RGSS version [0-9]" "$log" | head -1 | grep -oE "[0-9]$")
    ruby=$(grep -aoE "^Ruby: [0-9.]+[^\n]*" "$OUT/$safe.session.log" 2>/dev/null | head -1 | sed 's/Ruby: //')
    fps=$(grep -aoE "ember-metrics\] [0-9]+ fps" "$log" | tail -3 | grep -oE "[0-9]+ fps" | tr '\n' ' ')
    errors=$(grep -acE "^\[erro\]" "$OUT/$safe.session.log" 2>/dev/null); errors=${errors:-0}
    missing=$(grep -aoiE "(Unable to find|No such file|cannot load|Failed to load)[^\n]{0,80}" "$log" | sort -u | head -3 | tr '\n' ';' | sed 's/|/\//g')
    printf '| %s | %s | %s | ![](%s) | ![](%s) | %s | %s | %s |\n' \
        "$id" "${rgss:-?}" "${ruby:-?}" "$safe.1-title.png" "$safe.2-play.png" "${fps:-?}" "$errors" "${missing:-}" >> "$REPORT"
done

xcrun simctl spawn "$DEV" defaults delete "$APP" settings.gameSound 2>/dev/null
echo "Relatório: $REPORT"
