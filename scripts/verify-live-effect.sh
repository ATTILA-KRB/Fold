#!/bin/zsh
# Requires a built app, logged-in desktop and Screen Recording permission.
# Briefly bends the desktop three times; no screen content is saved.
set -euo pipefail
cd "${0:A:h}/.."
verification_directory=$(mktemp -d -t fold-live-tests)
trap 'rm -rf "$verification_directory"' EXIT
verification_app="$verification_directory/FoldLiveTests.app"
mkdir -p "$verification_app/Contents/MacOS" "$verification_app/Contents/Resources"
cp build/Build/Products/Release/Fold.app/Contents/Resources/default.metallib "$verification_app/Contents/Resources/"
cat > "$verification_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FoldLiveTests</string>
<key>CFBundleIdentifier</key><string>com.attila-krb.FoldLiveTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library \
  Fold/AppModel.swift Fold/BendMath.swift Fold/DesktopCapture.swift \
  Fold/LidSensor.swift Fold/Renderer.swift Tests/LiveEffectRegression.swift \
  -o "$verification_app/Contents/MacOS/FoldLiveTests"
"$verification_app/Contents/MacOS/FoldLiveTests"
