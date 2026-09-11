# Fold

[![Fold demo](docs/demo.gif)](docs/demo.gif)

[Download for Mac](https://github.com/ATTILA-KRB/Fold/releases/latest/download/Fold-macOS.dmg)

Your desktop bends and blurs as you close your MacBook lid. Fold runs in the menu bar and is free and open source.

Fold is a fork of [BendMac](https://github.com/IuCC123/BendMac) by IuCC, rebranded and maintained by [ATTILA-KRB](https://github.com/ATTILA-KRB) under the same MIT license. The effect, the sensor access and the capture pipeline come from that project; this fork carries its own application identity, update feed and release pipeline.

Inspired by [Bendy](https://trybendy.app/) and the iPhone Duo folding animation. No affiliation with Bendy or Apple, and none with BendMac or its author.

## Install

Requires **macOS 14+** and an **Apple silicon MacBook with a lid-angle sensor**. Tested hardware so far: M5 MacBook Air. If you try another model, please [let us know](https://github.com/ATTILA-KRB/Fold/issues).

1. Open the DMG and drag Fold into Applications.
2. Open Fold and turn on **General → Enable Fold**.
3. Grant access in **System Settings → Privacy & Security → Screen & System Audio Recording**.

Release downloads are Developer ID signed and notarized by Apple. Builds you make yourself with `scripts/build.sh` are only ad-hoc signed, so macOS may ask you to allow the app in Privacy & Security the first time you open it.

## Using it

Adjust the style, blur, perspective, and shadow in Appearance. The preview works without Screen Recording permission. Lid Behavior lets you change the angle at which the effect clears or control it manually.

Press **Escape** to pause the effect. Close the settings window to leave Fold running, or quit from the menu bar. Only the built-in display is affected.

Turn on **General → Open at login** to start Fold with your Mac. If the effect was on when you quit, it comes back on by itself with the same Follow lid setting and manual angle. Temporary capture failures are retried; missing sensor or display readiness can recover when the device becomes available.

Use **Check for updates** to install future versions in the app.

Screen frames stay in memory. Nothing is recorded to disk or uploaded, and audio isn't captured. Update checks contact GitHub to look for new releases.

## Build from source

XcodeGen is the source of truth for the project; `Fold.xcodeproj` is checked in for convenience.

```sh
brew install xcodegen
xcodegen generate             # only needed after changing project.yml
./scripts/build.sh --signed   # local testing
./scripts/build.sh            # ad-hoc, no certificate needed
make verify                   # build, then the app, shader and window checks
```

`make verify` runs `scripts/verify.sh` (animation, lifecycle, saved settings, rendered frames) and `scripts/verify-capture.sh` (capture exclusion, and that pausing leaves no overlay panel above the menu bar). Neither is part of CI: the first needs a signed build, the second a logged-in desktop with Screen Recording permission.

Test the live effect with `--signed`. Screen Recording permission is stored per code identity: an ad-hoc signature has no team, so macOS keys the grant on the binary's own hash, every rebuild changes it, and the app asks for permission again even though System Settings shows the toggle as on. A Developer ID signature pins the grant to the team and to `com.attila-krb.Fold`, so it survives rebuilds. Keep the ad-hoc build for CI and for building without a certificate.

The app is written to `build/Build/Products/Release/Fold.app`. Run `./scripts/dmg.sh` to package a DMG.

`./scripts/verify.sh` checks lifecycle recovery, saved settings, idle animation timers, motion math, signature, sensor, and Metal rendering. It needs a Mac; FFmpeg is optional for exporting the preview video.

You can also open `Fold.xcodeproj` in Xcode and run the Fold scheme. Xcode downloads Sparkle; install the Metal compiler component if prompted.

See the [changelog](CHANGELOG.md) for release details.

## Contributing

[Issues](https://github.com/ATTILA-KRB/Fold/issues) and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for setup and [release instructions](docs/releases.md) for packaging and update signing.

The app uses SwiftUI, AppKit, ScreenCaptureKit, and Metal. The lid sensor's HID report is undocumented, so compatibility can vary. Website source is in `website/dist`.

[MIT license](LICENSE). Reference videos and Bendy's assets aren't included.
