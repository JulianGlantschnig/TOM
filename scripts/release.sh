#!/bin/zsh
# Baut die Release-Version und packt sie als ZIP für GitHub Releases.
# Aufruf: scripts/release.sh 1.1
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:?Version angeben, z. B. scripts/release.sh 1.1}"
xcodebuild -project Timecounter.xcodeproj -target Timecounter -configuration Release \
  MARKETING_VERSION="$version" SYMROOT=build clean build | grep -E "error|BUILD"

mkdir -p dist
zip="dist/Timecounter-$version.zip"
rm -f "$zip"
ditto -c -k --keepParent build/Release/Timecounter.app "$zip"
echo "$zip"
shasum -a 256 "$zip"
