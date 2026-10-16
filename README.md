# Camera Glass Pro

A native SwiftUI iPhone app with a camera-style workspace for photos you **already have**. You import a photo, then frame it with zoom, aspect ratios and composition guides. You can adjust it without touching the original, and export the original or an edited copy. The controls are Liquid Glass.

> Camera Glass Pro is a third-party app. It does not use the camera, capture photos or video, or replace Apple's Camera app. An **IMPORTED PHOTO** badge (which you can turn off in Settings) makes this clear in the viewfinder.

## Build status (read this first)

| Item | Status |
|---|---|
| Source code, Xcode project, scheme, tests | Complete. Written on Windows. |
| Compiled with Xcode | **Not yet.** There was no macOS or Xcode in the authoring environment. |
| Unit tests executed | **Not yet.** They run on the first Mac or CI build. |
| `.ipa` | **Not produced yet.** Build it with the GitHub Actions workflow or on a Mac (see below). |

The first Xcode build may find a few compile errors that a static review missed. They should be small, local fixes.

## Requirements

- **Xcode 26** or later, with the iOS 26 SDK. Liquid Glass (`glassEffect`, `GlassEffectContainer`) requires it. The project uses Xcode 16+ synchronized folders.
- Deployment target: **iOS 18.0**. iOS 26+ gets native Liquid Glass. iOS 18–25 get a material-based fallback.
- iPhone only, portrait.
- No third-party dependencies.

If you build with an older Xcode (16.x), the `#if compiler(>=6.2)` guards drop the Liquid Glass code paths and every OS uses the fallback.

## Features

| Area | What it does | Real or simulated |
|---|---|---|
| Import | `PhotosPicker` (no library permission needed). Files via `fileImporter`. iCloud originals download through the picker. Shows a loading state and has Cancel. | Real |
| Large images | ImageIO downsampled preview (2400 px max). The original bytes stay in memory as compressed data. Images over 250 MP are rejected. | Real |
| Zoom | .5 / 1 / 2 / 5 presets, a fine slider (0.5–5×), pinch to zoom, and double-tap to reset to 1×. | Real (preview crop) |
| Aspect | Original, 4:3, 16:9, 1:1. Fixed ratios follow the photo's orientation. | Real (preview framing) |
| Guides | Rule-of-thirds grid, fine grid, opacity, level guide, center crosshair, and mode framing bands | Real overlays. The level guide is static and doesn't read sensors. |
| Adjustments | Exposure, brightness, contrast, saturation, warmth, highlights and shadows (Core Image). Per-control reset, Reset All, and hold-to-compare. | Real, non-destructive |
| Night Look | Shadow lift plus noise reduction | Real filter. It is not a capture mode. |
| Flash | Off / Auto / On. "On" plays a screen flash when you use the center control. | Visual only |
| Live | Shows a LIVE badge | Preference only |
| Timer | 3 s / 10 s countdown before the photo picker opens | Real delay |
| Modes | PHOTO is the working mode. PORTRAIT adds a vignette, and VIDEO / CINEMATIC / PANO show framing bands. Each one says "Preview only". | Simulated looks |
| Export | Original as an exact byte-for-byte copy, or an edited copy (JPEG/HEIC/PNG) at full resolution. Optional crop to framing and optional burned-in guides. Uses the native share sheet (Save Image, Files, AirDrop). | Real |
| Settings | Appearance, glass or solid controls, control opacity, composition, preview defaults, export defaults, accessibility, About. Stored with `@AppStorage`. | Real |

**Center control:** the big circle imports a photo when none is loaded, or replaces the current one. Touch and hold it for Photos or Files. Its accessibility label says "Import photo" or "Replace photo". It never claims to take a picture.

**When you import a new photo:** zoom and aspect go back to your Settings defaults. Adjustments go back to neutral unless **Keep Adjustments on Replace** is on. A slower, older import can never overwrite a newer one, because each import has a generation token.

**Metadata:** an exported original keeps whatever metadata the file already had, since it is byte-for-byte. Edited copies are rendered fresh and carry no capture metadata. The app never adds or forges EXIF, GPS, timestamps or camera model.

## Project structure

```
CameraGlassPro.xcodeproj/          Xcode project (synchronized folders) + shared scheme
CameraGlassPro/
  App/CameraGlassProApp.swift
  Models/          CameraMode, PreviewFraming (aspect/zoom/geometry), PhotoAdjustmentState, CameraSettings
  ViewModels/      CameraWorkspaceViewModel (@Observable, @MainActor)
  Views/           Workspace, Toolbar, PhotoPreview (+ empty state), BottomControls, ModeSelector,
                   ControlPanel, AdjustmentView, ExportView, SettingsView
  Components/      CameraGlassModifier (glass system), GlassButton, ZoomSelector,
                   CompositionOverlays (grid/level/center/mode guides), LoadingOverlay
  Services/        PhotoImportService, ImageProcessingService (Core Image), PhotoExportService
  Utilities/       ImageDownsampler (ImageIO)
  Assets.xcassets  AppIcon (original artwork), AccentColor
CameraGlassProTests/               XCTest unit tests
.github/workflows/build-ipa.yml    CI: test + unsigned .ipa on a GitHub macOS runner
ExportOptions.plist                Development-signed export options for xcodebuild
project.yml                        XcodeGen fallback if the .xcodeproj ever fails to open
```

**Glass system.** `cameraGlass(_:in:)` takes four styles: regular, interactive, subtle and selected.
- On iOS 26 it uses `glassEffect`, and `GlassGroup` wraps `GlassEffectContainer`.
- On iOS 18–25 it uses an `.thinMaterial` / `.ultraThinMaterial` fill with a fine border, a specular top edge and a soft shadow.
- It switches to a solid style when Reduce Transparency is on, or when you choose **Solid** in Settings.

## Build and run on a Mac

1. Open `CameraGlassPro.xcodeproj` in Xcode 26.
2. Select the **CameraGlassPro** target. Under **Signing & Capabilities**, choose your Team. If the bundle ID is taken, change it from `com.example.CameraGlassPro` to something unique.
3. Simulator: pick any iPhone simulator and press **Run** (⌘R). To get a test photo, drag an image onto the simulator window and it lands in Photos.
4. Device: connect your iPhone and turn on **Developer Mode** (Settings › Privacy & Security). Select the iPhone and press **Run**.

Run the tests from the command line, choosing any installed iPhone simulator:

```bash
xcodebuild test -project CameraGlassPro.xcodeproj -scheme CameraGlassPro -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Archive and export an `.ipa` (Mac)

```bash
xcodebuild archive -project CameraGlassPro.xcodeproj -scheme CameraGlassPro -configuration Release -destination 'generic/platform=iOS' -archivePath build/CameraGlassPro.xcarchive DEVELOPMENT_TEAM=YOURTEAMID -allowProvisioningUpdates
```

```bash
xcodebuild -exportArchive -archivePath build/CameraGlassPro.xcarchive -exportPath build/ipa -exportOptionsPlist ExportOptions.plist -allowProvisioningUpdates
```

This writes `build/ipa/CameraGlassPro.ipa`, which is development-signed and installs on devices registered to your team. You can also use Xcode's **Product › Archive**, then **Distribute App**.

## Building on Windows, no Mac (xtool + WSL)

[xtool](https://github.com/xtool-org/xtool) is an open-source Xcode replacement for Linux and Windows (WSL). It builds this repo's `Package.swift` into a real iOS app with Apple's iOS SDK. It can also sign the app with your Apple ID, package an `.ipa`, and install it over USB. `Package.swift`, `xtool.yml` and `Packaging/Info.plist` hold the configuration, and they build the same `CameraGlassPro/` sources as the Xcode project.

**One-time setup**

1. In PowerShell, install Ubuntu 24.04 in WSL. On first launch it asks you to create a Linux username and password.
   ```bash
   wsl --install -d Ubuntu-24.04
   ```
2. Install Swift 6.4, xtool, usbmuxd and the build dependencies. Run this in the Ubuntu terminal:
   ```bash
   cd /mnt/e/workclaude/camera_glass_pro && ./scripts/setup-wsl.sh
   ```
3. In a Windows browser, sign in with your Apple ID and download **Xcode 27** (`.xip`, about 3 GB) from <https://developer.apple.com/download/all/?q=Xcode>. You don't need a Mac for this. xtool only extracts the iOS SDK from the file.
4. In Ubuntu, run the setup below. It asks for your Apple ID, then the path to the xip, for example `/mnt/c/Users/<you>/Downloads/Xcode_27.0.xip`.
   ```bash
   xtool setup
   ```
   - **Login mode 1 (password):** works with a free Apple ID. It uses private Apple APIs, so the xtool docs suggest a spare Apple ID.
   - **Login mode 0 (API key):** needs the paid Developer Program.
5. In `xtool.yml`, change `bundleID` to something unique, such as `com.yourname.CameraGlassPro`.

**Build**

From Ubuntu, in the project folder:

| Command | Result |
|---|---|
| `./scripts/build-ipa.sh` | Unsigned `dist/CameraGlassPro.ipa`. Sign it later with Sideloadly or AltStore. |
| `./scripts/build-ipa.sh --sign` | `.ipa` signed with your Apple ID |
| `./scripts/build-ipa.sh --install` | Builds, signs and installs straight to a USB-connected iPhone |

On Windows you can double-click `build-ipa.cmd` instead.

- **USB install:** needs USB passthrough into WSL ([usbipd](https://learn.microsoft.com/en-us/windows/wsl/connect-usb)). Otherwise, copy the `.ipa` to Windows and use Sideloadly.
- **First launch:** trust the developer on the iPhone in Settings › General › VPN & Device Management.
- **First build:** slow, because SwiftPM compiles the iOS SDK modules once.

**What the xtool build doesn't do:**
- Run the XCTest suite. Use Xcode or the GitHub workflow for tests.
- Compile `Assets.xcassets`. The app icon comes from `xtool.yml` instead. Nothing in the code reads the accent color.

## Building without a Mac (GitHub Actions)

1. Push this folder to a GitHub repository. Private works.
2. Go to **Actions › Build IPA › Run workflow**. The workflow runs on `macos-26`. If that runner label isn't available, change it to the newest `macos-*` image that has Xcode 26.
3. The workflow runs the unit tests and builds the app without signing. It then uploads **CameraGlassPro-unsigned-ipa** and **test-results** as artifacts.

### Installing from Windows

An unsigned `.ipa` **will not install as-is**. You have to sign it first. On Windows, Sideloadly or AltStore can sign it with your Apple ID:

- **Free Apple ID:** the app expires after 7 days and has to be re-signed. Apple also caps the number of sideloaded apps.
- **Paid Apple Developer account ($99/yr):** signatures last a year. It also unlocks the Mac archive flow above, ad-hoc distribution and TestFlight.

Either way, the iPhone needs **Developer Mode** on.

### Types of build output

| Output | Can it run on an iPhone? |
|---|---|
| Simulator build (`*-iphonesimulator/*.app`) | No. It runs only in the simulator. |
| Unsigned build or unsigned `.ipa` (what CI produces) | No, not until it is signed. |
| Development-signed `.ipa` | Yes, on devices registered to your team. |
| App Store / TestFlight build | Yes, through Apple's distribution channels. |

A file ending in `.ipa` is not automatically installable. The signature and provisioning are what make it install.

## Manual test checklist

- Empty state shows. **Import Photo** and **Browse Files** both open the right picker.
- Import a HEIC, a JPEG and a large panorama. Check that orientation is correct, the image isn't stretched, and the spinner and Cancel work.
- Import over an existing photo. The new photo wins, even if you start two imports quickly.
- Grid cycles off → thirds → fine. Level and center guides toggle. Guides stay aligned at every zoom.
- Zoom presets, the slider, pinch and double-tap all work. Aspect cycles through all four options. **Reset** in the panel restores the defaults.
- Every adjustment slider works. Check per-control reset, Reset All, hold-to-compare, and the EDITED badge on the thumbnail.
- Export: the original is byte-identical. The edited copy works in JPEG, HEIC and PNG, with crop and with guides. Save Image asks for permission to add to Photos.
- Settings persist across app launches. **Reset All Preferences** restores the defaults.
- Turn on Reduce Motion: there are no scale transitions and no screen flash. With Increase Contrast and Reduce Transparency, controls switch to solid backgrounds.
- VoiceOver: every control has a label, and selected states are announced.
- Larger text sizes, iPhone SE / mini width, and light versus dark sheets.

## Troubleshooting

- **"Signing requires a development team"**: choose your Team in Signing & Capabilities, or pass `DEVELOPMENT_TEAM=` to xcodebuild.
- **The project won't open or reports a damaged file**: run `brew install xcodegen && xcodegen` in this folder to regenerate it from `project.yml`.
- **`glassEffect` not found**: you are on an SDK older than iOS 26. Install Xcode 26, or accept the fallback (see Requirements).
- **The Warmth slider goes the wrong way**: `ImageProcessingTests.testWarmthDirection` checks this. If it fails, flip the sign in `ImageProcessingService.apply`.

## Privacy

Everything is processed on the device. There are no network calls, analytics or tracking. Photos come in only through the system pickers, so the app never asks for access to your whole library. The only permission it asks for is "add to Photos", and only when you choose Save Image. Photos are never written to preferences. Exports go to a temporary folder, and only the most recent one is kept.

## Known limitations

- Not compiled or tested yet (see Build status).
- Zoom is centered. You can't drag to pan, so "crop to framing" always crops around the center.
- The level guide is static and doesn't read sensors.
- Modes other than Photo are preview-only looks.
- Burned-in guides cover the grid and center crosshair only, not the level guide or mode bands.
- No RAW development. RAW files import through ImageIO's default rendering.
- No pinch-to-zoom haptics. Haptics fire only on discrete events.
