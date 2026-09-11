#!/bin/zsh
# Local release for Fold: archive, Developer ID signing, notarization, DMG,
# Sparkle appcast and (with --publish) the GitHub release.
#
# Default is a dry run: everything is produced under build/release/ and nothing
# outside this repository is touched. Pass --publish to push the GitHub release
# and update docs/appcast.xml.
#
# Flags:
#   --skip-build   reuse the already notarized and stapled app
#   --skip-dmg     reuse the already notarized and stapled DMG
#                  Both exist to retry a late step (typically the appcast or the
#                  GitHub release) without paying for another notarization round.
#
# Requires: Xcode, xcodegen, the Developer ID identity in the login keychain,
# a notarytool keychain profile, and the Sparkle signing key for the account in
# SPARKLE_ACCOUNT (its private half never leaves the keychain).
set -euo pipefail
cd "${0:A:h}/.."

export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Two Developer ID certificates share the same display name in this keychain, so
# `codesign --sign "<name>"` is ambiguous and refuses to run. Pin the hash.
IDENTITY_HASH="${DEVELOPER_ID_HASH:-561D8D381F89B361D335724A008AAAC5AE9E688B}"
TEAM_ID="${DEVELOPER_TEAM_ID:-5FMH389VS7}"
NOTARY_PROFILE="${NOTARY_PROFILE:-popcorn-notary}"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-com.attila-krb.Fold}"
REPO="${REPO:-ATTILA-KRB/Fold}"

publish=false
skip_build=false
skip_dmg=false
for arg in "$@"; do
  case "$arg" in
    --publish) publish=true ;;
    --skip-build) skip_build=true ;;
    --skip-dmg) skip_dmg=true ;;
    *) print -u2 "Unknown argument: $arg"; exit 2 ;;
  esac
done

version=$(awk '/MARKETING_VERSION:/ {gsub(/'"'"'/,"",$2); print $2; exit}' project.yml)
build_number=$(awk '/CURRENT_PROJECT_VERSION:/ {gsub(/'"'"'/,"",$2); print $2; exit}' project.yml)
tag="v${version}"
out="build/release"
app="$out/Fold.app"
dmg="$out/Fold-macOS.dmg"
zip="" # set once the Sparkle archive is built in its own directory

print "==> Fold ${version} (build ${build_number}), tag ${tag}"
[[ -n "$version" && -n "$build_number" ]] || { print -u2 "Could not read the version from project.yml"; exit 1; }

print "==> Preflight"
# Capture, then match in the shell: piping a command into `grep -q` lets grep
# close the pipe early, the writer dies on SIGPIPE and `set -o pipefail` turns
# a passing check into a failure.
identities=$(security find-identity -v -p codesigning)
[[ "$identities" == *"${IDENTITY_HASH}"* ]] || {
  print -u2 "The pinned Developer ID identity ${IDENTITY_HASH} is not a valid codesigning identity."
  print -u2 "Run 'security find-identity -v -p codesigning' and set DEVELOPER_ID_HASH to the right one."
  exit 1
}
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null || {
  print -u2 "notarytool profile '${NOTARY_PROFILE}' is not usable."
  exit 1
}
command -v xcodegen > /dev/null || { print -u2 "xcodegen is required (brew install xcodegen)."; exit 1; }

sparkle_bin=$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null | head -1)
[[ -n "$sparkle_bin" ]] || { print -u2 "Sparkle tools not found; build the app once so SPM resolves Sparkle."; exit 1; }

if [[ "$skip_build" == true ]]; then
  [[ -d "$app" ]] || { print -u2 "--skip-build but there is no app at $app"; exit 1; }
  print "==> Reusing the notarized app at $app"
else
  rm -rf "$out" build/Fold.xcarchive
  mkdir -p "$out"

  print "==> Generating the Xcode project"
  xcodegen generate > /dev/null

  print "==> Archiving with Developer ID and the distribution entitlements"
  xcodebuild -project Fold.xcodeproj -scheme Fold -configuration Release \
    -archivePath build/Fold.xcarchive -destination 'generic/platform=macOS' \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY_HASH" \
    CODE_SIGN_ENTITLEMENTS=packaging/Fold.entitlements DEVELOPMENT_TEAM="$TEAM_ID" \
    archive > "$out/archive.log" 2>&1 || { print -u2 "Archive failed; see $out/archive.log"; exit 1; }

  print "==> Exporting"
  xcodebuild -exportArchive -archivePath build/Fold.xcarchive -exportPath "$out" \
    -exportOptionsPlist packaging/ExportOptions.plist > "$out/export.log" 2>&1 \
    || { print -u2 "Export failed; see $out/export.log"; exit 1; }
  [[ -d "$app" ]] || { print -u2 "No app at $app"; exit 1; }
fi

print "==> Verifying the signature"
codesign --verify --strict --verbose=2 "$app" 2>&1 | tail -2
sign_output=$(codesign -dv --verbose=4 "$app" 2>&1)
team=$(print -r -- "$sign_output" | awk -F= '/TeamIdentifier/ {print $2}')
[[ "$team" == "$TEAM_ID" ]] || { print -u2 "Wrong team identifier: ${team}"; exit 1; }
[[ "$sign_output" == *"flags=0x10000(runtime)"* ]] || {
  print -u2 "Hardened runtime is not enabled on the exported app."; exit 1
}
entitlements=$(codesign -d --entitlements - "$app" 2>&1)
[[ "$entitlements" != *"disable-library-validation"* ]] || {
  print -u2 "The distribution build must not carry disable-library-validation."; exit 1
}
print "    team=${team}, hardened runtime on, no library-validation exception"

if [[ "$skip_build" == true ]]; then
  xcrun stapler validate "$app" > /dev/null || {
    print -u2 "The reused app is not stapled; drop --skip-build."; exit 1
  }
else
  print "==> Notarizing the app bundle"
  # Keep this archive out of $out: generate_appcast scans that directory and
  # refuses two archives carrying the same bundle version.
  mkdir -p build/notary
  ditto -c -k --sequesterRsrc --keepParent "$app" build/notary/Fold-app.zip
  xcrun notarytool submit build/notary/Fold-app.zip --keychain-profile "$NOTARY_PROFILE" --wait \
    | tee "$out/notary-app.log" | grep -E "id:|status:"
  [[ "$(<"$out/notary-app.log")" == *"status: Accepted"* ]] || {
    print -u2 "Notarization of the app was not accepted; see $out/notary-app.log"; exit 1
  }
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
fi

if [[ "$skip_dmg" == true ]]; then
  [[ -f "$dmg" ]] || { print -u2 "--skip-dmg but there is no DMG at $dmg"; exit 1; }
  print "==> Reusing the notarized DMG at $dmg"
  xcrun stapler validate "$dmg" > /dev/null || {
    print -u2 "The reused DMG is not stapled; drop --skip-dmg."; exit 1
  }
else
  print "==> Packaging the DMG"
  APP_PATH="$PWD/$app" DMG_OUTPUT="$PWD/$dmg" ./scripts/dmg.sh
  [[ -f "$dmg" ]] || { print -u2 "No DMG at $dmg"; exit 1; }

  # Sign the image itself as well as notarizing it. An unsigned image still
  # carries the app's notarization, but `spctl -a -t install` rejects it and the
  # download no longer looks uniformly trustworthy.
  print "==> Signing the DMG"
  codesign --force --sign "$IDENTITY_HASH" --timestamp "$dmg"
  codesign --verify --verbose=2 "$dmg"

  print "==> Notarizing the DMG"
  xcrun notarytool submit "$dmg" --keychain-profile "$NOTARY_PROFILE" --wait \
    | tee "$out/notary-dmg.log" | grep -E "id:|status:"
  [[ "$(<"$out/notary-dmg.log")" == *"status: Accepted"* ]] || {
    print -u2 "Notarization of the DMG was not accepted; see $out/notary-dmg.log"; exit 1
  }
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
fi

print "==> Building the Sparkle archive and appcast"
# generate_appcast refuses two archives holding the same bundle version, and it
# scans the whole directory it is pointed at. Give it a directory that contains
# the Sparkle ZIP and nothing else: the DMG must never live here.
appcast_dir="build/appcast"
rm -rf "$appcast_dir"
mkdir -p "$appcast_dir"
zip="$appcast_dir/Fold-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
cp docs/appcast.xml "$appcast_dir/appcast.xml"
"$sparkle_bin/generate_appcast" --account "$SPARKLE_ACCOUNT" --maximum-deltas 0 \
  --download-url-prefix "https://github.com/${REPO}/releases/download/${tag}/" "$appcast_dir" \
  || { print -u2 "generate_appcast failed. Retry with --skip-build --skip-dmg."; exit 1; }
cp "$appcast_dir/appcast.xml" "$out/appcast.xml"
[[ -f "$out/appcast.xml" ]] || { print -u2 "generate_appcast produced no feed; is the Sparkle key present?"; exit 1 }
[[ "$(<"$out/appcast.xml")" == *"$tag"* ]] || { print -u2 "The generated feed has no ${tag} item."; exit 1 }
print "    $(du -h "$dmg" | cut -f1) DMG, $(du -h "$zip" | cut -f1) ZIP"

if [[ "$publish" != true ]]; then
  print "==> Verifying the artifacts"
  ./scripts/verify-release.sh || exit 1
  print "\nDry run complete. Artifacts in ${out}:"
  ls -lh "$dmg" "$zip" "$out/appcast.xml"
  print "\nNothing was published. Re-run with --publish to create the GitHub release and update docs/appcast.xml."
  exit 0
fi

print "==> Publishing the GitHub release ${tag}"
notes="$out/notes.md"
if [[ -f "$out/notes.md.custom" ]]; then
  notes="$out/notes.md.custom"
else
  print "Fold ${version}.\n\nSee [CHANGELOG.md](https://github.com/${REPO}/blob/main/CHANGELOG.md)." > "$notes"
fi
gh release create "$tag" "$dmg" "$zip" -R "$REPO" --title "$tag" --notes-file "$notes"

print "==> Updating docs/appcast.xml"
cp "$out/appcast.xml" docs/appcast.xml
git add docs/appcast.xml
git commit -q -m "Publie le flux de mise a jour ${version}" || print "    (nothing to commit)"
git push origin HEAD

print "==> Verifying the published release"
./scripts/verify-release.sh --public || exit 1

print "\nPublished: https://github.com/${REPO}/releases/tag/${tag}"
print "Re-run ./scripts/verify-release.sh --public at any time to re-check the delivery."
