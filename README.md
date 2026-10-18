# Camera Glass Pro

A native SwiftUI iPhone app with a camera-style workspace for photos you **already have**. You import a photo, then frame it with zoom, aspect ratios and composition guides. You can adjust it without touching the original, and export the original or an edited copy. The controls are Liquid Glass.

> Camera Glass Pro is a third-party app. It does not use the camera, capture photos or video, or replace Apple's Camera app. The UI mirrors the iOS 27 Camera layout: the photo fills the viewfinder, with the status icons, zoom, ƒ, shutter and ⠿ controls floating over it.

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
| Zoom | .5 / 1 / 2 / 5 presets; swipe the zoom row (or tap the active value) for the curved zoom dial (log scale, haptic ticks at presets); pinch; drag to pan when zoomed in; double-tap resets. | Real (preview crop; crop export follows the pan) |
| Aspect | Original, 4:3, 16:9, 1:1. Fixed ratios follow the photo's orientation. | Real (preview framing) |
| Guides | Rule-of-thirds grid, fine grid, opacity, level guide and center crosshair | Real overlays. The level follows the phone's sideways tilt (CoreMotion) and turns yellow within 1° of level. |
| Adjustments | Exposure, brightness, contrast, saturation, warmth, highlights and shadows (Core Image). Per-control reset, Reset All, and hold-to-compare. Auto (magic wand) sets exposure, contrast, highlights, shadows, saturation and warmth from the photo's histogram and color cast, as one undo step you can fine-tune. While Adjust or any edit pop-up is open, the photo shrinks (same framing) to sit fully above it, so every change stays visible; the Adjust sheet stops at half height. | Real, non-destructive |
| AI edit | Top of Adjust: describe the look in words ("moody and cinematic", "brighter face, darker background") and Apple's on-device model (Foundation Models, iOS 26 with Apple Intelligence) sets the editor's own sliders, filter and subject/background values as one undo step. Afterwards it lists exactly what it moved (those sliders get a ✦ mark) with Undo AI Edit / Keep buttons. It never generates pixels and nothing leaves the phone. Other iPhones see a short note instead. | Real; needs Apple Intelligence |
| Vignette | Adjust slider: + darkens, − lightens the corners with a soft radial falloff (in exposure stops, so hues stay true). Framed on the final cropped picture, applied before grain. | Real |
| Halation | Adjust slider: the red-orange glow real film gets around bright lights (CineStill style). Only highlights feed it, so dark areas stay clean. | Real |
| Subject vs background | SUBJECT pop-up > ADJUST: brightness, saturation and warmth for just the subject or just the background, using the same on-device subject mask as Portrait. | Real |
| Film stocks | FILTER > Film tab: Portra 400, Ektar 100, Gold 200, Fuji 400H, CineStill 800T and Tri-X 400, built from tone curves, white balance and split toning. Picking one also sets matching grain (and CineStill its halation) unless you already set those. Strength slider applies. | Real (inspired by, not measured from, the film stocks) |
| Smooth Skin | Adjust slider: softens skin only, on faces found on-device (Vision), on skin-colored pixels and never across edges, so eyes, lips and hair stay sharp. Photos without faces are unchanged. | Real |
| Perspective | Crop editor: Vertical and Horizontal keystone sliders straighten leaning buildings and walls; the frame stays filled (no empty corners). Photos only. | Real |
| Graduated & Radial | Adjust > Graduated & Radial: up to four filters. Graduated starts from an edge (top/bottom/left/right) with Reach and Softness; Radial has position, size, softness and inside/outside. Each sets brightness, saturation and warmth inside its mask; a small map shows the mask in yellow on the photo. | Real |
| Noise Reduction & Sharpen | Adjust sliders. Noise Reduction is a Metal kernel: edge-aware brightness smoothing (real edges are kept) plus color-speckle removal, with average brightness unchanged; Sharpen is luminance-only and sized to the picture. | Real |
| Sky | SUBJECT pop-up > ADJUST > Sky: brightness, saturation and warmth for the sky only. The sky is found on-device from color (blue, overcast or dark night sky), smoothness and position, so a plain bright wall near the top can be included. | Real (heuristic, not a trained model) |
| FX | FX pop-up (controls panel > Edit > FX) in three pages. Blur: Speed Blur streaks the background behind the subject (with direction); Tilt-Shift makes a miniature with a movable focus band. Blend: Double Exposure shows a second photo through the subject while the background fades to white (whole frame without a subject). Privacy: choose Faces or Drawing (only one is hidden; switching keeps the other's settings). Faces: blur or pixelate every detected face. Drawing: Draw to Blur or Pixelate with a finger in a full-screen editor (Undo and Redo strokes; Clear All asks first and can be undone), with Brush size and a Strength slider for blur amount / pixel size. Shuffle (dice, also in FILTER) tries a random filter, grain and vignette. | Real |
| Subject creations | SUBJECT > Create: Sticker saves the edited subject as a transparent PNG to Photos and copies it; 3D Video makes a 4-second clip where the subject floats in front of a moving background (opens as a new item). Dispersion breaks the subject into square particles that drift away, with Strength, Particle Size and Direction sliders. | Real |
| Layout | Busy panels are split into short pages with the same glass style: the controls panel (Camera, Edit, Tools), Adjust (Light, Color, Detail, Effects, Local, AI), SUBJECT (Style, Adjust, Create) and FX (Blur, Blend, Privacy). Grain size is a small menu next to GRAIN. The main camera screen is unchanged. Every glass control takes taps across its whole shape, pop-up cards keep one height across pages, and while a pop-up is open a tap outside it closes it instead of pressing the controls underneath. | Real |
| Color Mixer | In Adjust: pick one of eight colors (red, orange, yellow, green, aqua, blue, purple, magenta) and shift its hue, saturation and luminance. Neighboring colors blend smoothly and grays are never touched. Runs as a 3D lookup table in Core Image. | Real |
| Night Look | Shadow lift plus noise reduction | Real filter. It is not a capture mode. |
| Flash | Off / Auto / On. "On" plays a screen flash when you use the center control. | Visual only |
| Live | Shows a LIVE badge | Preference only |
| Timer | 3 s / 10 s countdown before the photo picker opens | Real delay |
| Modes | PHOTO is the working mode. PORTRAIT adds a vignette; VIDEO, SLO-MO and TIME-LAPSE play imported videos; CINEMATIC and PANO say "Preview only". | Simulated looks |
| Export | Original as an exact byte-for-byte copy, or an edited copy (JPEG/HEIC/PNG) at full resolution. Optional crop to framing and optional burned-in guides. Uses the native share sheet (Save Image, Files, AirDrop). | Real |
| ⠿ panel | FLASH, LIVE, ASPECT, TIMER, EXPOSURE (slider), STYLES (adjustments), FILTER (Vivid/Mono/Noir/Chrome/Fade/Instant), DEPTH, NIGHT MODE, FORMAT (export format) | Real except Flash/Live (visual) and Depth (preview-only vignette) |
| Video | Import videos from Photos or Files. Full-screen looping playback; the red center control plays/pauses (stop square while playing) with a running timecode. Exposure, Styles, Filter and Night Look apply live per frame and to the edited MOV export. | Real |
| Save Screen with UI | Export sheet › Save Screen with UI: captures the viewfinder with the camera controls exactly as shown and adds it to Photos (videos use the current frame). | Real |
| Top bar | Pick which controls appear: open ⠿, tap **Edit** (top-left), then + / − on any control. Saved across launches. Timer and depth also appear while they're on. | Real |
| Grid & Level | GRID (off / thirds / fine) and LEVEL buttons in the ⠿ panel; saved across launches. | Real |
| Exposure scopes | SCOPES control cycles Luminance histogram, RGB histogram and RGB Parade waveform, in a panel top-left of the viewfinder (live for videos, ~4×/s). | Real |
| Focus peaking | PEAKING control paints the sharpest edges red (display only, never exported). | Real |
| Save Video with UI | Export sheet › Save Video with UI: records the screen with ReplayKit while your video plays once (≤ 60 s; shutter stops early), then saves it to Photos. | Real |
| Landscape | The layout stays portrait; icons, zoom labels and the level turn upright when you hold the phone sideways (CoreMotion, with hysteresis). | Real |
| App icon | Standard, dark and tinted Home Screen variants. | — |
| Styles 3 | Texture (local contrast) and film Grain in Adjust. Grain is monochrome film grain (two soft grain sizes, about 2 px on the preview) added to brightness only in display space, so it never tints colors; strongest in midtones, lighter in shadows, none in bright highlights; sized to the image so preview and export match; Fine / Medium / Coarse grain size in the FILTER pop-up; rendered by a Metal Core Image kernel; 0 = no grain. | Real |
| Highlight clipping | ZEBRAS control stripes near-white areas (display only). | Real |
| Undo / presets | Undo/redo in Adjust (a slider drag is one step); save, apply and delete named styles. | Real |
| SLO-MO / TIME-LAPSE | Imported videos play at 1/4 or 8x in these modes; the edited MOV exports at that speed. | Real |
| Trim | TRIM control: start/end handles; playback loops inside, edited export and Save Video with UI use it. | Real |
| Multi-select | Pick up to 20 photos/videos (Photos or Files); swipe sideways (when not zoomed) to move between them; each keeps its own edits; "2 / 5" counter. | Real |
| Restore | Reopens the last photo/video with its edits, mode, zoom, aspect, pan and trim on relaunch (one copy kept in the app's private storage). | Real |
| Live Text | TEXT control: on-device text recognition (Vision) with tappable boxes (tap = copy line), Show Text sheet with Copy All and on-device Translate. Pauses videos to scan the current frame. | Real |
| Mode carousel | Slide the mode strip like iOS 27: the capsule opens to full width, the thumbnail and Files button hide, labels glide under a fixed glass pill, the centered mode lights up with a haptic tick, and it snaps on release. Tap a mode to jump; tap the selected one for controls. | — |
| Filters | FILTER opens a glass pop-up with live preview tiles for 100 filters in 12 scrolling tabs: Classic, Film, Cinematic, Portrait, Nature, B&W, Vintage, Moody, Food, Y2K, Quality and DigiCam FX. Every look was checked on night, portrait and nature photos; split toning never tints pure black. Looks use tone curves and luminance-weighted split toning; none adds grain, text, borders or watermarks. The pop-up has a STRENGTH slider (0–100%, blends the look with the unfiltered photo), an independent GRAIN slider (0 = none), hold-for-original compare and Reset All. | Real |
| Tap to focus/expose | Tap the photo: yellow focus square meters exposure for that spot; drag up/down for the sun slider; touch and hold for AE/AF LOCK. | Real (exposure); focus is visual for imported media |
| Photographic Styles | STYLES opens the iOS-style pad: 16 styles (Standard, Amber, Gold, Rose Gold, Neutral, Cool Rose, Cool, Vibrant, Natural, Luminous, Dramatic, Quiet, Cozy, Ethereal, Muted/Stark B&W), a Tone x Color touch pad and a Palette slider. | Real |
| Portrait | Real background blur: Vision finds the subject (people, pets, objects), the background blurs by f-number (f1.4-16 slider from the top-bar f readout), and Portrait Lighting applies (Natural, Studio, Contour, Stage, Stage Mono, High-Key) via the cube button. Works on photos, video frames (person segmentation) and exports. | Real |
| Live Photos | Live Photos import with their motion: touch and hold the LIVE badge to play (LIVE on = plays once when opened). | Real |
| Effects | EFFECTS pop-up: Loop, Bounce and Long Exposure from a video or Live Photo (with your edits; result opens as a new item), and Live Photo: turns the whole video (or its trimmed part) into a real Live Photo saved to the library, with the frame on screen as the photo. | Real |
| Export size | Edited photos: Full, 12 MP, 4 MP or 1 MP (long edge, Lanczos, never enlarged). Edited videos: Full, 4K, 1080p or 720p. Originals always export byte-for-byte. | Real |
| Live Photo sound | Switch in Effects: Live Photos made from videos keep the video's sound (interleaved AAC) or save silent. Remembered. | Real |
| Subject | SUBJECT pop-up: Color Splash (subject in color, background black and white) and Background Swap (Original, Blur, Black, White, Gray, Sky, Sunset, or one of your photos), using on-device subject detection; combines with Portrait. Photos, video frames and exports. | Real |
| Crop | CROP opens a full-screen editor: crop box with corner handles and thirds grid, straighten (+/-45 degrees, auto-zoom so no empty corners), rotate 90, flip, Auto (Vision horizon) and aspect presets (Freeform, Original, Square, 4:3, 3:4, 16:9, 9:16). One undo step; preview and export match. Photos only (videos keep their frame). | Real |
| Depth tags | PORTRAIT / NATURAL LIGHT (or PORTRAIT OFF) show for about 1.6 s after toggling depth, then fade. | — |
| Layout | iOS 27 Camera style: full-screen photo, plain status row, ƒ / shutter / ⠿ over the photo, thumbnail (export) · mode capsule · Files button in the bottom bar. No settings screen. | — |

**Center control:** the big circle imports a photo when none is loaded, or replaces the current one. Touch and hold it for Photos or Files. Its accessibility label says "Import photo" or "Replace photo". It never claims to take a picture.

**When you import a new photo:** zoom and aspect go back to their defaults (1×, full screen). Adjustments go back to neutral unless **Keep Adjustments on Replace** is on. A slower, older import can never overwrite a newer one, because each import has a generation token.

**Metadata:** an exported original keeps whatever metadata the file already had, since it is byte-for-byte. Edited copies are rendered fresh and carry no capture metadata. The app never adds or forges EXIF, GPS, timestamps or camera model.

## Project structure

```
CameraGlassPro.xcodeproj/          Xcode project (synchronized folders) + shared scheme
CameraGlassPro/
  App/CameraGlassProApp.swift
  Models/          CameraMode, PreviewFraming (aspect/zoom/geometry), PhotoAdjustmentState, CameraSettings
  ViewModels/      CameraWorkspaceViewModel (@Observable, @MainActor)
  Views/           Workspace, Toolbar, PhotoPreview (+ empty state), BottomControls, ModeSelector,
                   ControlPanel, AdjustmentView, ExportView
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
- It switches to a solid style when Reduce Transparency is on.

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
- Grid and export format persist across app launches.
- Turn on Reduce Motion: there are no scale transitions and no screen flash. With Increase Contrast and Reduce Transparency, controls switch to solid backgrounds.
- VoiceOver: every control has a label, and selected states are announced.
- Larger text sizes, iPhone SE / mini width, and light versus dark sheets.

## Troubleshooting

- **"Signing requires a development team"**: choose your Team in Signing & Capabilities, or pass `DEVELOPMENT_TEAM=` to xcodebuild.
- **The project won't open or reports a damaged file**: run `brew install xcodegen && xcodegen` in this folder to regenerate it from `project.yml`.
- **`glassEffect` not found**: you are on an SDK older than iOS 26. Install Xcode 26, or accept the fallback (see Requirements).
- **The Warmth slider goes the wrong way**: `ImageProcessingTests.testWarmthDirection` checks this on every CI run.

## Privacy

Everything is processed on the device. There are no network calls, analytics or tracking. Photos come in only through the system pickers, so the app never asks for access to your whole library. The only permission it asks for is "add to Photos", and only when you choose Save Image. Photos are never written to preferences. Exports go to a temporary folder, and only the most recent one is kept.

## Known limitations

- Not compiled or tested yet (see Build status).
- The level shows phone tilt, not the horizon inside the photo.
- Modes other than Photo are preview-only looks.
- Burned-in guides cover the grid and center crosshair only, not the level guide or mode bands.
- No RAW development. RAW files import through ImageIO's default rendering.
- No pinch-to-zoom haptics. Haptics fire only on discrete events.
