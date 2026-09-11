# Publishing a release

Fold ships outside the App Store: a Developer ID signed and notarized DMG for downloads, and a Sparkle 2 feed for in-app updates.

- App reads `docs/appcast.xml` from this repository.
- Sparkle downloads the signed ZIP from GitHub Releases.
- `scripts/release.sh` does the whole chain locally on a Mac that holds the Developer ID identity and Apple notarization access. CI is not required and must not be the primary path: the signing identity and the Sparkle key live on the maintainer's machine.

## Prerequisites

| What | Check |
|---|---|
| Xcode, not CommandLineTools | `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version` |
| Developer ID identity | `security find-identity -v -p codesigning` lists `Developer ID Application: … (5FMH389VS7)` |
| Notarization credentials | `xcrun notarytool history --keychain-profile popcorn-notary` returns a history |
| XcodeGen | `xcodegen --version` |
| Sparkle tools | resolved by SPM on the first build, found under `DerivedData/**/artifacts/sparkle/Sparkle/bin` |

The notary profile is per Apple ID, not per app, so it is shared with the other apps of this team. `popcorn-notary` is the profile name by default; override with `NOTARY_PROFILE=<name>`.

The script pins the Developer ID certificate by SHA-1 (`DEVELOPER_ID_HASH`, default `561D8D381F89B361D335724A008AAAC5AE9E688B`) because two certificates in this keychain share the display name and `codesign --sign "<name>"` fails as ambiguous. Both app and DMG are signed with a secure timestamp, notarized, and stapled; `spctl -a -vvv -t install` must accept the shipped DMG.

## Signing model

Two entitlement files, on purpose:

- `Fold/Fold.entitlements` — used by XcodeGen for ordinary builds. It carries `com.apple.security.cs.disable-library-validation`, which an **ad-hoc** signature needs because it has no team ID to match the embedded Sparkle framework against. `scripts/build.sh` and CI produce this build.
- `packaging/Fold.entitlements` — deliberately empty, used only by `scripts/release.sh`. With Developer ID signing, Xcode re-signs the embedded framework with the same team, so the exception is neither needed nor wanted in a shipped app. `scripts/release.sh` fails the release if the exception is present in the exported app.

## Update signing key

The private update-signing key lives in the macOS login Keychain under the Sparkle account `com.attila-krb.Fold`. The public half is in `project.yml`. Back the private half up outside this repository: losing it prevents existing installations from trusting future updates.

```sh
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts/sparkle/Sparkle/bin' -type d | head -1)"
"$SPARKLE_BIN/generate_keys" --account com.attila-krb.Fold                      # create / print the public key
"$SPARKLE_BIN/generate_keys" --account com.attila-krb.Fold -x /path/outside/repo # back the private key up
```

Always pass the same `--account` to `generate_appcast`: a different account signs with a different key and every client rejects the update.

Sparkle signatures authenticate the update payload. They do not replace Developer ID signing or notarization for the first download.

## Procedure

1. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. The build number must increase on every release, including a re-release of the same version.
2. Update `CHANGELOG.md`.
3. Dry run:

   ```sh
   ./scripts/release.sh
   ```

   Archive, export with Developer ID, notarize the app, staple it, build the DMG, notarize and staple the DMG, then generate the appcast. Everything lands in `build/release/`; nothing is published. Expect 5–15 minutes for the two notarization submissions.
4. Verify the artifacts: `./scripts/verify-release.sh` (the release script already runs it at the end of a dry run). It checks the exported signature, the bundled entitlements, both staples, Gatekeeper's verdict on app and image, the generated feed against `project.yml`, the Sparkle archive, and that `Fold.xcodeproj` still matches `project.yml`.
5. Publish:

   ```sh
   ./scripts/release.sh --publish
   ```

   Creates the GitHub release `vX.Y.Z` with the DMG and the ZIP, copies the feed to `docs/appcast.xml`, commits and pushes it, then runs `./scripts/verify-release.sh --public` to compare the published bytes with the local ones. Publish the release before the feed — a feed pointing at a missing asset serves every client a 404.
6. If a step fails after publication, inspect the report; the script prints the concrete mismatch (size, missing asset, feed not on `main`) rather than a generic error.

## DMG naming

`scripts/dmg.sh` always writes `Fold-macOS.dmg`, so the website and the README can use GitHub's `/releases/latest/download/Fold-macOS.dmg` redirect and follow the newest release without any edit. Keep the filename stable across releases, and keep the signed ZIP (not the DMG) as the Sparkle payload.

## Notes

- Never commit private keys or notary credentials. Contributors compile with the public key only.
- `docs/appcast.xml` is committed empty until the first release, so a fresh install finds nothing to verify rather than an unverifiable item. Upstream BendMac feed entries cannot be reused: they are signed with a key this app does not trust.
- `/opt/homebrew/bin` is not on the PATH of every agent shell; `scripts/release.sh` prepends it.
