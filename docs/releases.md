# Publishing an update

Fold uses Sparkle 2 for in-app updates. The app reads `docs/appcast.xml` from this repository and downloads signed archives from GitHub Releases.

## Signing key

The private update-signing key is stored in the macOS login Keychain under the Sparkle account `com.attila-krb.Fold`. The public key is in `project.yml`. Keep a secure backup of the private key outside this repository. Losing it would prevent existing installations from trusting future updates.

To create the key pair, or to export a backup of an existing one:

```sh
SPARKLE_BIN="$(find ~/Library/Developer/Xcode/DerivedData -path '*sparkle/Sparkle/bin' -type d | head -1)"
"$SPARKLE_BIN/generate_keys" --account com.attila-krb.Fold
"$SPARKLE_BIN/generate_keys" --account com.attila-krb.Fold -x /path/to/private/key/outside/repo
```

Use the same `--account` value for `generate_appcast`, or Sparkle will sign with the wrong key and every client will reject the update.

The current ad-hoc build uses an app-scoped library-validation exception because it has no Apple Team ID. Remove that exception when switching the app and embedded framework to Developer ID signing.

Sparkle signatures authenticate updates. They do not replace Apple Developer ID signing or notarization for the first download.

## Release steps

1. Increase `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`. The build number must increase with every release.
2. Run `scripts/build.sh`.
3. Download the matching Sparkle distribution to get its `generate_appcast` tool.
4. Create a release folder containing only the new app archive:

   ```sh
   mkdir -p build/update
   ditto -c -k --sequesterRsrc --keepParent build/Build/Products/Release/Fold.app build/update/Fold-macOS.zip
   ```

5. Copy the existing `docs/appcast.xml` into that folder. Generate the feed with your release tag in the download URL:

   ```sh
   /path/to/Sparkle/bin/generate_appcast --account com.attila-krb.Fold --maximum-deltas 0 --download-url-prefix https://github.com/ATTILA-KRB/Fold/releases/download/v1.0.0/ build/update
   ```

6. Upload the exact signed ZIP to that GitHub release. Do not rebuild or modify it after signing.
7. Copy the generated `appcast.xml` back to `docs/appcast.xml` and publish it only after the release asset is available.

Never commit private keys. Contributors can compile the app with the public key; only the release maintainer needs access to the private key.

`docs/appcast.xml` is committed empty until the first release, so a fresh install finds no update instead of an entry it cannot verify. The upstream project's feed entries cannot be reused: they are signed with a key this app does not trust.

## Drag-to-install download

Run `./scripts/dmg.sh` after building to create `build/Fold-macOS.dmg`. It generates the Retina background and Finder layout without opening Finder. Upload the DMG alongside the ZIP and keep the filename `Fold-macOS.dmg` on every release. The website uses GitHub’s `/releases/latest/download/Fold-macOS.dmg` redirect, so the buttons follow the latest stable release without a website update. Publish each release only after both assets are uploaded. Keep the signed ZIP for Sparkle updates.
