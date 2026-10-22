# Camera Glass Pro: camera, composition and finishing features

This page covers the camera and composition features added on 2026-10-22 and how far each one has been checked.
The existing edit screen (filters, adjustments, effects, subject tools, video) is described in `HANDOFF.md` and `README.md`.

## Verification levels

| Level | Meaning |
|---|---|
| **Source** | The code is written. |
| **CI build** | It compiles with Xcode 26 on GitHub's macOS runner. |
| **Unit test** | Its logic passes tests in the iPhone Simulator. |
| **Device** | Someone has tried it on a real iPhone. |

**No camera feature has been tried on a real iPhone yet.** The Simulator has no camera. CI can only prove that the camera code compiles and that its logic is correct.

## What each control does

The main screen keeps its existing layout. The controls now work as follows.

| Control | While shooting (live camera) | With a photo open |
|---|---|---|
| Shutter | Takes a photo (with the timer if one is set). Touch and hold to import instead. | Goes back to the camera. Touch and hold for Photos or Files. |
| Thumbnail | Opens the **Library**. | Opens Export (unchanged). |
| Round button (↻) | Switches between front and back camera. | Imports from Files (unchanged). |
| Zoom row | Real lens zoom (.5 only if the iPhone has an ultra wide; tele presets from the hardware). Pinch zooms too. | Preview zoom (unchanged). |
| Top-bar EV / exposure slider | Camera exposure compensation. | Edit exposure (unchanged). |
| Tap / hold the viewfinder | Focus and exposure at that point / AE-AF lock. Drag up or down next to the box to change EV. | Unchanged. |
| ƒ, FILTER, STYLES, NIGHT MODE | Chosen before the shot and applied to the captured photo. Filters and Styles also preview live on the viewfinder. | Unchanged. |
| ASPECT | Cycles 3:4 → 4:5 → 9:16 → 1:1. It becomes the photo's real crop (non-destructive and editable in Crop). | Unchanged. |
| FLASH | Real flash mode (off, auto, on) when the camera has one. | Visual only (unchanged). |

The ⠿ panel has a new **PRO** page.

- **SCAN** analyzes the live scene and suggests a frame.
- **COMPOSE** lets you draw a custom frame and track a subject.
- **MANUAL** sets ISO, shutter speed, focus and white balance.
- **RAW** cycles Off → RAW → ProRAW, offering only what the iPhone supports.
- **TORCH** turns the flashlight on and off.

**SCAN** is also pinned to the top bar by default, in place of LIVE. Live Photo *capture* isn't implemented, so LIVE is disabled while shooting.

## Feature status

| Feature | Status | Notes |
|---|---|---|
| Live preview, capture, front/back, permission and error states, interruptions, background/foreground | Source, CI build | `Camera/CameraService.swift`, `Camera/LiveCameraModel.swift`. Capture uses the largest photo size and quality prioritization. |
| HEIF / JPEG capture | Source, CI build | Follows the FORMAT control (JPEG → JPEG; HEIF or PNG → HEIF capture). |
| RAW (Bayer) and Apple ProRAW | Source, CI build | Only offered when `AVCapturePhotoOutput` reports it. The DNG becomes the project's original, and edits render from it. The camera's processed HEIF is kept beside it as `camera.heic`. A JPEG is never labeled RAW. |
| Manual ISO, shutter, focus, white balance | Source, CI build | Each row is enabled only if the device supports that mode. Some multi-camera (virtual) devices may not allow custom exposure; the row then shows N/A. |
| Lens-aware zoom | Source, CI build, unit test (presets) | Uses `displayVideoZoomFactorMultiplier` and the switch-over factors. |
| Capture aspect → crop | Source, CI build, unit test (geometry) | The crop is stored in the edit (`cropRect`), so the full sensor image is kept. |
| Composition scan | Source, CI build, unit test (engine) | Vision finds faces, people, objectness saliency and the horizon, plus a luminance sample. It merges 3 frames, then scores candidate crops on placement, size, room around the subject, headroom, cut-off subjects and resolution kept. Guidance is labeled *measured* (ruler icon) or *suggestion* (bulb icon). With no clear subject it says so instead of guessing. |
| Custom frame (COMPOSE) and subject tracking | Source, CI build, unit test (alignment) | Drag to draw, drag inside to move, drag a corner to resize. Choose a ratio (Free, 3:4, 4:5, 1:1, 9:16). Tap a subject to track it with `VNTrackObjectRequest`. The frame turns yellow with a haptic tap when the subject reaches a third or the center. The camera never moves on its own: tracking only guides you. |
| Live look preview | Source, CI build | Applies the filter, its strength and the Photographic Style to live frames on the GPU. Subject-dependent and heavy effects appear after capture, at full quality. |
| Signature looks (8 original presets) | Source, CI build, unit test | Daylight Neg, Push 1600, Sun Faded, Silver Tone, Soft Bloom, Deep Print, Quiet Cinema, Golden Split. They are a new first filter tab, and each one is adjustable. |
| Curves (RGB, R, G, B) | Source, CI build, unit test | Adjust › Color. Monotone cubic curve feeding Core Image color curves. |
| Color calibration | Source, CI build, unit test | Adjust › Color. Shifts the hue and saturation of the red, green and blue primaries. This is an approximation of how camera profiles do it. |
| Dust, Scratches | Source, CI build, unit test | Adjust › Effects. They use a fixed pattern, so the same photo always gets the same marks. |
| Frames (Plain, White, Paper, Black, Negative, Specs) and date stamp | Source, CI build, unit test | Export › Finish, with a preview. Applied to the exported copy only. The Specs frame uses real EXIF values and says "unavailable" when they're missing. The date stamp needs a capture date. |
| Metadata in edited exports | Source, CI build, unit test | Capture details carry over to the edited copy, and orientation is reset. **Remove Location** drops GPS. |
| Library (projects) | Source, CI build, unit test (store) | Every capture and every imported photo becomes a project. The original is stored byte-for-byte, and the edit, framing and finish are kept as JSON. You can reopen, duplicate the edit, or delete (with a confirmation). Projects whose original is missing are still listed, so you can delete them. |

## Owner rule 1 and frames

Rule 1 says no filter or effect may burn text, dates, borders or watermarks into the picture. That still holds, and its test still runs over every filter.

Frames and the date stamp are a separate, opt-in **finishing** step that the owner asked for on 2026-10-22. They live only in the export (`ExportOptions.finish`, `FinishingRenderer`) and are never part of `PhotoAdjustmentState` or the filter and effect pipeline.

## Known limits and things to check on a device

- Horizon direction: the sign of Vision's horizon angle was reasoned from the documentation, not measured on a device. If "turn counterclockwise" points the wrong way, negate it in `SceneAnalyzer.analyze`.
- Live look performance with heavy filters on older iPhones is unmeasured. The Metal view renders at 2× scale.
- Custom exposure on virtual multi-lens devices: some iPhones may report it unsupported. The UI then disables the row.
- RAW and ProRAW capture, flash, torch, lens switching, the permission flow and interruptions all need a real iPhone to verify.
- The app now needs camera permission (`NSCameraUsageDescription`). Sideloadly signing doesn't need any extra entitlement for the camera.
