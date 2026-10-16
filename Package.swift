// swift-tools-version: 6.0
// SwiftPM manifest used by xtool to build the app on Windows (WSL) or Linux, no Mac needed.
// Mac users can keep using CameraGlassPro.xcodeproj; both build the same CameraGlassPro/ sources.

import PackageDescription

let package = Package(
    name: "CameraGlassPro",
    platforms: [
        .iOS(.v18),
    ],
    products: [
        // xtool bundles exactly one library product as the app.
        .library(name: "CameraGlassPro", targets: ["CameraGlassPro"]),
    ],
    targets: [
        .target(
            name: "CameraGlassPro",
            path: "CameraGlassPro",
            // actool is Mac-only; xtool takes the icon from xtool.yml instead.
            exclude: ["Assets.xcassets"]
        ),
    ],
    swiftLanguageModes: [.v5] // matches SWIFT_VERSION = 5.0 in the Xcode project
)
