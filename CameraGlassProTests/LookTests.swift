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
