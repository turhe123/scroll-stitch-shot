# ScrollStitchShot — specification

**Tagline:** Drag a region, let it auto-scroll, and get one tall stitched screenshot of a long page or document.

**Category:** Screen & OCR

**Inspired by (paid):** ScrollSnap ($4.99 one-time)

**Frameworks:** SwiftUI, AppKit, ScreenCaptureKit, CoreGraphics, ApplicationServices, UniformTypeIdentifiers

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: ScrollSnap is a Mac App Store utility that captures scrolling screenshots of web pages and documents by stitching frames together, processed locally. A similar app, Longshot, sells for about 12.99 and several blogs note that macOS still has no built-in scrolling capture, which is why these small apps keep getting recommended in screenshot roundups and on Mac power user forums. Our clean-room version, ScrollStitchShot, covers the core job only.

Feature set: a menu bar app with one global hotkey. Press it, drag a rectangle over the scrollable area, and press Return. The app captures the first frame, posts synthetic scroll wheel events over the region, captures a frame after each step, and stops when two consecutive frames are identical (bottom reached), when the user presses Escape, or when a frame limit of 40 is hit. Frames are stitched vertically into one image, saved as PNG to a chosen folder, and optionally copied to the clipboard. A manual mode lets the user scroll by hand while the app grabs frames every 300 milliseconds and stitches them.

UI spec: MenuBarExtra with items Capture Scrolling Region, Open Last Capture, Settings, Quit. A full screen transparent overlay window handles region selection with a crosshair and size label. While running, a small floating pill shows frame count and a Stop button. Settings window fields: hotkey recorder, save folder picker, scroll step in points (default 70 percent of region height), delay between steps (default 250 ms), copy to clipboard toggle, play sound toggle, launch at login toggle. Empty state in the menu shows no recent captures yet.

Technical approach: use ScreenCaptureKit SCScreenshotManager captureImage with an SCContentFilter for the display and a sourceRect equal to the region, excluding the app's own overlay windows. Scrolling uses CGEvent scrollWheelEvent2 posted at the region center, which needs the Accessibility permission, checked with AXIsProcessTrusted and prompted with the options dictionary. Screen Recording permission is checked with CGPreflightScreenCaptureAccess and requested with CGRequestScreenCaptureAccess, with a friendly sheet that links to the right System Settings pane. Stitching: for each new frame, find the vertical overlap with the previous frame by comparing rows of downsampled grayscale pixels from the bottom of the previous frame against candidate offsets in the new frame, choosing the offset with the lowest sum of absolute differences, then append only the new rows. Draw the final image with CGContext. The global hotkey uses the Carbon RegisterEventHotKey API. Persist settings with AppStorage and launch at login with SMAppService.mainApp.

Edge cases and error handling: if permissions are missing, show a clear prompt and do nothing else. If the overlap match is poor (sum difference above a threshold), keep going but flag the result as possibly misaligned in the notification. Sticky headers and footers can repeat, so offer a Trim Fixed Header and Footer pair of numeric fields in points that are cropped from every frame after the first. Retina scaling must be respected by multiplying by the display backing scale factor. Very tall output beyond 16000 pixels is split into multiple files. If the save folder is gone, fall back to the Desktop. If the region is smaller than 100 points, reject it with a hint. Multiple displays are supported by picking the display under the cursor.
