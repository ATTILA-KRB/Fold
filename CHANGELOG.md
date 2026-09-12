# Changelog

## 1.0.1 - 2026-09-11

### Fixed

- Pausing the effect could leave a full-screen panel ordered above the menu bar, showing a frozen desktop and hiding the menu bar item: the app looked crashed and nothing blurred. Every overlay a session creates is now hidden when the effect stops, not only the most recent one.
- The folded sheet no longer leaves flat-black wedges on either side. The area outside the sheet continues the desktop, blurred and slightly darkened, instead of being multiplied to zero. At full fold the black area was up to 23.5% of the screen.
- The sheet's silhouette fades over a wider band, so the fold reads as a soft transition rather than a hard diagonal edge.

### Changed

- Blur now holds the desktop sharp for most of the fold and gathers against the top edge (`pow(height, 4.5)`, radius 56). The first attempt at a smoother ramp (`pow(height, 2.1)`) blurred from the first degrees of the fold and read as arriving too early.

### Developer checks

- `./scripts/build.sh --signed` produces a Developer ID build. Screen Recording permission is stored per code identity, and an ad-hoc signature's is keyed on the binary's hash, so every rebuild dropped the grant and re-prompted while System Settings showed it as on.
- The app icon is generated reproducibly: the drawing goes through an explicit device-RGB bitmap instead of `NSImage.cgImage(forProposedRect:)`, which inherited the display's colour space and produced different bytes from one run to the next. The icon is unchanged to the eye (mean difference 0.39/255, edges only).
- Argument typos in `scripts/build.sh` now fail instead of silently falling back to an ad-hoc build.
- The hardened-runtime check in the release scripts matches the flag word: ad-hoc encodes it as `0x10002(adhoc,runtime)`, where the literal `flags=0x10000(runtime)` does not appear.

## 1.0.0 - 2026-09-11

First release under the Fold identity. Fold is a rebranded fork of BendMac 0.4.8; the effect, sensor access and capture pipeline are unchanged from that baseline.

### Changed

- Application identity moved to `com.attila-krb.Fold`, so Fold installs alongside BendMac instead of upgrading it.
- Update feed moved to this repository's `docs/appcast.xml`, authenticated with a Fold-specific Sparkle EdDSA key.
- Bundle version reset to `1.0.0` (build 1).
- Releases are Developer ID signed and notarized, including the disk image. Downloads no longer need a manual Privacy & Security approval.
- Support links now point at this repository; the upstream author's donation link and website were removed.
- Project, scripts and tests renamed from BendMac to Fold; XcodeGen remains the source of truth, and CI now fails when `Fold.xcodeproj` drifts from `project.yml`.

### Added

- `scripts/release.sh` — local release chain: archive, Developer ID signing, notarization of the app and of the DMG, DMG packaging, Sparkle appcast, and the GitHub release. Dry run by default; `--publish` to ship.
- `packaging/Fold.entitlements` and `packaging/ExportOptions.plist` for the distribution build, kept separate from the ad-hoc development entitlements.

History for the feature baseline is in the [upstream changelog](https://github.com/IuCC123/BendMac/blob/main/CHANGELOG.md).
