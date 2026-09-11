#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
verification_binary=$(mktemp -t fold-tests)
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" Fold/BendMath.swift Tests/main.swift -o "$verification_binary"
"$verification_binary"
./scripts/verify-lifecycle.sh
app_path="$PWD/build/Build/Products/Release/Fold.app"
codesign --verify --deep --strict "$app_path"
"$app_path/Contents/MacOS/Fold" --sensor-check
"$app_path/Contents/MacOS/Fold" --render-proof verification/frames
# The shader compiles whatever it is told to; only pixels show that the desktop
# folds without folding into flat black.
xcrun swift scripts/verify-frames.swift verification/frames
if command -v ffmpeg >/dev/null; then
  ffmpeg -y -hide_banner -loglevel error -framerate 30 -i verification/frames/frame-%03d.png -c:v libx264 -pix_fmt yuv420p -crf 18 verification/fold-preview.mp4
fi
