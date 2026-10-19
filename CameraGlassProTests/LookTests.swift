import CoreImage
import UIKit
import XCTest
@testable import CameraGlassPro

/// Renders every filter, style and effect on real photos (CC0, see Photos/CREDITS.md) into labeled contact
/// sheets. The sheets are kept as test attachments; CI publishes them (release "screenshots") so the looks
/// can be judged on real pictures, not only measured on flat test images.
final class LookTests: XCTestCase {
    private let processor = ImageProcessingService.shared
    private let tileWidth: CGFloat = 400

    /// A bundled test photo, scaled to `tileWidth`.
    private func photo(_ name: String) throws -> CIImage {
        let bundle = Bundle(for: LookTests.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "jpg")
            ?? bundle.url(forResource: name, withExtension: "jpg", subdirectory: "Photos"), "\(name).jpg missing")
        let image = try XCTUnwrap(CIImage(contentsOf: url, options: [.applyOrientationProperty: true]))
        let s = tileWidth / image.extent.width
        return image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY)
            .concatenating(CGAffineTransform(scaleX: s, y: s)))
    }

    /// Grid of labeled tiles, 6 across, kept as a JPEG attachment.
    private func sheet(_ name: String, _ tiles: [(String, CIImage)]) {
        guard let first = tiles.first?.1 else { return }
        let columns = 6
        let tile = CGSize(width: tileWidth, height: first.extent.height.rounded())
        let label: CGFloat = 26
        let rows = (tiles.count + columns - 1) / columns
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: tile.width * CGFloat(columns), height: (tile.height + label) * CGFloat(rows))
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (index, (title, picture)) in tiles.enumerated() {
                let x = CGFloat(index % columns) * tile.width, y = CGFloat(index / columns) * (tile.height + label)
                if let cg = processor.context.createCGImage(picture, from: CGRect(origin: .zero, size: tile)) {
                    UIImage(cgImage: cg).draw(in: CGRect(x: x, y: y, width: tile.width, height: tile.height))
                }
                (title as NSString).draw(at: CGPoint(x: x + 6, y: y + tile.height + 3), withAttributes: [
                    .font: UIFont.systemFont(ofSize: 18, weight: .semibold), .foregroundColor: UIColor.white,
                ])
            }
        }
        guard let data = image.jpegData(compressionQuality: 0.82) else { return XCTFail("sheet \(name) didn't encode") }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.jpeg")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func render(_ state: PhotoAdjustmentState, _ image: CIImage) -> CIImage {
        processor.apply(state, to: image).cropped(to: image.extent)
    }

    private func with(_ change: (inout PhotoAdjustmentState) -> Void) -> PhotoAdjustmentState {
        var state = PhotoAdjustmentState()
        change(&state)
        return state
    }

    func testFilterSheetsOnRealPhotos() throws {
        let filters = PhotoFilter.allCases
        for name in ["night", "portrait", "landscape", "food"] {
            let image = try photo(name)
            for (part, chunk) in stride(from: 0, to: filters.count, by: 60).map({ Array(filters[$0..<min($0 + 60, filters.count)]) }).enumerated() {
                sheet("looks-filters-\(name)-\(part + 1)", chunk.map { filter in
                    (filter == .none ? "Original" : filter.label, render(with { $0.filter = filter }, image))
                })
            }
        }
    }

    func testStyleSheet() throws {
        let image = try photo("portrait")
        sheet("looks-styles-portrait", PhotographicStyle.allCases.map { style in (style.label, render(with { $0.style = style }, image)) })
    }

    func testEffectSheets() throws {
        var effects: [(String, PhotoAdjustmentState)] = [
            ("Original", PhotoAdjustmentState()),
            ("Speed Blur", with { $0.speedBlur = 0.6 }), ("Tilt-Shift", with { $0.tiltShift = 0.7 }),
            ("Ghost", with { $0.ghostOpacity = 0.5 }), ("Hologram", with { $0.hologram = 0.8 }),
            ("Thermal", with { $0.visionMode = .thermal }), ("Night Vision", with { $0.visionMode = .night }),
            ("Pixel Sort", with { $0.pixelSort = 0.6 }), ("Orbit", with { $0.orbitCount = 6 }), ("Melt", with { $0.melt = 0.7 }),
            ("Planet", with { $0.littlePlanet = 0.8 }), ("Depth", with { $0.depthMap = 1 }),
            ("Blinds", with { $0.blinds = 0.7 }), ("Spotlight", with { $0.spotlight = 0.7 }), ("Glow", with { $0.glow = 0.6 }),
            ("Sparkle", with { $0.sparkle = 0.8 }), ("VHS", with { $0.vhs = 0.8 }), ("Webcam", with { $0.webcam = 0.8 }),
            ("Halftone", with { $0.halftone = 0.8 }), ("Chroma", with { $0.chroma = 0.7 }),
            ("Portrait f2", with { $0.portrait = true; $0.aperture = 2 }), ("Color Splash", with { $0.colorSplash = true }),
            ("Halation", with { $0.halation = 0.8 }), ("Grain", with { $0.grain = 0.6 }),
            ("Smooth Skin", with { $0.skinSmoothing = 0.8 }), ("Vignette", with { $0.vignette = 0.6 }),
        ]
        effects += PopEffect.allCases.filter { $0 != .none }.map { pop in (pop.label, with { $0.pop = pop; $0.popAmount = 0.9 }) }
        effects += BackgroundBlurKind.allCases.map { kind in
            ("Blur \(kind.label)", with { $0.background = .blur; $0.backgroundBlurKind = kind; $0.backgroundBlurAmount = 0.7 })
        }
        for name in ["portrait", "landscape", "night"] {
            let image = try photo(name)
            sheet("looks-effects-\(name)", effects.map { ($0.0, render($0.1, image)) })
        }
    }

    func testPack5Sheet() throws {
        for name in ["landscape", "sunset"] {
            let image = try photo(name)
            let skies = SkyReplacement.allCases.filter { $0 != .photo }.map { kind in
                (kind == .none ? "Original" : "Sky \(kind.label)", render(with { $0.skyReplace = kind }, image))
            }
            let removed = render(with { $0.removeStrokes = [MaskStroke(add: true, width: 0.08, points: [CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.56, y: 0.62)])] }, image)
            let story = PhotoExportService.storyFill(image)
            let storyTile = story.transformed(by: CGAffineTransform(scaleX: image.extent.height / story.extent.height,
                                                                    y: image.extent.height / story.extent.height))
                .composited(over: CIImage(color: .black).cropped(to: image.extent))
            sheet("looks-pack5-\(name)", skies + [("Remove (middle)", removed), ("9:16 Story", storyTile)])
        }
    }

    func testPack6Sheet() throws {
        let portrait = try photo("portrait"), landscape = try photo("landscape"), sunset = try photo("sunset")
        let food = try photo("food"), night = try photo("night")
        func stroke(_ x: CGFloat, _ y: CGFloat, _ width: Double, to end: CGPoint? = nil) -> MaskStroke {
            MaskStroke(add: true, width: width, points: [CGPoint(x: x, y: y)] + (end.map { [$0] } ?? []))
        }
        var tiles: [(String, CIImage)] = [
            ("Portrait", portrait),
            ("Eyes + Teeth", render(with { $0.eyeBrighten = 1; $0.teethWhiten = 1 }, portrait)),
            ("Focus on rock", render(with { $0.focusStrokes = [stroke(0.27, 0.6, 0.25)]; $0.focusBlur = 0.8 }, landscape)),
            ("Remove spire top", render(with { $0.removeStrokes = [stroke(0.5, 0.05, 0.04, to: CGPoint(x: 0.5, y: 0.25))] }, sunset)),
            ("Remove house", render(with { $0.removeStrokes = [stroke(0.9, 0.62, 0.18)] }, sunset)),
            ("Sunset sky band", render(with { $0.skyReplace = .golden }, sunset)),
        ]
        for (index, cells) in Collage.layouts(for: 4).enumerated() {
            if let collage = Collage.render([portrait, landscape, food, night], layout: cells, shape: .square, longEdge: 400) {
                let fitted = collage.transformed(by: CGAffineTransform(scaleX: portrait.extent.height / 400, y: portrait.extent.height / 400))
                    .composited(over: CIImage(color: .black).cropped(to: portrait.extent))
                tiles.append(("Collage \(index + 1)", fitted))
            }
        }
        sheet("looks-pack6", tiles)
    }

    /// A hand-made mask of the woman in portrait.jpg (the simulator can't detect people), for subject effects.
    private func portraitMask(_ image: CIImage) -> CIImage {
        let e = image.extent
        func disc(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> CIImage {
            (CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: e.width * x, y: e.height * (1 - y)), "inputRadius0": e.width * r * 0.97,
                "inputRadius1": e.width * r, "inputColor0": CIColor.white, "inputColor1": CIColor.black,
            ])?.outputImage ?? CIImage.empty()).cropped(to: e)
        }
        let body = CIImage(color: .white).cropped(to: CGRect(x: e.width * 0.42, y: 0, width: e.width * 0.36, height: e.height * 0.4))
        return [disc(0.57, 0.42, 0.2), disc(0.66, 0.27, 0.2), disc(0.76, 0.42, 0.13), body]
            .reduce(CIImage(color: .black).cropped(to: e)) { $1.applyingFilter("CIMaximumCompositing", parameters: [kCIInputBackgroundImageKey: $0]) }
            .cropped(to: e)
    }

    /// Particle Dissolve next to the reference look, plus its controls, and the original Pieces style.
    func testParticleDissolveSheet() throws {
        let image = try photo("portrait")
        let mask = portraitMask(image)
        func dissolve(_ change: (inout PhotoAdjustmentState) -> Void) -> CIImage {
            var state = PhotoAdjustmentState()
            state.dispersionStyle = .particleDissolve
            state.dissolveAmount = 0.55
            change(&state)
            return processor.apply(state, to: image, subjectMask: mask).cropped(to: image.extent)
        }
        var pieces = PhotoAdjustmentState()
        pieces.dispersion = 0.8
        sheet("looks-particle-dissolve", [
            ("Original", image), ("Mask (test)", mask),
            ("Default", dissolve { _ in }), ("Dissolve 85", dissolve { $0.dissolveAmount = 0.85 }),
            ("Dissolve 25", dissolve { $0.dissolveAmount = 0.25 }), ("Size 80", dissolve { $0.dissolveSize = 0.8 }),
            ("Spread 90", dissolve { $0.dissolveSpread = 0.9 }), ("Spread 10", dissolve { $0.dissolveSpread = 0.1 }),
            ("Density 20", dissolve { $0.dissolveDensity = 0.2 }), ("Softness 5", dissolve { $0.dissolveSoftness = 0.05 }),
            ("Softness 100", dissolve { $0.dissolveSoftness = 1 }), ("Direction 180", dissolve { $0.dissolveAngle = 180 }),
            ("Direction 90", dissolve { $0.dissolveAngle = 90 }), ("Pieces (old)", processor.apply(pieces, to: image, subjectMask: mask)),
        ])
        // Full size crop of the default, to judge particle detail.
        let large = try XCTUnwrap(CIImage(contentsOf: try XCTUnwrap(Bundle(for: LookTests.self).url(forResource: "portrait", withExtension: "jpg")),
                                          options: [.applyOrientationProperty: true]))
        var state = PhotoAdjustmentState()
        state.dispersionStyle = .particleDissolve
        state.dissolveAmount = 0.55
        let scale = large.extent.width / image.extent.width
        let bigMask = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let full = processor.apply(state, to: large, subjectMask: bigMask)
        let crop = CGRect(x: large.extent.width * 0.45, y: large.extent.height * 0.3, width: 400, height: large.extent.height * 0.45)
        sheet("looks-particle-dissolve-detail", [("Default, full size (crop)", full.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: 1, y: 1)))])
    }

    /// Background blur and privacy at low to high strength.
    func testStrengthSheets() throws {
        let image = try photo("portrait")
        let mask = portraitMask(image)
        var tiles: [(String, CIImage)] = []
        for kind in [BackgroundBlurKind.soft, .zoom, .lens] {
            for amount in [0.0, 0.1, 0.3, 0.6, 1.0] {
                var state = PhotoAdjustmentState()
                state.background = .blur
                state.backgroundBlurKind = kind
                state.backgroundBlurAmount = amount
                tiles.append(("\(kind.label) \(Int(amount * 100))", processor.apply(state, to: image, subjectMask: mask)))
            }
            tiles.append(("", image))
        }
        for mode in [Redaction.blur, .pixelate] {
            for strength in [0.0, 0.25, 0.5, 0.75, 1.0] {
                var state = PhotoAdjustmentState()
                state.redactionTarget = .drawing
                state.redactionStrength = strength
                state.redactionStrokes = [RedactionStroke(mode: mode, width: 0.3, points: [CGPoint(x: 0.6, y: 0.4)])]
                tiles.append(("\(mode.label) \(Int(strength * 100))", processor.apply(state, to: image)))
            }
            tiles.append(("", image))
        }
        sheet("looks-strengths", tiles)
    }

    /// Pack 8: echo, subject effects, new photo FX and adjustments on real photos.
    func testPack8Sheet() throws {
        let portrait = try photo("portrait"), landscape = try photo("landscape"), sunset = try photo("sunset")
        let mask = portraitMask(portrait)
        func subject(_ change: (inout PhotoAdjustmentState) -> Void) -> CIImage {
            processor.apply(with(change), to: portrait, subjectMask: mask).cropped(to: portrait.extent)
        }
        sheet("looks-pack8", [
            ("Dissolve echo 100", subject { $0.dispersionStyle = .particleDissolve; $0.dissolveAmount = 0.55; $0.dissolveEcho = 1 }),
            ("Dissolve echo 0", subject { $0.dispersionStyle = .particleDissolve; $0.dissolveAmount = 0.55; $0.dissolveEcho = 0 }),
            ("Neon 80", subject { $0.neonOutline = 0.8 }), ("Aura 80", subject { $0.aura = 0.8 }),
            ("Silhouette 100", subject { $0.silhouette = 1 }), ("Shadow 80", subject { $0.subjectShadow = 0.8 }),
            ("Fog", render(with { $0.weather = .fog; $0.weatherAmount = 0.6 }, landscape)),
            ("Rain", render(with { $0.weather = .rain; $0.weatherAmount = 0.6 }, landscape)),
            ("Snow", render(with { $0.weather = .snow; $0.weatherAmount = 0.6 }, landscape)),
            ("God Rays", render(with { $0.weather = .rays; $0.weatherAmount = 0.6 }, sunset)),
            ("Flare", render(with { $0.flare = 0.7 }, sunset)), ("Prism", render(with { $0.prism = 0.7 }, portrait)),
            ("Oil", render(with { $0.paint = 0.8; $0.paintStyle = .oil }, landscape)),
            ("Watercolor", render(with { $0.paint = 0.8; $0.paintStyle = .watercolor }, landscape)),
            ("Sketch", render(with { $0.paint = 0.8; $0.paintStyle = .sketch }, portrait)),
            ("Mirror left", render(with { $0.mirror = .left }, landscape)),
            ("Brilliance 80", render(with { $0.brilliance = 0.8 }, sunset)), ("Clarity 80", render(with { $0.clarity = 0.8 }, landscape)),
            ("Fade 60", render(with { $0.fade = 0.6 }, portrait)),
            ("Grade teal/orange", render(with { $0.gradeShadowAmount = 0.6; $0.gradeHighlightAmount = 0.6 }, sunset)),
        ])
    }

    /// The raw masks everything subject- and sky-based is built on (white = subject / sky), next to each photo.
    func testMaskSheet() throws {
        var tiles: [(String, CIImage)] = []
        for name in ["portrait", "landscape", "food", "night"] {
            let image = try photo(name)
            let e = image.extent
            let black = CIImage(color: .black).cropped(to: e)
            tiles.append((name, image))
            tiles.append(("subject", SubjectMasker.mask(for: image)?.cropped(to: e).composited(over: black) ?? black))
            tiles.append(("person (fast)", SubjectMasker.mask(for: image, fast: true)?.cropped(to: e).composited(over: black) ?? black))
            tiles.append(("sky", processor.skyMask(for: image, extent: e)?.composited(over: black) ?? black))
        }
        sheet("looks-masks", tiles)
    }

    /// Owner rule: pure black stays neutral. Checked on a real night photo for every filter.
    func testNightBlacksStayNeutralOnARealPhoto() throws {
        let image = try photo("night")
        let w = Int(image.extent.width), h = Int(image.extent.height)
        func pixels(_ picture: CIImage) -> [UInt8] {
            var p = [UInt8](repeating: 0, count: w * h * 4)
            processor.context.render(picture, toBitmap: &p, rowBytes: w * 4, bounds: CGRect(x: 0, y: 0, width: w, height: h),
                                     format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return p
        }
        let original = pixels(image)
        let blacks = stride(from: 0, to: original.count, by: 4).filter { max(original[$0], original[$0 + 1], original[$0 + 2]) < 12 }
        guard blacks.count > 50 else { throw XCTSkip("too few near-black pixels in the night photo") }
        // Every look except duotones (Game Boy maps black to its dark color on purpose).
        for filter in PhotoFilter.allCases where filter != .none && LookRecipe.recipe(filter)?.duotone == nil {
            let out = pixels(render(with { $0.filter = filter }, image))
            let chroma = blacks.reduce(0.0) { sum, i in
                sum + Double(max(out[i], out[i + 1], out[i + 2]) - min(out[i], out[i + 1], out[i + 2]))
            } / Double(blacks.count)
            XCTAssertLessThan(chroma, 12, "\(filter.label) tints the black night sky (average color spread \(Int(chroma))/255)")
        }
    }
}
