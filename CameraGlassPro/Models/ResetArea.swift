import Foundation

/// The part of the edit a Reset button clears. Each one leaves everything else (filters, FX, crop...) alone.
enum ResetArea: String, CaseIterable, Sendable {
    /// Adjust sheet tabs, and all of them together.
    case light, color, detail, effects, local, adjust
    /// Filter pop-up: filter, strength and grain.
    case filter
    /// FX pages.
    case fxBlur, fxBlend, fxPrivacy
    /// SUBJECT pages (the Adjust page has its own reset for subject / background / sky edits).
    case subjectStyle, subjectCreate

    var title: String {
        switch self {
        case .light: "Reset Light"
        case .color: "Reset Color"
        case .detail: "Reset Detail"
        case .effects: "Reset Effects"
        case .local: "Reset Filters"
        case .adjust: "Reset Adjust"
        case .filter: "Reset Filter"
        case .fxBlur, .fxBlend, .fxPrivacy, .subjectStyle, .subjectCreate: "Reset"
        }
    }

    /// The Adjust sheet tab this area belongs to, if any.
    init?(_ group: AdjustGroup) {
        switch group {
        case .light: self = .light
        case .color: self = .color
        case .detail: self = .detail
        case .effects: self = .effects
        case .local: self = .local
        case .ai: return nil
        }
    }
}

extension PhotoAdjustmentState {
    /// This edit with only `area` put back to its defaults.
    func resetting(_ area: ResetArea) -> PhotoAdjustmentState {
        let d = PhotoAdjustmentState()
        var next = self
        func sliders(_ group: AdjustGroup) {
            for parameter in AdjustmentParameter.allCases where parameter.group == group {
                next[parameter] = parameter.defaultValue
            }
        }
        switch area {
        case .light:
            sliders(.light)
            next.nightLook = d.nightLook
        case .color:
            sliders(.color)
            next.colorMixer = d.colorMixer
        case .detail:
            sliders(.detail)
        case .effects:
            sliders(.effects)
            next.grainSize = d.grainSize
        case .local:
            next.localAdjustments = d.localAdjustments
        case .adjust:
            for part in [ResetArea.light, .color, .detail, .effects, .local] { next = next.resetting(part) }
        case .filter:
            next.filter = d.filter
            next.filterStrength = d.filterStrength
            next.grain = d.grain
            next.grainSize = d.grainSize
        case .fxBlur:
            next.speedBlur = d.speedBlur
            next.speedAngle = d.speedAngle
            next.tiltShift = d.tiltShift
            next.tiltShiftPosition = d.tiltShiftPosition
        case .fxBlend:
            next.doubleExposure = d.doubleExposure
        case .fxPrivacy:
            next.faceRedaction = d.faceRedaction
            next.redactionTarget = d.redactionTarget
            next.redactionStrokes = d.redactionStrokes
            next.redactionStrength = d.redactionStrength
        case .subjectStyle:
            next.colorSplash = d.colorSplash
            next.background = d.background
        case .subjectCreate:
            next.dispersion = d.dispersion
            next.dispersionSize = d.dispersionSize
            next.dispersionAngle = d.dispersionAngle
        }
        return next
    }

    func canReset(_ area: ResetArea) -> Bool { resetting(area) != self }
}
