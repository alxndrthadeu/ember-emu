#!/bin/bash
# Sets the app version and build in project.yml and regenerates the
# Xcode project.
#   scripts/bump-version.sh 1.2.0        version 1.2.0, build + 1
#   scripts/bump-version.sh 1.2.0 7      version 1.2.0, build 7
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?usage: scripts/bump-version.sh <version> [build]}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.0" >&2; exit 1; }
current_build=$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "?([0-9]+)"?.*/\1/p' project.yml | head -1)
build="${2:-$((current_build + 1))}"

sed -i '' -E "s/(MARKETING_VERSION: )\"?[0-9.]+\"?/\1\"$version\"/" project.yml
sed -i '' -E "s/(CURRENT_PROJECT_VERSION: )\"?[0-9]+\"?/\1\"$build\"/" project.yml
xcodegen generate >/dev/null
echo "Ember $version (build $build)"
