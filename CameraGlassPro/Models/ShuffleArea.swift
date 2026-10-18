import Foundation

/// Shuffle per area: each dice button randomizes only the settings of its own tab or page, within
/// natural-looking ranges. Areas where randomness makes no sense (privacy, local filters) have no shuffle.
extension PhotoAdjustmentState {
    static func canShuffle(_ area: ResetArea) -> Bool {
        switch area {
        case .light, .color, .detail, .effects, .filter, .fxBlur, .fxBlend, .fxGhost, .fxArt, .fxLight, .fxRetro, .fxPop, .subjectCreate: true
        case .local, .adjust, .fxPrivacy, .subjectStyle: false
        }
    }

    /// This edit with only `area` randomized, or nil when the area can't be shuffled.
    /// `category` limits the Filter shuffle to one tab; `hasSecondPhoto` allows Double Exposure.
    func shuffling<G: RandomNumberGenerator>(_ area: ResetArea, category: FilterCategory? = nil, hasSecondPhoto: Bool = false,
                                             using rng: inout G) -> PhotoAdjustmentState? {
        guard Self.canShuffle(area) else { return nil }
        var next = self
        func random(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &rng) }
        func coin(_ chance: Double = 0.5) -> Bool { Double.random(in: 0..<1, using: &rng) < chance }

        switch area {
        case .light:
            next.exposure = random(-0.6...0.6)
            next.brightness = random(-0.08...0.08)
            next.contrast = random(0.9...1.2)
            next.highlights = random(-0.6...0)
            next.shadows = random(-0.2...0.5)
        case .color:
            next.saturation = random(0.8...1.3)
            next.warmth = random(-0.35...0.35)
            var mixer = ColorMixer()
            for _ in 0..<2 { // nudge two colors
                let band = ColorBand.allCases.randomElement(using: &rng) ?? .orange
                mixer[band, .hue] = random(-0.35...0.35)
                mixer[band, .saturation] = random(-0.4...0.4)
                mixer[band, .luminance] = random(-0.3...0.3)
            }
            next.colorMixer = mixer
        case .detail:
            next.texture = random(-0.2...0.5)
            next.sharpen = random(0...0.5)
            next.noiseReduction = random(0...0.4)
        case .effects:
            next.vignette = random(-0.1...0.5)
            next.halation = coin() ? random(0.2...0.6) : 0
            next.grain = random(0...0.5)
            next.grainSize = GrainSize.allCases.randomElement(using: &rng) ?? .medium
        case .filter:
            let pool = (category?.filters ?? PhotoFilter.allCases.filter { $0 != .none }).filter { $0 != filter }
            next.filter = pool.randomElement(using: &rng) ?? filter
            next.filterStrength = random(0.7...1)
            next.grain = coin(0.6) ? random(0.1...0.4) : 0
            next.grainSize = GrainSize.allCases.randomElement(using: &rng) ?? .medium
        case .fxBlur:
            // Usually one of the two, sometimes both.
            let speed = coin(0.6)
            next.speedBlur = speed ? random(0.25...0.8) : 0
            next.speedAngle = random(0...180)
            next.tiltShift = !speed || coin(0.3) ? random(0.3...0.85) : 0
            next.tiltShiftPosition = random(0.35...0.7)
        case .fxBlend:
            next.doubleExposure = hasSecondPhoto ? random(0.35...0.9) : doubleExposure
            if var match = lookMatch {
                match.amount = random(0.4...1)
                next.lookMatch = match
            }
        case .fxGhost:
            next.ghostOpacity = random(0.3...0.8)
            next.ghostDistance = random(0.08...0.6)
            next.ghostAngle = random(0...360)
            if ghostTarget == .subject { next.ghostHideOriginal = coin(0.3) }
        case .fxArt:
            // One art effect at a time, with a random setting.
            next = resetting(.fxArt)
            switch ArtEffect.allCases.randomElement(using: &rng) ?? .hologram {
            case .hologram: next.hologram = random(0.5...1)
            case .vision:
                next.visionMode = coin() ? .thermal : .night
                next.visionAmount = random(0.7...1)
            case .sort:
                next.pixelSort = random(0.3...0.9)
                next.pixelSortVertical = coin()
            case .orbit:
                next.orbitCount = Double(Int.random(in: 3...9, using: &rng))
                next.orbitSize = random(0.25...0.7)
                next.orbitDistance = random(0.2...0.8)
            case .melt: next.melt = random(0.4...1)
            case .planet:
                next.littlePlanet = random(0.3...1)
                next.planetSpin = random(0...360)
            case .depth:
                next.depthMap = random(0.6...1)
                next.depthHeat = coin()
            }
        case .fxLight:
            next = resetting(.fxLight)
            switch LightEffect.allCases.randomElement(using: &rng) ?? .glow {
            case .blinds:
                next.blinds = random(0.4...0.9)
                next.blindsAngle = random(15...60)
                next.blindsSize = random(0.2...0.7)
            case .spot:
                next.spotlight = random(0.4...0.9)
                next.spotlightSize = random(0.3...0.7)
            case .glow: next.glow = random(0.3...0.8)
            case .sparkle: next.sparkle = random(0.4...1)
            }
        case .fxRetro:
            next = resetting(.fxRetro)
            switch RetroEffect.allCases.randomElement(using: &rng) ?? .vhs {
            case .vhs: next.vhs = random(0.5...1)
            case .webcam: next.webcam = random(0.6...1)
            case .halftone:
                next.halftone = random(0.6...1)
                next.halftoneDot = random(0.2...0.7)
                next.halftoneBalance = random(-0.4...0.4)
                next.halftoneColor = coin()
            case .chroma: next.chroma = random(0.3...0.9)
            }
        case .fxPop:
            next.pop = PopEffect.allCases.filter { $0 != .none && $0 != pop }.randomElement(using: &rng) ?? .glitch
            next.popAmount = random(0.6...1)
            next.popOption = random(0...1)
        case .subjectCreate:
            next.dispersion = random(0.4...1)
            next.dispersionSize = random(0.2...0.8)
            next.dispersionAngle = random(0...360)
        case .local, .adjust, .fxPrivacy, .subjectStyle:
            return nil
        }
        return next
    }
}
