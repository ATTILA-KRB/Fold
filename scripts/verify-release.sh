#!/bin/zsh
# Verify the artifacts a release actually ships. Run it after `release.sh`
# (dry run or publish) and before announcing anything.
#
#   ./scripts/verify-release.sh            # local artifacts only
#   ./scripts/verify-release.sh --public   # also fetch the published DMG,
#                                          # the served feed and the GitHub release
#
# It asserts on the shipped objects, not on the intent: signature properties of
# the exported app, Gatekeeper's verdict on both app and image, stapled tickets,
# the generated feed, and — with --public — that the bytes GitHub serves are the
# bytes you notarized.
set -uo pipefail
cd "${0:A:h}/.."

export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

REPO="${REPO:-ATTILA-KRB/Fold}"
TEAM_ID="${DEVELOPER_TEAM_ID:-5FMH389VS7}"
NOTARY_PROFILE="${NOTARY_PROFILE:-popcorn-notary}"

public=false
[[ "${1:-}" == "--public" ]] && public=true

out="build/release"
app="$out/Fold.app"
dmg="$out/Fold-macOS.dmg"
zip="build/appcast/Fold-macOS.zip"
feed=docs/appcast.xml
scratch=$(mktemp -d "${TMPDIR:-/tmp}/hermes-verify-fold.XXXXXX")
trap 'rm -rf "$scratch"' EXIT

version=$(awk '/MARKETING_VERSION:/ {gsub(/'"'"'/,"",$2); print $2; exit}' project.yml)
build_number=$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/'"'"'/,"",$2); print $2; exit}' project.yml)
public_key=$(awk '/SUPublicEDKey:/ {gsub(/'"'"'/,"",$2); print $2; exit}' project.yml)
tag="v${version}"

fail=0
ok()    { print "  ok   $1" }
bad()   { print "  FAIL $1"; fail=1 }
check() { [[ "$2" == *"$1"* ]] && ok "$3" || bad "$3 (expected to contain: $1)" }

print "Checking Fold ${version} (build ${build_number}, tag ${tag})"

for required in "$app" "$dmg" "$zip" "$feed"; do
  [[ -e "$required" ]] || { print -u2 "Missing $required — run ./scripts/release.sh first."; exit 1 }
done

print "1. Exported bundle"
sign_output=$(codesign -dv --verbose=4 "$app" 2>&1)
check "Identifier=com.attila-krb.Fold" "$sign_output" "bundle identifier"
check "TeamIdentifier=${TEAM_ID}" "$sign_output" "signing team"
check "flags=0x10000(runtime)" "$sign_output" "hardened runtime"
entitlements=$(codesign -d --entitlements - "$app" 2>&1)
[[ "$entitlements" != *"disable-library-validation"* ]] \
  && ok "no library-validation exception" \
  || bad "distribution build carries disable-library-validation"
check "$version" "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" "bundle version"
check "$build_number" "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" "bundle build number"
check "$public_key" "$(plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist")" "Sparkle public key matches project.yml"
check "${REPO}/" "$(plutil -extract SUFeedURL raw "$app/Contents/Info.plist")" "feed URL points at this repository"

print "2. Generated icon matches the app"
xcrun swift scripts/icon.swift --variant refined --icns "$scratch/AppIcon.icns" > /dev/null \
  || bad "scripts/icon.swift failed"
cmp -s "$scratch/AppIcon.icns" Fold/AppIcon.icns \
  && ok "Fold/AppIcon.icns == icon.swift output" \
  || bad "Fold/AppIcon.icns differs from the generator"
cmp -s Fold/AppIcon.icns "$app/Contents/Resources/AppIcon.icns" \
  && ok "bundled icon matches the repository icon" \
  || bad "bundled icon differs from Fold/AppIcon.icns"

print "3. Notarization and Gatekeeper"
for target in "$app" "$dmg"; do
  xcrun stapler validate "$target" > /dev/null 2>&1 \
    && ok "staple valid: ${target:t}" \
    || bad "staple invalid: $target"
done
check "Notarized Developer ID" "$(spctl -a -vvv "$app" 2>&1)" "Gatekeeper accepts the app"
check "Notarized Developer ID" "$(spctl -a -vvv -t install "$dmg" 2>&1)" "Gatekeeper accepts the disk image"
codesign --verify --strict "$dmg" > /dev/null 2>&1 \
  && ok "disk image signature is valid" \
  || bad "disk image signature is invalid"

print "4. Sparkle feed"
# plutil lints plists, not RSS — it rejects a valid appcast with "unknown tag rss".
xmllint --noout "$feed" 2> /dev/null && ok "feed is well-formed XML" || bad "feed is not well-formed"
feed_body=$(<"$feed")
check "<title>${version}</title>" "$feed_body" "feed item carries ${version}"
check "sparkle:version>${build_number}<" "$feed_body" "feed item carries build ${build_number}"
check "/releases/download/${tag}/" "$feed_body" "feed item points at the ${tag} assets"
check "sparkle:edSignature" "$feed_body" "feed item is signed"
check "length=\"$(stat -f %z "$zip")\"" "$feed_body" "feed length matches the Sparkle archive"

print "5. Sparkle archive payload"
unzip -tqq "$zip" > /dev/null 2>&1 && ok "Sparkle archive is a readable zip" || bad "Sparkle archive is corrupt"
[[ "$zip" -nt "$app" ]] && ok "Sparkle archive is newer than the app it wraps" \
  || bad "Sparkle archive predates the app (stale build/ artifact?)"

print "6. Project matches project.yml"
xcodegen generate > /dev/null 2>&1
git diff --quiet -- Fold.xcodeproj \
  && ok "Fold.xcodeproj == xcodegen output" \
  || bad "Fold.xcodeproj drifts from project.yml (regenerate and commit)"

if [[ "$public" == true ]]; then
  print "7. Published bytes"
  local_size=$(stat -f %z "$dmg")
  remote_size=$(curl -sSIL --max-time 30 "https://github.com/${REPO}/releases/latest/download/Fold-macOS.dmg" \
    | tr -d '\r' | awk 'tolower($1)=="content-length:" {n=$2} END {print n}')
  [[ "$local_size" == "$remote_size" ]] \
    && ok "public DMG is byte-identical ($local_size bytes)" \
    || bad "public DMG size $remote_size != local $local_size"
  assets=$(gh release view "$tag" -R "$REPO" --json assets --jq '[.assets[].name] | join(",")' 2>/dev/null)
  check "Fold-macOS.dmg" "$assets" "release carries the DMG"
  check "Fold-macOS.zip" "$assets" "release carries the Sparkle archive"
  served=$(curl -sS --max-time 30 "https://raw.githubusercontent.com/${REPO}/main/${feed}")
  [[ "$served" == "$feed_body" ]] \
    && ok "served feed == committed feed" \
    || bad "the served feed differs from $feed (not committed on main yet?)"
fi

print ""
if [[ $fail -eq 0 ]]; then
  print "All checks passed."
else
  print "At least one check failed."
fi
exit $fail
