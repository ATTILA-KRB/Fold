#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
app_path="${APP_PATH:-$PWD/build/Build/Products/Release/Fold.app}"
dmg_path="${DMG_OUTPUT:-$PWD/build/Fold-macOS.dmg}"
[[ -d "$app_path" ]] || { print -u2 'Build Fold with scripts/build.sh first.'; exit 1; }
mkdir -p "${dmg_path:h}"
if [[ ! -x build/dmg-tools/bin/dmgbuild ]]; then
  python3 -m venv build/dmg-tools
  build/dmg-tools/bin/pip install 'dmgbuild==1.6.5'
fi
xcrun swift scripts/dmg-background.swift "$PWD/build/dmg-artwork"
build/dmg-tools/bin/dmgbuild -s packaging/dmg-settings.py \
  -D app="$app_path" -D background="$PWD/build/dmg-artwork/background.png" \
  Fold "$dmg_path"
