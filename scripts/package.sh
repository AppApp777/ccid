#!/bin/bash
# Builds the release download: dist/ccid-macos.zip (Apple silicon and Intel) and dist/SHA256SUMS.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

UNIVERSAL=1 scripts/build-app.sh >/dev/null
cd dist
rm -f ccid-macos.zip SHA256SUMS.txt
ditto -c -k --keepParent ccid.app ccid-macos.zip
shasum -a 256 ccid-macos.zip > SHA256SUMS.txt
cat SHA256SUMS.txt
