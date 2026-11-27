# Notch

A SwiftUI/AppKit menu-bar app with detached music artwork, native Now Playing controls, themed track/volume sliders, battery status, and temporary AirPods connection indicators.

## Build

Open `Notch.xcodeproj`, select the **Notch** scheme and **My Mac**, then build and run. The project builds and embeds MediaRemoteAdapter from Objective-C source. The app and adapter target macOS 14.6. Select your own development team for signing; no certificates or private keys are included.

The shared project uses Xcode's `project.xcproj` format and was validated using Xcode 27.2. Older Xcode versions may not support this project format.

### Local toolchain on Apple silicon

Use **My Mac** for local runs and **Product → Archive** to archive the app. Debug, Release, and CI build for Apple silicon (arm64) only. If Xcode offers standard architectures, choose **Build** to keep arm64.

If selecting Xcode as the system developer directory makes `git` fail with an `arm64e` error from `libxcrun`, use the standalone Command Line Tools for Terminal and Homebrew. Check the selection with `xcode-select -p`. You can still build from the Xcode app or invoke its build tool directly:

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Notch.xcodeproj -scheme Notch -configuration Debug \
  -destination 'platform=macOS,arch=arm64' build
```

## Checks

Run `zsh scripts/test.sh` for the standalone regression checks. Keep Xcode's Main Thread Checker enabled when checking Accessibility menu placement. Console logging is not suppressed by the shared scheme.

## Placement and playback

Music artwork uses a left dot when app-menu space allows it. Right-side dots are hidden when space is blocked or cannot be verified; menu rectangles are checked even when the overlay masks the menu during Accessibility hit-testing. Numbers keeps the existing no-dot behavior. Click the physical notch to open the panel when dots are hidden.

Accessibility hit-testing that can reenter Notch's own views runs on the main thread. Remote app-menu reads remain on a background queue. Signing and Accessibility authorization persistence still depend on the signing identity; the code does not change certificate trust or reset permissions.

The visualizer is a generalized playback animation, not live audio analysis. No system audio capture, browser extension, or JavaScript through Apple Events is used.

## License

Notch is licensed under the MIT license in the repository-root `LICENSE`. The vendored MediaRemote adapter retains its separate BSD-3-Clause license.

## Third-party code

The MediaRemote adapter is from [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter). Its BSD-3-Clause license and copyright notices are preserved in `Notch/LICENSE` and the source files, and the license is bundled in the app. The adapter uses a private macOS interface that may change in future macOS versions.
