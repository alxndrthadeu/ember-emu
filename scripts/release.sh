#!/bin/bash
# After a version's PR is merged into main: tags the merge commit and
# publishes a GitHub Release with that version's notes from CHANGELOG.md.
#   scripts/release.sh 1.2.0
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/release.sh <version>}"
tag="v$version"

git fetch origin --tags
git switch main
git pull --ff-only
configured=$(sed -nE 's/.*MARKETING_VERSION: "?([0-9.]+)"?.*/\1/p' project.yml | head -1)
[[ "$configured" == "$version" ]] || { echo "project.yml says $configured, not $version" >&2; exit 1; }
git rev-parse "$tag" >/dev/null 2>&1 && { echo "$tag already exists" >&2; exit 1; }

# This version's section of the changelog, without its heading.
notes=$(awk -v v="$version" '
  $0 ~ "^## \\[" v "\\]" { on = 1; next }
  on && /^## \[/ { exit }
  on && /^\[[0-9]/ { exit }
  on { print }' CHANGELOG.md)
[[ -n "${notes//[[:space:]]/}" ]] || { echo "CHANGELOG.md has no notes for $version" >&2; exit 1; }

git tag -a "$tag" -m "Ember $version"
git push origin "$tag"
gh release create "$tag" --title "Ember $version" --notes "$notes" --verify-tag
