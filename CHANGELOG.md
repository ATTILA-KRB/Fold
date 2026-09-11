# Changelog

## 1.0.0 - Unreleased

First release under the Fold identity. Fold is a rebranded fork of BendMac 0.4.8; the effect, sensor access and capture pipeline are unchanged from that baseline.

### Changed

- Application identity moved to `com.attila-krb.Fold`, so Fold installs alongside BendMac instead of upgrading it.
- Update feed moved to this repository's `docs/appcast.xml`, authenticated with a Fold-specific Sparkle EdDSA key.
- Bundle version reset to `1.0.0` (build 1).
- Support links now point at this repository; the upstream author's donation link and website were removed.
- Project, scripts and tests renamed from BendMac to Fold; XcodeGen remains the source of truth.

History for the feature baseline is in the [upstream changelog](https://github.com/IuCC123/BendMac/blob/main/CHANGELOG.md).
