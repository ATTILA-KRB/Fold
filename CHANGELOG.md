# Changelog

## 1.0.0 - Unreleased

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
