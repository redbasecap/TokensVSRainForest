#!/usr/bin/env bash
# Builds universal release archives into dist/: the app and the `rainforest` CLI.
#   VERSION=0.1.0 ./Scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"

swift test
VERSION="$VERSION" ./Scripts/package_app.sh --universal
rm -rf dist && mkdir -p dist
ditto -c -k --keepParent TokensVSRainForest.app "dist/TokensVSRainForest-${VERSION}-macOS-universal.zip"

CLI_DIR=$(mktemp -d)/rainforest-${VERSION}
mkdir -p "$CLI_DIR"
cp .build/apple/Products/Release/rainforest "$CLI_DIR/rainforest"
codesign --force --sign - "$CLI_DIR/rainforest" >/dev/null
cp LICENSE "$CLI_DIR/"
ditto -c -k --keepParent "$CLI_DIR" "dist/rainforest-cli-${VERSION}-macOS-universal.zip"

(cd dist && shasum -a 256 *.zip > SHA256SUMS.txt)
ls -la dist
cat dist/SHA256SUMS.txt
