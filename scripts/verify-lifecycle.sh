#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
verification_binary=$(mktemp -t fold-lifecycle-tests)
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library Fold/AppModel.swift Fold/BendMath.swift Tests/AppModelRegression.swift -o "$verification_binary"
"$verification_binary"
