import CoreGraphics
import Foundation

/// Non-destructive edit recipe. The original image bytes are never touched;
/// this struct is applied to the preview while editing and to the full image on export.
struct PhotoAdjustmentState: Equatable, Codable, Sendable {
    var exposure: Double = 0
    var brightness: Double = 0
    var contrast: Double = 1
    var saturation: Double = 1
    var warmth: Double = 0
    var highlights: Double = 0
    var shadows: Double = 0
    /// White and black points (-1...1), Dehaze (+ cuts haze, - adds it), Tint (+ magenta, - green), Vibrance.
    var whites: Double = 0
    var blacks: Double = 0
    var dehaze: Double = 0
    var tint: Double = 0
    var vibrance: Double = 0
    /// Local contrast (iOS 27 "Styles 3" texture): + crisper detail, − softer.
    var texture: Double = 0
    /// Film-like luminance grain.
    var grain: Double = 0
    var grainSize: GrainSize = .medium
    /// Fine detail (0...1) and noise cleanup (0...1).
    var sharpen: Double = 0
    var noiseReduction: Double = 0
    /// Softens skin on detected faces (0...1).
    var skinSmoothing: Double = 0
    /// Darkens (+) or lightens (−) the corners.
    var vignette: Double = 0
    /// Per-color hue, saturation and luminance.
    var colorMixer = ColorMixer()
    /// Film halation: red-orange glow bleeding around bright lights (0...1).
    var halation: Double = 0
    /// "Night Look": lifts shadows and reduces noise. A real filter, not a capture mode.
    var nightLook = false
    /// Photo look applied after the adjustments (the panel's FILTER control).
    var filter: PhotoFilter = .none
    /// How much of the filter is applied (0...1), blended with the unfiltered photo.
    var filterStrength: Double = 1
    /// Where the filter applies: everywhere, only the subject, or only the background.
    var filterTarget: FilterTarget = .all
    /// Photographic Style and its 2D pad position (Tone vertical, Color horizontal) and Palette strength.
    var style: PhotographicStyle = .standard
    var styleTone: Double = 0
    var styleColor: Double = 0
    var stylePalette: Double = 1
    /// Real Portrait: subject kept sharp, background blurred by `aperture` (ƒ1.4–16), with lighting.
    var portrait = false
    var aperture: Double = 2.8
    var lighting: PortraitLighting = .natural
    /// Subject in color, background black and white.
    var colorSplash = false
    /// What goes behind the subject.
    var background: BackgroundStyle = .original
    /// Separate light and color for the subject and for the background (subject mask).
    var subjectEdit = RegionEdit()
    var backgroundEdit = RegionEdit()
    /// Light and color for the detected sky only.
    var skyEdit = RegionEdit()
    /// Motion blur behind the subject (0...1) and its direction in degrees (0 = horizontal).
    var speedBlur: Double = 0
    var speedAngle: Double = 0
    /// Miniature effect: blur strength (0...1) and where the sharp band sits (0 top ... 1 bottom).
    var tiltShift: Double = 0
    var tiltShiftPosition: Double = 0.55
    /// Blends the second photo in (0...1): through the subject when one is found, else over everything.
    var doubleExposure: Double = 0
    /// Colors and tones matched to a reference photo (nil = off).
    var lookMatch: LookMatch?
    /// Hide every detected face, and painted areas (final framing).
    var faceRedaction: Redaction = .none
    /// Faces or drawing: only the chosen one is hidden (the other's settings are kept for switching back).
    var redactionTarget: RedactionTarget = .faces
    /// How strongly faces and painted areas are hidden: blur amount or pixel block size (0...1).
    var redactionStrength: Double = 0.5
    /// Dispersion: the subject breaks into particles (strength 0...1, particle size 0...1).
    var dispersion: Double = 0
    var dispersionSize: Double = 0.4
    /// Which way the particles drift, in degrees: 0 right, 90 up, 180 left, 270 down.
    var dispersionAngle: Double = 0
    /// Ghost: a translucent copy of the subject or whole photo, moved (opacity 0 = off).
    var ghostOpacity: Double = 0
    var ghostDistance: Double = 0.25
    var ghostAngle: Double = 0
    var ghostTarget: GhostTarget = .subject
    var ghostHideOriginal = false
    /// Background blur kind and strength when the background is Blur.
    var backgroundBlurKind: BackgroundBlurKind = .soft
    var backgroundBlurAmount: Double = 0.5
    /// Art FX. Hologram, Melt (0 = off) and Orbit (clone count, under 2 = off) need the subject.
    var hologram: Double = 0
    var melt: Double = 0
    var orbitCount: Double = 0
    var orbitSize: Double = 0.45
    var orbitDistance: Double = 0.5
    var visionMode: VisionMode = .none
    var visionAmount: Double = 1
    var pixelSort: Double = 0
    var pixelSortVertical = false
    var pixelSortSubjectOnly = false
    /// Little Planet: 0 = off, higher = bigger planet; spin turns it (degrees).
    var littlePlanet: Double = 0
    var planetSpin: Double = 0
    /// Depth Map (estimated): mix amount, gray or heat colors.
    var depthMap: Double = 0
    var depthHeat = false
    /// Light FX: window blinds, spotlight, Orton glow, sparkle.
    var blinds: Double = 0
    var blindsAngle: Double = 35
    var blindsSize: Double = 0.4
    var spotlight: Double = 0
    var spotlightSize: Double = 0.5
    var glow: Double = 0
    var sparkle: Double = 0
    /// Retro FX: VHS, halftone (mix, dot size, black-white balance, color), chroma fringe.
    var vhs: Double = 0
    var halftone: Double = 0
    var halftoneDot: Double = 0.4
    var halftoneBalance: Double = 0
    var halftoneColor = false
    var chroma: Double = 0
    /// Refine Subject strokes and Liquify pushes (photo coordinates before crop and rotation).
    var maskStrokes: [MaskStroke] = []
    var liquifyStrokes: [LiquifyStroke] = []

    var orbitClones: Int { orbitCount >= 1.5 ? Int(orbitCount.rounded()) : 0 }
    var redactionStrokes: [RedactionStroke] = []
    /// Graduated and radial filters, applied on the final framing.
    var localAdjustments: [LocalAdjustment] = []

    /// Crop (normalized, top-left origin, relative to the rotated/straightened photo), quarter turns
    /// clockwise, horizontal mirror and straighten angle in degrees. Photos only.
    var cropRect: CGRect = PhotoAdjustmentState.fullCrop
    var rotation = 0
    var flipped = false
    var straighten: Double = 0
    /// Keystone correction, -1...1: + widens the top (vertical) / the right side (horizontal).
    var perspectiveVertical: Double = 0
    var perspectiveHorizontal: Double = 0

    static let fullCrop = CGRect(x: 0, y: 0, width: 1, height: 1)

    var hasGeometry: Bool {
        cropRect != Self.fullCrop || ((rotation % 4) + 4) % 4 != 0 || flipped || abs(straighten) > 0.01
            || abs(perspectiveVertical) > 0.001 || abs(perspectiveHorizontal) > 0.001
    }

    /// Same edit without crop/rotate/flip/straighten (videos keep their frame size).
    var withoutGeometry: PhotoAdjustmentState {
        var copy = self
        copy.cropRect = Self.fullCrop
        copy.rotation = 0
        copy.flipped = false
        copy.straighten = 0
        copy.perspectiveVertical = 0
        copy.perspectiveHorizontal = 0
        return copy
    }

    /// Any edit that needs the subject mask.
    var needsSubject: Bool {
        portrait || colorSplash || background != .original || !subjectEdit.isNeutral || !backgroundEdit.isNeutral
            || speedBlur > 0 || doubleExposure > 0 || dispersion > 0 || ghostOpacity > 0 // the subject goes back on top of the ghost
            || hologram > 0 || melt > 0 || orbitClones > 0 || (pixelSort > 0 && pixelSortSubjectOnly)
            || (filter != .none && filterTarget != .all) || spotlight > 0 || depthMap > 0
    }

    /// Same edit with everything that needs a subject switched off (what renders when none is found).
    var withoutSubjectEdits: PhotoAdjustmentState {
        var copy = self
        copy.portrait = false
        copy.colorSplash = false
        copy.background = .original
        copy.subjectEdit = RegionEdit()
        copy.backgroundEdit = RegionEdit()
        copy.speedBlur = 0 // double exposure still works without a subject
        copy.dispersion = 0
        if copy.ghostTarget == .subject { copy.ghostOpacity = 0 }
        copy.hologram = 0
        copy.melt = 0
        copy.orbitCount = 0
        copy.filterTarget = .all // no subject found: the filter covers everything
        if copy.pixelSortSubjectOnly { copy.pixelSort = 0 }
        return copy
    }

    subscript(region: PhotoRegion) -> RegionEdit {
        get {
            switch region {
            case .subject: subjectEdit
            case .background: backgroundEdit
            case .sky: skyEdit
            }
        }
        set {
            switch region {
            case .subject: subjectEdit = newValue
            case .background: backgroundEdit = newValue
            case .sky: skyEdit = newValue
            }
        }
    }

    var isIdentity: Bool { self == PhotoAdjustmentState() }

    /// Effects that work pixel by pixel or per subject: live video previews them at a lighter size.
    var isHeavy: Bool {
        needsSubject || dispersion > 0 || melt > 0 || pixelSort > 0 || littlePlanet > 0 || !liquifyStrokes.isEmpty
            || skinSmoothing > 0 || faceRedaction != .none || !redactionStrokes.isEmpty || halation > 0 || noiseReduction > 0
    }

    init() {}

    /// Missing keys fall back to defaults, so presets saved by older versions keep loading.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = (try? c.decodeIfPresent(Double.self, forKey: .whites)) ?? 0
        blacks = (try? c.decodeIfPresent(Double.self, forKey: .blacks)) ?? 0
        dehaze = (try? c.decodeIfPresent(Double.self, forKey: .dehaze)) ?? 0
        tint = (try? c.decodeIfPresent(Double.self, forKey: .tint)) ?? 0
        vibrance = (try? c.decodeIfPresent(Double.self, forKey: .vibrance)) ?? 0
        texture = try c.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? 0
        grainSize = (try? c.decodeIfPresent(GrainSize.self, forKey: .grainSize)) ?? .medium
        vignette = min(max(try c.decodeIfPresent(Double.self, forKey: .vignette) ?? 0, -1), 1)
        colorMixer = (try? c.decodeIfPresent(ColorMixer.self, forKey: .colorMixer)) ?? ColorMixer()
        halation = min(max(try c.decodeIfPresent(Double.self, forKey: .halation) ?? 0, 0), 1)
        skinSmoothing = min(max(try c.decodeIfPresent(Double.self, forKey: .skinSmoothing) ?? 0, 0), 1)
        sharpen = min(max(try c.decodeIfPresent(Double.self, forKey: .sharpen) ?? 0, 0), 1)
        noiseReduction = min(max(try c.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0, 0), 1)
        subjectEdit = (try? c.decodeIfPresent(RegionEdit.self, forKey: .subjectEdit)) ?? RegionEdit()
        backgroundEdit = (try? c.decodeIfPresent(RegionEdit.self, forKey: .backgroundEdit)) ?? RegionEdit()
        skyEdit = (try? c.decodeIfPresent(RegionEdit.self, forKey: .skyEdit)) ?? RegionEdit()
        func unit(_ key: CodingKeys, _ fallback: Double = 0) -> Double {
            let v = (try? c.decodeIfPresent(Double.self, forKey: key)) ?? fallback
            return v.isFinite ? min(max(v, 0), 1) : fallback
        }
        speedBlur = unit(.speedBlur)
        speedAngle = min(max((try? c.decodeIfPresent(Double.self, forKey: .speedAngle)) ?? 0, 0), 180)
        tiltShift = unit(.tiltShift)
        tiltShiftPosition = unit(.tiltShiftPosition, 0.55)
        doubleExposure = unit(.doubleExposure)
        lookMatch = (try? c.decodeIfPresent(LookMatch.self, forKey: .lookMatch)).flatMap { $0.isUsable ? $0 : nil }
        redactionStrength = unit(.redactionStrength, 0.5)
        dispersion = unit(.dispersion)
        dispersionSize = unit(.dispersionSize, 0.4)
        ghostOpacity = unit(.ghostOpacity)
        ghostDistance = unit(.ghostDistance, 0.25)
        ghostAngle = min(max((try? c.decodeIfPresent(Double.self, forKey: .ghostAngle)) ?? 0, 0), 360)
        ghostTarget = (try? c.decodeIfPresent(GhostTarget.self, forKey: .ghostTarget)) ?? .subject
        ghostHideOriginal = (try? c.decodeIfPresent(Bool.self, forKey: .ghostHideOriginal)) ?? false
        backgroundBlurKind = (try? c.decodeIfPresent(BackgroundBlurKind.self, forKey: .backgroundBlurKind)) ?? .soft
        backgroundBlurAmount = unit(.backgroundBlurAmount, 0.5)
        hologram = unit(.hologram)
        melt = unit(.melt)
        orbitCount = min(max((try? c.decodeIfPresent(Double.self, forKey: .orbitCount)) ?? 0, 0), 12)
        orbitSize = unit(.orbitSize, 0.45)
        orbitDistance = unit(.orbitDistance, 0.5)
        visionMode = (try? c.decodeIfPresent(VisionMode.self, forKey: .visionMode)) ?? .none
        visionAmount = unit(.visionAmount, 1)
        pixelSort = unit(.pixelSort)
        pixelSortVertical = (try? c.decodeIfPresent(Bool.self, forKey: .pixelSortVertical)) ?? false
        pixelSortSubjectOnly = (try? c.decodeIfPresent(Bool.self, forKey: .pixelSortSubjectOnly)) ?? false
        littlePlanet = unit(.littlePlanet)
        depthMap = unit(.depthMap)
        depthHeat = (try? c.decodeIfPresent(Bool.self, forKey: .depthHeat)) ?? false
        blinds = unit(.blinds)
        blindsAngle = min(max((try? c.decodeIfPresent(Double.self, forKey: .blindsAngle)) ?? 35, 0), 180)
        blindsSize = unit(.blindsSize, 0.4)
        spotlight = unit(.spotlight)
        spotlightSize = unit(.spotlightSize, 0.5)
        glow = unit(.glow)
        sparkle = unit(.sparkle)
        vhs = unit(.vhs)
        halftone = unit(.halftone)
        halftoneDot = unit(.halftoneDot, 0.4)
        halftoneBalance = min(max((try? c.decodeIfPresent(Double.self, forKey: .halftoneBalance)) ?? 0, -1), 1)
        halftoneColor = (try? c.decodeIfPresent(Bool.self, forKey: .halftoneColor)) ?? false
        chroma = unit(.chroma)
        maskStrokes = Array(((try? c.decodeIfPresent([MaskStroke].self, forKey: .maskStrokes)) ?? []).prefix(MaskStroke.limit))
        liquifyStrokes = Array(((try? c.decodeIfPresent([LiquifyStroke].self, forKey: .liquifyStrokes)) ?? []).prefix(LiquifyStroke.limit))
        planetSpin = min(max((try? c.decodeIfPresent(Double.self, forKey: .planetSpin)) ?? 0, 0), 360)
        dispersionAngle = min(max((try? c.decodeIfPresent(Double.self, forKey: .dispersionAngle)) ?? 0, 0), 360)
        faceRedaction = (try? c.decodeIfPresent(Redaction.self, forKey: .faceRedaction)) ?? .none
        redactionStrokes = Array(((try? c.decodeIfPresent([RedactionStroke].self, forKey: .redactionStrokes)) ?? [])
            .prefix(RedactionStroke.limit))
        // Older saves had no choice: painted strokes mean Drawing.
        redactionTarget = (try? c.decodeIfPresent(RedactionTarget.self, forKey: .redactionTarget))
            ?? (redactionStrokes.isEmpty ? .faces : .drawing)
        localAdjustments = ((try? c.decodeIfPresent([LocalAdjustment].self, forKey: .localAdjustments)) ?? [])
            .prefix(LocalAdjustment.limit).map(\.clamped)
        nightLook = try c.decodeIfPresent(Bool.self, forKey: .nightLook) ?? false
        filter = (try? c.decodeIfPresent(PhotoFilter.self, forKey: .filter)) ?? .none
        filterStrength = min(max(try c.decodeIfPresent(Double.self, forKey: .filterStrength) ?? 1, 0), 1)
        filterTarget = (try? c.decodeIfPresent(FilterTarget.self, forKey: .filterTarget)) ?? .all
        style = try c.decodeIfPresent(PhotographicStyle.self, forKey: .style) ?? .standard
        styleTone = min(max(try c.decodeIfPresent(Double.self, forKey: .styleTone) ?? 0, -1), 1)
        styleColor = min(max(try c.decodeIfPresent(Double.self, forKey: .styleColor) ?? 0, -1), 1)
        stylePalette = min(max(try c.decodeIfPresent(Double.self, forKey: .stylePalette) ?? 1, 0), 1)
        portrait = try c.decodeIfPresent(Bool.self, forKey: .portrait) ?? false
        aperture = min(max(try c.decodeIfPresent(Double.self, forKey: .aperture) ?? 2.8, 1.4), 16)
        lighting = try c.decodeIfPresent(PortraitLighting.self, forKey: .lighting) ?? .natural
        colorSplash = try c.decodeIfPresent(Bool.self, forKey: .colorSplash) ?? false
        background = (try? c.decodeIfPresent(BackgroundStyle.self, forKey: .background)) ?? .original
        let crop = (try? c.decodeIfPresent(CGRect.self, forKey: .cropRect)) ?? Self.fullCrop
        cropRect = CGRect(x: 0, y: 0, width: 1, height: 1).contains(crop) && crop.width > 0.01 && crop.height > 0.01
            ? crop : Self.fullCrop
        rotation = ((try c.decodeIfPresent(Int.self, forKey: .rotation) ?? 0) % 4 + 4) % 4
        flipped = try c.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
        straighten = min(max(try c.decodeIfPresent(Double.self, forKey: .straighten) ?? 0, -45), 45)
        perspectiveVertical = min(max(try c.decodeIfPresent(Double.self, forKey: .perspectiveVertical) ?? 0, -1), 1)
        perspectiveHorizontal = min(max(try c.decodeIfPresent(Double.self, forKey: .perspectiveHorizontal) ?? 0, -1), 1)
    }

    subscript(parameter: AdjustmentParameter) -> Double {
        get { self[keyPath: parameter.keyPath] }
        set { self[keyPath: parameter.keyPath] = parameter.clamp(newValue) }
    }

    mutating func reset(_ parameter: AdjustmentParameter) {
        self[parameter] = parameter.defaultValue
    }

    func isModified(_ parameter: AdjustmentParameter) -> Bool {
        self[parameter] != parameter.defaultValue
    }

    /// Copy with every value inside its valid range (guards decoded or programmatic values).
    func clamped() -> PhotoAdjustmentState {
        var copy = self
        for parameter in AdjustmentParameter.allCases {
            copy[parameter] = self[keyPath: parameter.keyPath]
        }
        return copy
    }
}

/// Film grain size, as different film speeds: fine (slow film) to coarse (fast film).
enum GrainSize: String, CaseIterable, Codable, Sendable {
    case fine, medium, coarse

    var label: String { rawValue.capitalized }

    /// Grain cell = image width / divisor (medium ≈ 2 px on the 2400 px preview).
    var cellDivisor: CGFloat {
        switch self {
        case .fine: 1600
        case .medium: 1100
        case .coarse: 650
        }
    }
}

/// Pages of the Adjust sheet.
enum AdjustGroup: String, CaseIterable, Identifiable, Sendable {
    case light, color, detail, effects, local, ai

    var id: String { rawValue }
    var title: String { self == .ai ? "AI" : rawValue.capitalized }
}

enum AdjustmentParameter: String, CaseIterable, Identifiable, Sendable {
    case exposure, brightness, contrast, highlights, shadows, whites, blacks, dehaze, saturation, vibrance, warmth, tint,
         texture, sharpen, noise, skin, vignette, halation, grain

    var id: String { rawValue }
    var title: String {
        switch self {
        case .skin: "Smooth Skin"
        case .noise: "Noise Reduction"
        default: rawValue.capitalized
        }
    }

    var group: AdjustGroup {
        switch self {
        case .exposure, .brightness, .contrast, .highlights, .shadows, .whites, .blacks, .dehaze: .light
        case .saturation, .vibrance, .warmth, .tint: .color
        case .texture, .sharpen, .noise, .skin: .detail
        case .vignette, .halation, .grain: .effects
        }
    }

    var systemImage: String {
        switch self {
        case .exposure: "plusminus.circle"
        case .brightness: "sun.max"
        case .contrast: "circle.lefthalf.filled"
        case .saturation: "drop"
        case .warmth: "thermometer.medium"
        case .highlights: "circle.righthalf.filled.inverse"
        case .shadows: "circle.bottomhalf.filled"
        case .whites: "circle"
        case .blacks: "circle.fill"
        case .dehaze: "sun.haze.fill"
        case .tint: "drop.triangle"
        case .vibrance: "paintpalette"
        case .texture: "circle.hexagongrid"
        case .sharpen: "triangle"
        case .noise: "aqi.low"
        case .skin: "face.smiling"
        case .vignette: "camera.aperture"
        case .halation: "sun.haze"
        case .grain: "circle.dotted"
        }
    }

    var range: ClosedRange<Double> {
        switch self {
        case .exposure: -2...2          // EV stops
        case .brightness: -0.5...0.5
        case .contrast: 0.5...1.5
        case .saturation: 0...2
        case .warmth: -1...1
        case .highlights: -1...0        // 0 = unchanged, -1 = strongest recovery
        case .shadows: -1...1
        case .whites, .blacks, .dehaze, .tint, .vibrance: -1...1
        case .texture: -1...1
        case .sharpen, .noise: 0...1
        case .skin: 0...1
        case .vignette: -1...1        // + darker corners, − lighter
        case .halation: 0...1
        case .grain: 0...1
        }
    }

    var defaultValue: Double {
        switch self {
        case .contrast, .saturation: 1
        default: 0
        }
    }

    var keyPath: WritableKeyPath<PhotoAdjustmentState, Double> {
        switch self {
        case .exposure: \.exposure
        case .brightness: \.brightness
        case .contrast: \.contrast
        case .saturation: \.saturation
        case .warmth: \.warmth
        case .highlights: \.highlights
        case .shadows: \.shadows
        case .whites: \.whites
        case .blacks: \.blacks
        case .dehaze: \.dehaze
        case .tint: \.tint
        case .vibrance: \.vibrance
        case .texture: \.texture
        case .sharpen: \.sharpen
        case .noise: \.noiseReduction
        case .skin: \.skinSmoothing
        case .vignette: \.vignette
        case .halation: \.halation
        case .grain: \.grain
        }
    }

    func clamp(_ value: Double) -> Double {
        guard value.isFinite else { return defaultValue }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    /// Human-readable value: EV for exposure, signed -100...100 style for the rest.
    func format(_ value: Double) -> String {
        if self == .exposure { return String(format: "%+.1f EV", value) }
        let relative = Int(((value - defaultValue) * 100).rounded())
        return relative == 0 ? "0" : String(format: "%+ld", relative)
    }
}

/// Photo looks picked in the FILTER pop-up (grouped by `FilterCategory`).
enum PhotoFilter: String, CaseIterable, Codable, Sendable {
    case none, vivid, mono, noir, chrome, fade, instant
    case portra, ektar, gold, fuji400h, cinestill, trix
    // Recipe looks (LookRecipes.swift)
    case vividWarm, vividCool, dramatic, dramaticCool
    case portra160, superia400, ektachrome, velvia50, kodachrome, hp5, provia100f, ultramax400
    case tealOrange, blockbuster, moodyNight, bleachBypass, neonNoir, matrixGreen, desertHeat, vintageHollywood, arcticBlue, sunsetDrama
    case studioClean, goldenGlow, rosy, mattePortrait, brightAiry, warmSkin, softPeach, editorial
    case vividGreen, deepSky, autumn, alpineCool, desertGold, ocean, forestMood, springBloom
    case silver, softMatte, highContrast, selenium, sepia, infrared, platinum, cyanotype, redFilter
    case seventies, eighties, polaroidFade, kodakMoment, oldPostcard, sunbleached, retroTeal, lomo
    case darkAcademia, rainyDay, midnight, foggy, emberGlow, stormy, shadowBlue
    case freshFood, warmBakery, crispSalad, cafeLatte, juicy
    case disposable, bloomPop, frosted, cyberPink
    case cleanPro, vividHDR
    case pointShoot, nightFlash, coolCCD, y2006
    case aerochrome, crossProcess, technicolor, vaporwave, synthwave, animePastel, expiredFilm, underwaterFix
    case springLight, summerHeat, winterFrost, goldenHour
    case vision3, agfaVista, delta3200, lomoPurple, polaroid600, gameBoy
    case tokyoNeon, santoriniBlue, parisRose, thrillerGreen, pastelSymmetry, sunKissed
    case y2kGlow, flashPop, cyber, pastel
    case hd, clarity, hdr, crisp
    case digicam, ccd, retro

    var label: String {
        if let recipe = LookRecipe.recipe(self) { return recipe.label }
        return switch self {
        case .none: "Off"
        case .y2kGlow: "Y2K Glow"
        case .flashPop: "Flash Pop"
        case .pastel: "Pastel"
        case .hd: "HD"
        case .hdr: "HDR"
        case .digicam: "DigiCam"
        case .ccd: "CCD"
        case .portra: "Portra 400"
        case .ektar: "Ektar 100"
        case .gold: "Gold 200"
        case .fuji400h: "Fuji 400H"
        case .cinestill: "CineStill 800T"
        case .trix: "Tri-X 400"
        default: rawValue.capitalized
        }
    }

    var next: PhotoFilter {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}
