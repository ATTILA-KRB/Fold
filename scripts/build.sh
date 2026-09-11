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
# Settings shows the toggle as on. With Developer ID the grant belongs to
# 5FMH389VS7 and com.attila-krb.Fold, and it survives rebuilds.
set -euo pipefail
cd "${0:A:h}/.."

export PATH="/opt/homebrew/bin:$PATH"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

TEAM_ID="${DEVELOPER_TEAM_ID:-5FMH389VS7}"
identity="-"
sign_args=()

if [[ "${1:-}" == "--signed" ]]; then
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
  print "==> Ad-hoc signature: Screen Recording will be re-requested on every rebuild"
fi

xcodegen generate
xcodebuild -project Fold.xcodeproj -scheme Fold -configuration Release -derivedDataPath build \
  CODE_SIGN_IDENTITY="$identity" "${sign_args[@]}" build
