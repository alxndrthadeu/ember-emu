#!/bin/bash
# Quick checks that need no engine: run before a PR, and on every PR in
# GitHub Actions (.github/workflows/checks.yml). The app itself and its
# unit tests (EmberTests) build only on a Mac with the engine:
#   xcodebuild test -project Ember.xcodeproj -scheme Ember \
#     -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
set -uo pipefail
cd "$(dirname "$0")/.."
failed=0
fail() { echo "✗ $*"; failed=1; }
ok() { echo "✓ $*"; }

# Every string has English and Spanish.
missing=$(python3 - <<'PY'
import json
d = json.load(open("Ember/Resources/Localizable.xcstrings"))
for key, value in sorted(d["strings"].items()):
    if value.get("shouldTranslate") is False or value.get("extractionState") == "stale":
        continue
    locs = value.get("localizations", {})
    for lang in ("en", "es"):
        unit = locs.get(lang, {}).get("stringUnit") or {}
        plural = locs.get(lang, {}).get("variations")
        if not unit.get("value") and not plural:
            print(f"{lang}: {key[:70]}")
PY
)
if [[ -n "$missing" ]]; then fail "strings without a translation:"; echo "$missing" | head -20; else ok "translations"; fi

stale=$(python3 -c 'import json;d=json.load(open("Ember/Resources/Localizable.xcstrings"));print(sum(1 for v in d["strings"].values() if v.get("extractionState")=="stale"))')
[[ "$stale" == "0" ]] && ok "no unused strings" || fail "$stale unused strings in Localizable.xcstrings"

# Ruby: Ember's engine scripts and the demo game.
bad=0
for file in Ember/Resources/EngineScripts/*.rb demo/scripts/*.rb scripts/*.rb fastlane/Fastfile; do
    [[ -f "$file" ]] || continue
    ruby -c "$file" >/dev/null 2>&1 || { fail "Ruby syntax: $file"; bad=1; }
done
[[ $bad == 0 ]] && ok "Ruby syntax"

# The scripts that run inside games also run on Ruby 1.8 and 1.9
# (Essentials, RPG Maker XP/VX): no syntax those can't read.
old_ruby=$(python3 - Ember/Resources/EngineScripts/*.rb demo/scripts/*.rb <<'PY'
import re, sys
# Safe navigation, stabby lambdas, squiggly heredocs, `key: value` hashes
# and keyword arguments: none of them parse on Ruby 1.8.
patterns = [(r"&\.", "&."), (r"->\s*[({]", "->"), (r"<<~", "<<~"),
            (r"(^|[{(,|]\s*)[a-z_][a-zA-Z0-9_]*: (?!:)", "key: value")]
for path in sys.argv[1:]:
    for number, line in enumerate(open(path, encoding="utf-8"), 1):
        code = re.sub(r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\"", "''", line.split(" #")[0])
        if code.lstrip().startswith("#"):
            continue
        for pattern, name in patterns:
            if re.search(pattern, code):
                print(f"{path}:{number}: {name}: {line.strip()[:80]}")
PY
)
if [[ -n "$old_ruby" ]]; then fail "syntax Ruby 1.8/1.9 can't read:"; echo "$old_ruby" | head -10; else ok "Ruby 1.8/1.9 syntax"; fi

# Shell scripts.
bad=0
for file in scripts/*.sh; do
    bash -n "$file" 2>/dev/null || { fail "shell syntax: $file"; bad=1; }
done
[[ $bad == 0 ]] && ok "shell syntax"

# The version in project.yml has a changelog section.
version=$(sed -nE 's/.*MARKETING_VERSION: "?([0-9.]+)"?.*/\1/p' project.yml | head -1)
grep -q "^## \[$version\]" CHANGELOG.md && ok "CHANGELOG has $version" || fail "CHANGELOG.md has no section for $version"

# Credentials never go in.
if git ls-files | grep -E '(\.p8|fastlane/\.env|Signing\.local\.xcconfig)$' >/dev/null; then
    fail "a credential file is tracked by git"
else
    ok "no credentials in git"
fi

exit $failed
