import Observation
import PhotosUI
import SwiftUI

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// Session state for the workspace. Persistent preferences live in @AppStorage (SettingsKey);
/// photo data lives only here, in memory.
///
/// Replacement policy: importing a new photo resets zoom and aspect to the default preferences.
/// Adjustments reset to neutral unless "Keep Adjustments on Replace" is enabled.
@MainActor
@Observable
final class CameraWorkspaceViewModel {
    // MARK: Photo
    private(set) var photo: ImportedPhoto?
    private(set) var renderedPreview: CGImage?
    private(set) var adjustments = PhotoAdjustmentState()
    var showOriginal = false

    // MARK: Import
    private(set) var isImporting = false
    private(set) var importMessage = ""
    private(set) var importSuccessCount = 0

    // MARK: Framing
    private(set) var zoom: CGFloat = 1
    var aspect: AspectRatioOption = .original
    var mode: CameraMode = .photo

    // MARK: Camera-style controls (visual preferences, not hardware)
    var flash: FlashSetting = .off
    var livePreference = false
    /// Preview-only depth look (vignette + f-number readout). Not exported.
    var depthEffect = false
    var timer: TimerSetting = .off
    private(set) var countdown: Int?
    private(set) var flashPulse = 0

    // MARK: Presentation
    var isControlPanelOpen = false
    var isZoomSliderVisible = false
    /// Exposure slider shown inside the control panel.
    var isExposureDialVisible = false
    /// Width / height of the on-screen viewfinder; "Full" framing uses it so the photo fills the screen.
    var viewfinderRatio: CGFloat = 9.0 / 19.5
    var showPhotosPicker = false
    var showFileImporter = false
    var showAdjustments = false
    var showExport = false
    var alert: AppAlert?

    // MARK: Export
    private(set) var isExporting = false
    private(set) var exportedFile: URL?

    private let importer: PhotoImporting
    private let processor: ImageProcessingService
    private let exporter: PhotoExportService
    private let defaults: UserDefaults
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = UUID()

    init(
        importer: PhotoImporting = PhotoImportService(),
        processor: ImageProcessingService = .shared,
        exporter: PhotoExportService = PhotoExportService(),
        defaults: UserDefaults = .standard
    ) {
        self.importer = importer
        self.processor = processor
        self.exporter = exporter
        self.defaults = defaults
        resetFraming()
    }

    // MARK: Derived

    var displayedImage: CGImage? {
        guard let photo else { return nil }
        return showOriginal ? photo.preview : (renderedPreview ?? photo.preview)
    }

    var hasEdits: Bool { !adjustments.isIdentity }

    var previewRatio: CGFloat {
        guard aspect != .original else { return viewfinderRatio }
        return aspect.resolvedRatio(imageSize: photo?.previewSize ?? CGSize(width: 3, height: 4))
    }

    // MARK: Import

    /// The large center control. Honors the timer preference, then opens the picker.
    func primaryAction() {
        guard countdown == nil else { cancelCountdown(); return }
        if flash == .on { flashPulse += 1 }
        guard timer != .off else { showPhotosPicker = true; return }
        let seconds = timer.rawValue
        countdownTask = Task { [weak self] in
            for remaining in stride(from: seconds, to: 0, by: -1) {
                self?.countdown = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            self?.countdown = nil
            self?.showPhotosPicker = true
        }
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = nil
    }

    func importFromLibrary(_ item: PhotosPickerItem) {
        beginImport(message: "Loading from Photos…") { try await $0.loadImage(from: item) }
    }

    func importFromFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            beginImport(message: "Loading file…") { try await $0.loadImage(from: url) }
        case .failure(let error):
            let mapped = PhotoImportError.map(error)
            if mapped != .cancelled {
                alert = AppAlert(title: "File Import Failed", message: mapped.errorDescription ?? "")
            }
        }
    }

    func cancelImport() {
        importTask?.cancel()
        importGeneration = UUID() // any in-flight result is now stale
        isImporting = false
    }

    private func beginImport(
        message: String,
        _ operation: @escaping @Sendable (PhotoImporting) async throws -> ImportedPhoto
    ) {
        importTask?.cancel()
        let generation = UUID()
        importGeneration = generation
        importMessage = message
        isImporting = true
        let importer = self.importer

        importTask = Task { [weak self] in
            do {
                let photo = try await operation(importer)
                guard let self, self.importGeneration == generation else { return } // a newer import won
                self.apply(photo)
            } catch {
                guard let self, self.importGeneration == generation else { return }
                self.isImporting = false
                let mapped = PhotoImportError.map(error)
                if mapped != .cancelled {
                    self.alert = AppAlert(title: "Couldn't Import Photo", message: mapped.errorDescription ?? "")
                }
            }
        }
    }

    private func apply(_ newPhoto: ImportedPhoto) {
        photo = newPhoto // the previous photo is released here
        renderedPreview = nil
        showOriginal = false
        invalidateExport()
        resetFraming()
        if !defaults.bool(forKey: SettingsKey.keepAdjustmentsOnReplace) {
            adjustments = PhotoAdjustmentState()
        }
        isImporting = false
        importSuccessCount += 1
        scheduleRender()
    }

    // MARK: Framing

    func setZoom(_ value: CGFloat) {
        zoom = ZoomLimits.clamp(value)
    }

    func resetFraming() {
        zoom = ZoomLimits.clamp(CGFloat(defaults.object(forKey: SettingsKey.defaultZoom) as? Double ?? 1))
        aspect = AspectRatioOption(rawValue: defaults.string(forKey: SettingsKey.defaultAspect) ?? "") ?? .original
    }

    /// Current viewfinder framing in normalized image coordinates, used by "crop to framing" export.
    var normalizedFraming: CGRect? {
        guard let photo else { return nil }
        return FramingGeometry.normalizedVisibleRect(
            image: photo.previewSize, ratio: previewRatio, zoom: zoom, fill: true)
    }

    // MARK: Adjustments

    func setAdjustment(_ parameter: AdjustmentParameter, to value: Double) {
        adjustments[parameter] = value
        adjustmentsChanged()
    }

    func resetAdjustment(_ parameter: AdjustmentParameter) {
        adjustments.reset(parameter)
        adjustmentsChanged()
    }

    func cycleFilter() {
        adjustments.filter = adjustments.filter.next
        adjustmentsChanged()
    }

    /// True when any camera-style control differs from its default (rings the panel button yellow).
    var hasActiveControls: Bool {
        hasEdits || flash != .off || livePreference || timer != .off || depthEffect || aspect != .original
    }

    func setNightLook(_ enabled: Bool) {
        adjustments.nightLook = enabled
        adjustmentsChanged()
    }

    func resetAllAdjustments() {
        adjustments = PhotoAdjustmentState()
        adjustmentsChanged()
    }

    private func adjustmentsChanged() {
        invalidateExport()
        scheduleRender()
    }

    /// Renders the downsampled preview off the main thread; newer requests cancel older ones,
    /// so dragging a slider never queues up stale renders.
    private func scheduleRender() {
        renderTask?.cancel()
        guard let source = photo?.preview else {
            renderedPreview = nil
            return
        }
        let recipe = adjustments
        guard !recipe.isIdentity else {
            renderedPreview = source
            return
        }
        let processor = self.processor
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(12)) // coalesce rapid slider ticks
            guard !Task.isCancelled else { return }
            let rendered = await Task.detached(priority: .userInitiated) {
                processor.renderPreview(source, adjustments: recipe)
            }.value
            guard !Task.isCancelled, let self, self.photo?.preview === source else { return }
            if let rendered {
                self.renderedPreview = rendered
            } else {
                self.alert = AppAlert(title: "Adjustment Failed", message: "The preview couldn't be rendered with these settings.")
            }
        }
    }

    // MARK: Export

    func prepareExport(options: ExportOptions, overlays: OverlayBurnIn) {
        guard let photo else { return }
        exportTask?.cancel()
        exportedFile = nil
        isExporting = true

        let isEdited = options.content == .adjusted
        let request = ExportRequest(
            data: photo.data,
            typeIdentifier: photo.typeIdentifier,
            adjustments: adjustments,
            options: options,
            normalizedCrop: isEdited && options.cropToFraming ? normalizedFraming : nil,
            overlays: isEdited && options.burnOverlays ? overlays : OverlayBurnIn()
        )
        let exporter = self.exporter
        exportTask = Task { [weak self] in
            do {
                let url = try await exporter.export(request)
                guard !Task.isCancelled else { return }
                self?.exportedFile = url
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? "The photo couldn't be exported."
                self?.alert = AppAlert(title: "Export Failed", message: message)
            }
            self?.isExporting = false
        }
    }

    func invalidateExport() {
        exportTask?.cancel()
        exportTask = nil
        exportedFile = nil
        isExporting = false
    }
}
