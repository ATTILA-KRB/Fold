#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
xcodegen generate
xcodebuild -project Fold.xcodeproj -scheme Fold -configuration Release -derivedDataPath build CODE_SIGN_IDENTITY=- build
