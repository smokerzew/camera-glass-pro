import Foundation

/// How effect strength sliders map to the effect actually applied. Effects are strong at full strength, so a
/// straight line made the low end far too strong (20% of a glitch or blur is already obvious). Strength is
/// squared instead: 10% gives 1%, 30% gives 9%, half gives a quarter, full stays full. Sliders keep showing the
/// value you set; only the rendering uses the curve. Exposure, contrast and the other light and color sliders
/// keep their own units (EV etc.) and are not affected.
extension PhotoAdjustmentState {
    /// 0...1 strengths.
    static let effectStrengths: [WritableKeyPath<PhotoAdjustmentState, Double>] = [
        \.speedBlur, \.tiltShift, \.doubleExposure, \.ghostOpacity, \.hologram, \.melt, \.pixelSort, \.littlePlanet,
        \.depthMap, \.blinds, \.spotlight, \.glow, \.sparkle, \.vhs, \.webcam, \.halftone, \.chroma, \.popAmount,
        \.visionAmount, \.dispersion, \.halation, \.grain, \.skinSmoothing, \.sharpen, \.noiseReduction, \.focusBlur,
        \.eyeBrighten, \.teethWhiten, \.skyReplaceAmount, \.filterStrength,
        // Not here (each has its own mapping where it renders): backgroundBlurAmount, redactionStrength,
        // the Particle Dissolve settings.
    ]

    /// -1...1 strengths (the curve keeps the sign).
    static let signedEffectStrengths: [WritableKeyPath<PhotoAdjustmentState, Double>] = [
        \.texture, \.vignette, \.dehaze,
    ]

    /// This edit with every effect strength on the gentle curve (what actually gets rendered).
    func withEffectResponse() -> PhotoAdjustmentState {
        var copy = self
        for path in Self.effectStrengths {
            let v = min(max(copy[keyPath: path], 0), 1)
            copy[keyPath: path] = v * v
        }
        for path in Self.signedEffectStrengths {
            let v = min(max(copy[keyPath: path], -1), 1)
            copy[keyPath: path] = v * abs(v)
        }
        if var match = copy.lookMatch {
            match.amount = match.amount * match.amount
            copy.lookMatch = match
        }
        return copy
    }
}
