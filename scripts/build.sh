#!/bin/zsh
# Builds the Release app into build/Build/Products/Release/Fold.app.
#
#   ./scripts/build.sh            ad-hoc signature: no certificate needed, what
#                                 contributors and CI use
#   ./scripts/build.sh --signed   Developer ID signature: use this for local
#                                 testing
#
# Why it matters: Screen Recording permission is granted per code identity. An
# ad-hoc signature has no team, so macOS keys the grant on the binary's hash and
# every rebuild looks like a different app — it re-prompts even though System
# Settings shows the toggle as on. With Developer ID the designated requirement
# names the team and the bundle id instead, and the grant survives rebuilds.
set -euo pipefail
cd "${0:A:h}/.."

export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM_ID="${DEVELOPER_TEAM_ID:-5FMH389VS7}"

signed=false
for arg in "$@"; do
  case "$arg" in
    --signed) signed=true ;;
    -h|--help)
      print -r -- "usage: build.sh [--signed]"
      print -r -- "  (no flag)  ad-hoc signature — CI and contributors without a certificate"
      print -r -- "  --signed   Developer ID signature — local testing, keeps the Screen"
      print -r -- "             Recording grant across rebuilds"
      exit 0 ;;
    # Reject typos: silently falling back to ad-hoc reintroduces the permission
    # loop the caller was trying to avoid.
    *) print -u2 "Unknown argument: ${arg} (expected --signed)"; exit 2 ;;
  esac
done

identity="-"
sign_args=()

if [[ "$signed" == true ]]; then
  identity="${DEVELOPER_ID_HASH:-561D8D381F89B361D335724A008AAAC5AE9E688B}"
  # Capture then match: `security … | grep -q` closes the pipe early and
  # `set -o pipefail` turns the SIGPIPE into a failure.
  identities=$(security find-identity -v -p codesigning)
  [[ "$identities" == *"$identity"* ]] || {
    print -u2 "No usable Developer ID identity ${identity} in the keychain."
    print -u2 "Run 'security find-identity -v -p codesigning' and set DEVELOPER_ID_HASH."
    exit 1
  }
  sign_args=(CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM_ID")
  print "==> Signing with Developer ID ${identity} (team ${TEAM_ID})"
else
  print "==> Ad-hoc signature: macOS will re-request Screen Recording on every rebuild"
fi

xcodegen generate
xcodebuild -project Fold.xcodeproj -scheme Fold -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="$identity" "${sign_args[@]}" build
