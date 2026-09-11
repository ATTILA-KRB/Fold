#!/bin/zsh
# Requires a logged-in Mac desktop and Screen Recording permission.
set -euo pipefail
cd "${0:A:h}/.."
verification_binary=$(mktemp -t fold-capture-tests)
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library Fold/DesktopCapture.swift Fold/Renderer.swift Fold/BendMath.swift Tests/CaptureRegression.swift -o "$verification_binary"
"$verification_binary"
