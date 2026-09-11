#!/bin/zsh
# Requires a logged-in Mac desktop and Screen Recording permission.
set -euo pipefail
cd "${0:A:h}/.."
verification_binary=$(mktemp -t fold-capture-tests)
trap 'rm -f "$verification_binary"' EXIT
xcrun swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -parse-as-library Fold/DesktopCapture.swift Fold/Renderer.swift Fold/BendMath.swift Tests/CaptureRegression.swift -o "$verification_binary"
"$verification_binary"

# Windows and lifecycle: enable, fold, pause. Then assert that pausing left no
# overlay panel behind — a survivor sits above the status bar showing a frozen
# desktop and hides the menu bar item, and nothing else notices.
app_path="$PWD/build/Build/Products/Release/Fold.app"
[[ -d "$app_path" ]] || { print -u2 'Build Fold first: ./scripts/build.sh --signed'; exit 1; }
smoke_report=/tmp/fold-smoke.txt
rm -f "$smoke_report"
"$app_path/Contents/MacOS/Fold" --smoke --background > /dev/null 2>&1 &
sleep 7
pkill -f "MacOS/Fold --smoke" 2>/dev/null || true
[[ -f "$smoke_report" ]] || { print -u2 'The smoke run produced no report'; exit 1; }
cat "$smoke_report"

# Extract by pattern, not by field: the report is one line holding several
# key=value pairs, so awk -F= $2 returns "frames" for every key and the check
# below could never fail.
field() { grep -o "$2=[0-9]*" "$1" | head -1 | cut -d= -f2 }
folds=$(field "$smoke_report" overlaysVisibleWhileFolded)
after=$(field "$smoke_report" overlaysVisibleAfterDisable)
[[ "$folds" -ge 1 ]] && print "PASS: the overlay counter sees a panel while folded ($folds)" \
  || { print -u2 "FAIL: the overlay counter saw no panel while folded, so the check below proves nothing"; exit 1; }
[[ "$after" -eq 0 ]] && print "PASS: pausing left no overlay window behind" \
  || { print -u2 "FAIL: $after overlay window(s) still on screen after pausing"; exit 1; }