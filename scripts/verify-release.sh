#!/bin/zsh
# Verify what a release ships. Run it after `release.sh` (a dry run runs it
# automatically) and before announcing anything.
#
#   ./scripts/verify-release.sh            local artifacts in build/release
#   ./scripts/verify-release.sh --public   also the published delivery
#
# The local pass is self-consistent: every value it checks comes from project.yml
# or from the artifacts themselves. The --public pass is self-consistent too, so
# it stays meaningful at any time and does not depend on what build/release
# currently holds: it re-reads the committed feed and makes GitHub prove that the
# asset it serves is the byte length that feed declares, which is exactly what
# Sparkle checks before installing.
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
feed="$out/appcast.xml"
zip="build/appcast/Fold-macOS.zip"
committed_feed=docs/appcast.xml

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
# Match the flag word: an ad-hoc signature encodes the same hardening as
# 0x10002(adhoc,runtime), where the literal "flags=0x10000(runtime)" never appears.
codesign_line=$(print -r -- "$sign_output" | awk '/^CodeDirectory/ {print; exit}')
check "runtime" "$codesign_line" "hardened runtime"
entitlements=$(codesign -d --entitlements - "$app" 2>&1)
[[ "$entitlements" != *"disable-library-validation"* ]] \
  && ok "no library-validation exception" \
  || bad "distribution build carries disable-library-validation"
check "$version" "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" "bundle version"
check "$build_number" "$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")" "bundle build number"
check "$public_key" "$(plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist")" "Sparkle public key matches project.yml"
check "${REPO}/" "$(plutil -extract SUFeedURL raw "$app/Contents/Info.plist")" "feed URL points at this repository"

print "2. Generated icon matches the app"
scratch=$(mktemp -d "${TMPDIR:-/tmp}/hermes-verify-icon.XXXXXX")
xcrun swift scripts/icon.swift --variant refined --icns "$scratch/AppIcon.icns" > /dev/null \
  || bad "scripts/icon.swift failed"
cmp -s "$scratch/AppIcon.icns" Fold/AppIcon.icns \
  && ok "Fold/AppIcon.icns == icon.swift output" \
  || bad "Fold/AppIcon.icns differs from the generator (regenerate and commit it)"
rm -rf "$scratch"
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

print "4. Generated Sparkle feed"
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
  print "7. Published delivery (read from the network, independent of this build)"
  served=$(curl -sS --max-time 30 "https://raw.githubusercontent.com/${REPO}/main/${committed_feed}")
  committed=$(<"$committed_feed")
  [[ -n "$served" && "$served" == "$committed" ]] \
    && ok "served feed == committed ${committed_feed}" \
    || bad "the served feed differs from ${committed_feed} (not committed on main, or not pushed)"
  assets=$(gh release view "$tag" -R "$REPO" --json assets --jq '[.assets[].name] | join(",")' 2>/dev/null)
  check "Fold-macOS.dmg" "$assets" "release carries the DMG"
  check "Fold-macOS.zip" "$assets" "release carries the Sparkle archive"
  # What Sparkle does before installing: download the ZIP, check its length
  # against the feed it just read, then verify the EdDSA signature.
  declared=$(print -r -- "$served" | grep -o 'length="[0-9]*"' | head -1 | tr -dc '0-9')
  served_zip=$(curl -sSIL --max-time 30 "https://github.com/${REPO}/releases/latest/download/Fold-macOS.zip" \
    | tr -d '\r' | awk 'tolower($1)=="content-length:" {n=$2} END {print n}')
  [[ -n "$declared" && "$declared" == "$served_zip" ]] \
    && ok "served archive is ${declared} bytes, exactly what the feed declares" \
    || bad "feed declares ${declared} bytes but GitHub serves ${served_zip}"
fi

print ""
if [[ $fail -eq 0 ]]; then
  print "All checks passed."
else
  print "At least one check failed."
fi
exit $fail
