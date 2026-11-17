#!/bin/bash
# Runs Ember's unit tests on an iPhone simulator (the first available
# one unless EMBER_TEST_DEVICE names a UDID). Needs the engine built for
# iphonesimulator, like the app.
#
#   scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."

device="${EMBER_TEST_DEVICE:-}"
if [[ -z "$device" ]]; then
    device=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"].startswith("iPhone") and d.get("isAvailable"):
            print(d["udid"]); sys.exit()
')
fi
[[ -n "$device" ]] || { echo "No iPhone simulator found." >&2; exit 1; }

xcodegen generate >/dev/null
log=$(mktemp -t ember-tests)
status=0
xcodebuild test -project Ember.xcodeproj -scheme Ember \
    -destination "id=$device" -disableAutomaticPackageResolution -quiet >"$log" 2>&1 || status=$?
grep -vE "appintentsmetadataprocessor|IOSurfaceClientSetSurfaceNotify" "$log" || true
rm -f "$log"
exit $status
