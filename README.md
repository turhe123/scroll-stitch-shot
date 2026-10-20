# ScrollStitchShot

Drag a region, let it auto-scroll, and get one tall stitched screenshot of a long page or document.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![GitHub release](https://img.shields.io/github/v/release/turhe123/scroll-stitch-shot)

## Why

macOS has no built-in scrolling screenshot, and the utilities that fill the gap are usually paid. ScrollStitchShot is a free, open-source, 100% native, backend-free alternative in the *Screen & OCR* category. It was inspired by ScrollSnap ($4.99 one-time) and covers the core job: capture a scrolling region and stitch it into one image, entirely on your Mac.

## Features

- **Menu bar app** (no Dock icon) with a global hotkey, default **⇧⌘8**, re-recordable in Settings.
- **Region selection**: full-screen overlay with a crosshair and size label. Press Return to confirm, Esc to cancel. Regions smaller than 100 × 100 pt are rejected with a hint.
- **Automatic mode**: captures a first frame, posts synthetic scroll-wheel events at the region center, captures after each step, and stops when two consecutive frames are identical (bottom reached), when you press Esc or click Stop, or at 40 frames.
- **Manual mode**: scroll by hand while the app grabs a frame every 300 ms (up to 300 frames).
- **Overlap-based stitching**: matches rows of downsampled grayscale pixels between frames to find the vertical offset, then appends only the new rows. If a match is poor, the result is flagged as "possibly misaligned".
- **Sticky header/footer trimming**: crop a fixed number of points from the top and bottom of every frame after the first so sticky bars appear only once.
- **Retina aware**: capture size and scroll offsets account for the display's backing scale factor.
- **Multi-display**: the region is captured from the display it was drawn on. ScreenCaptureKit excludes the app's own windows from the capture.
- **Output**: PNG saved to a folder you choose (falls back to the Desktop if it's missing), optionally copied to the clipboard, with an optional completion sound. Images taller than 16,000 px are split into multiple numbered files.
- **Floating HUD** showing frame count, a Stop button, and the result with a link to the file.
- **Settings**: hotkey recorder, save folder, scroll step (0 = 70% of region height), delay between steps (default 250 ms), header/footer trim, clipboard and sound toggles, launch at login.
- **Open Last Capture** from the menu; the menu shows "No recent captures yet" when empty.

## Screenshots

_Screenshots coming soon._

## Install

1. Download `ScrollStitchShot-macOS.zip` from the [latest release](https://github.com/turhe123/scroll-stitch-shot/releases/latest).
2. Unzip it and move `ScrollStitchShot.app` to `/Applications`.
3. Because the app is open source and not notarized, clear the quarantine flag:

   ```bash
   xattr -cr /Applications/ScrollStitchShot.app
   ```

4. Right-click the app → **Open** the first time.

## Build from source

Requires macOS 14+ and Xcode with command-line tools.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project ScrollStitchShot.xcodeproj -scheme ScrollStitchShot -configuration Release -derivedDataPath ./build build
```

The app is produced at `build/Build/Products/Release/ScrollStitchShot.app`.

## Permissions

| Permission | Why |
| --- | --- |
| **Screen Recording** | Required to capture the region you select (ScreenCaptureKit). Checked before every capture. |
| **Accessibility** | Required in automatic mode only, to post scroll-wheel events. Manual mode works without it. |

If a permission is missing, the app explains why and offers to open the matching System Settings pane; nothing is captured until it's granted. You may need to relaunch the app after enabling Screen Recording. The app does **not** request microphone, camera, or network access. Launch at login uses `SMAppService` and only applies if you turn it on.

## Built with AI

ScrollStitchShot was written by [Claude Code](https://claude.com/claude-code) inside an automated pipeline, from a plain-English spec. No code, binaries or assets from any commercial app were used; it is a clean-room reimplementation of a feature set, not a copy.

What that means in practice:

- The full source is in this repo under the MIT license. Read it before you run it.
- No network calls, no analytics, no third-party dependencies. Only Apple frameworks.
- Ad-hoc signed and not notarized, which is why Gatekeeper warns on first launch.
- It has had less human review than a hand-written app. Bug reports and pull requests are welcome.

## Support ❤️

If this saves you time, you can support the author: [Support Or (Leo) Davidai ❤️](https://ko-fi.com/leodavidai)

## License

MIT © Or Davidai Bachar
