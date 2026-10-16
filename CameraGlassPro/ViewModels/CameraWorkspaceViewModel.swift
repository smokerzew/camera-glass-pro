import AVFoundation
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// What the workspace is showing.
enum ImportedMedia {
    case photo(ImportedPhoto)
    case video(ImportedVideo)
}

/// Session state for the workspace. Persistent preferences live in @AppStorage (SettingsKey);
/// photo and video data live only here (videos as an app-owned temporary copy).
///
/// Replacement policy: importing new media resets zoom and aspect to their defaults.
/// Adjustments reset to neutral unless "Keep Adjustments on Replace" is enabled.
@MainActor
@Observable
final class CameraWorkspaceViewModel {
    // MARK: Media
    private(set) var photo: ImportedPhoto?
    private(set) var video: ImportedVideo?
    private(set) var renderedPreview: CGImage?
    private(set) var adjustments = PhotoAdjustmentState()
    private(set) var showOriginal = false

    // MARK: Video playback
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var playbackTime: Double = 0
    /// Still frame laid over the player while the screen is captured (snapshots can't see AVPlayerLayer).
    private(set) var snapshotFrame: CGImage?

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
    private(set) var depthEffect = false
    /// "PORTRAIT" / "PORTRAIT OFF" tag shown briefly after toggling depth, then faded out.
    private(set) var depthTag: String?
    var timer: TimerSetting = .off
    private(set) var countdown: Int?

    // MARK: Persistent controls (saved in UserDefaults)
    private(set) var gridStyle: GridStyle = .thirds
    private(set) var showLevel = false
    private(set) var exportFormat: ExportFormat = .jpeg
    /// Controls pinned to the top bar, in panel order. Changed with the panel's Edit mode.
    private(set) var topBarControls: [CameraControl] = CameraControl.defaultTopBar
    /// Panel Edit mode: tapping a control pins/unpins it instead of running it.
    var isEditingTopBar = false
    private(set) var flashPulse = 0

    // MARK: Presentation
    var isControlPanelOpen = false
    var isZoomSliderVisible = false
    /// Exposure slider shown inside the control panel.
    var isExposureDialVisible = false
    /// Width / height of the on-screen viewfinder; "Full" framing uses it so the media fills the screen.
    var viewfinderRatio: CGFloat = 9.0 / 19.5
    var showPhotosPicker = false
    var showFileImporter = false
    var showAdjustments = false
    var showExport = false
    var alert: AppAlert?
    private(set) var toast: String?

    // MARK: Export
    private(set) var isExporting = false
    private(set) var exportedFile: URL?

    private let importer: PhotoImporting
    private let processor: ImageProcessingService
    private let exporter: PhotoExportService
    private let defaults: UserDefaults
    private let recipe = AdjustmentBox()
    @ObservationIgnored private var importTask: Task<Void, Never>?
    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var depthTagTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = UUID()
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?

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
        gridStyle = GridStyle(rawValue: defaults.string(forKey: SettingsKey.gridStyle) ?? "") ?? .thirds
        showLevel = defaults.bool(forKey: SettingsKey.showLevel)
        exportFormat = ExportFormat(rawValue: defaults.string(forKey: SettingsKey.exportFormat) ?? "") ?? .jpeg
        topBarControls = CameraControl.decode(defaults.string(forKey: SettingsKey.topBarControls))
        resetFraming()
    }

    // MARK: Persistent controls

    func setGridStyle(_ style: GridStyle) {
        gridStyle = style
        defaults.set(style.rawValue, forKey: SettingsKey.gridStyle)
    }

    func setShowLevel(_ show: Bool) {
        showLevel = show
        defaults.set(show, forKey: SettingsKey.showLevel)
    }

    func setExportFormat(_ format: ExportFormat) {
        exportFormat = format
        defaults.set(format.rawValue, forKey: SettingsKey.exportFormat)
        invalidateExport()
    }

    func cycleExportFormat() {
        let all = ExportFormat.allCases
        setExportFormat(all[((all.firstIndex(of: exportFormat) ?? 0) + 1) % all.count])
    }

    func isInTopBar(_ control: CameraControl) -> Bool { topBarControls.contains(control) }

    /// Pins or unpins a control; the bar always keeps panel order.
    func toggleTopBar(_ control: CameraControl) {
        var set = Set(topBarControls)
        if set.contains(control) { set.remove(control) } else { set.insert(control) }
        topBarControls = CameraControl.allCases.filter(set.contains)
        defaults.set(CameraControl.encode(topBarControls), forKey: SettingsKey.topBarControls)
    }

    /// Top bar contents: the pinned controls, plus timer and depth whenever they're on (as iOS does).
    var visibleTopBarControls: [CameraControl] {
        CameraControl.allCases.filter { control in
            isInTopBar(control) || ((control == .timer || control == .depth) && isActive(control))
        }
    }

    // MARK: Derived

    var hasMedia: Bool { photo != nil || video != nil }

    var displayedImage: CGImage? {
        if let video { return video.poster }
        guard let photo else { return nil }
        return showOriginal ? photo.preview : (renderedPreview ?? photo.preview)
    }

    /// Oriented size of whatever is shown, for framing math.
    var mediaSize: CGSize? { photo?.previewSize ?? video?.displaySize }

    var hasEdits: Bool { !adjustments.isIdentity }

    var previewRatio: CGFloat {
        guard aspect != .original else { return viewfinderRatio }
        return aspect.resolvedRatio(imageSize: mediaSize ?? CGSize(width: 3, height: 4))
    }

    /// The center control plays/pauses a loaded video in the video modes; otherwise it imports.
    var centerControlPlaysVideo: Bool { video != nil && mode.usesRecordStyle }

    var timecode: String {
        let total = Int(playbackTime.rounded(.down))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    // MARK: Center control

    /// Plays/pauses a loaded video in the video modes; otherwise honors the timer and opens the picker.
    func primaryAction() {
        if centerControlPlaysVideo { togglePlayback(); return }
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

    // MARK: Import

    func importFromLibrary(_ item: PhotosPickerItem) {
        if item.supportedContentTypes.contains(where: { VideoService.isVideo($0) }) {
            beginImport(message: "Loading video…") { _ in
                guard let file = try await item.loadTransferable(type: PickedVideoFile.self) else {
                    throw PhotoImportError.loadFailed
                }
                return .video(try await VideoService.load(localURL: file.url))
            }
        } else {
            beginImport(message: "Loading from Photos…") { .photo(try await $0.loadImage(from: item)) }
        }
    }

    func importFromFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if VideoService.isVideo(UTType(filenameExtension: url.pathExtension)) {
                beginImport(message: "Loading video…") { _ in
                    let local = try await Task.detached { try VideoService.copyFromFiles(url) }.value
                    return .video(try await VideoService.load(localURL: local))
                }
            } else {
                beginImport(message: "Loading file…") { .photo(try await $0.loadImage(from: url)) }
            }
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
        _ operation: @escaping @Sendable (PhotoImporting) async throws -> ImportedMedia
    ) {
        importTask?.cancel()
        let generation = UUID()
        importGeneration = generation
        importMessage = message
        isImporting = true
        let importer = self.importer

        importTask = Task { [weak self] in
            do {
                let media = try await operation(importer)
                guard let self, self.importGeneration == generation else { // a newer import won
                    if case .video(let stale) = media { try? FileManager.default.removeItem(at: stale.url) }
                    return
                }
                await self.apply(media)
            } catch {
                guard let self, self.importGeneration == generation else { return }
                self.isImporting = false
                let mapped = PhotoImportError.map(error)
                if mapped != .cancelled {
                    self.alert = AppAlert(title: "Couldn't Import", message: mapped.errorDescription ?? "")
                }
            }
        }
    }

    private func apply(_ media: ImportedMedia) async {
        tearDownPlayer()
        if let old = video { try? FileManager.default.removeItem(at: old.url) }
        renderedPreview = nil
        showOriginal = false
        invalidateExport()
        resetFraming()
        if !defaults.bool(forKey: SettingsKey.keepAdjustmentsOnReplace) {
            adjustments = PhotoAdjustmentState()
        }
        recipe.value = adjustments

        switch media {
        case .photo(let newPhoto):
            video = nil
            photo = newPhoto // the previous media is released here
            if mode.usesRecordStyle { mode = .photo }
            scheduleRender()
        case .video(let newVideo):
            photo = nil
            video = newVideo
            mode = .video
            await setUpPlayer(for: newVideo)
        }
        isImporting = false
        importSuccessCount += 1
    }

    // MARK: Video playback

    private func setUpPlayer(for video: ImportedVideo) async {
        let item = AVPlayerItem(asset: video.asset)
        do {
            item.videoComposition = try await VideoService.composition(for: video.asset, recipe: recipe, processor: processor)
        } catch {
            alert = AppAlert(title: "Video Effects Unavailable", message: "The video will play without adjustments.")
        }
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.playbackTime = time.seconds.isFinite ? time.seconds : 0 }
        }
        self.player = player
        playbackTime = 0
        player.play()
        isPlaying = true
    }

    private func tearDownPlayer() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        isPlaying = false
        playbackTime = 0
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying.toggle()
    }

    /// While paused, re-render the current frame so adjustment changes show immediately.
    private func refreshPausedVideoFrame() {
        guard let player, !isPlaying else { return }
        player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Framing

    func setZoom(_ value: CGFloat) {
        zoom = ZoomLimits.clamp(value)
    }

    func resetFraming() {
        zoom = ZoomLimits.clamp(CGFloat(defaults.object(forKey: SettingsKey.defaultZoom) as? Double ?? 1))
        aspect = AspectRatioOption(rawValue: defaults.string(forKey: SettingsKey.defaultAspect) ?? "") ?? .original
    }

    /// Current viewfinder framing in normalized image coordinates, used by "crop to framing" photo export.
    var normalizedFraming: CGRect? {
        guard let photo else { return nil }
        return FramingGeometry.normalizedVisibleRect(
            image: photo.previewSize, ratio: previewRatio, zoom: zoom, fill: true)
    }

    // MARK: Depth

    func setDepth(_ enabled: Bool) {
        depthEffect = enabled
        depthTag = enabled ? "PORTRAIT" : "PORTRAIT OFF"
        depthTagTask?.cancel()
        depthTagTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.depthTag = nil
        }
    }

    // MARK: Adjustments

    /// True when any camera-style control differs from its default (rings the panel button yellow).
    var hasActiveControls: Bool {
        hasEdits || flash != .off || livePreference || timer != .off || depthEffect || aspect != .original || showLevel
    }

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

    func setNightLook(_ enabled: Bool) {
        adjustments.nightLook = enabled
        adjustmentsChanged()
    }

    func resetAllAdjustments() {
        adjustments = PhotoAdjustmentState()
        adjustmentsChanged()
    }

    /// Hold-to-compare: shows the unedited photo or video while held.
    func setShowOriginal(_ value: Bool) {
        showOriginal = value
        recipe.value = value ? PhotoAdjustmentState() : adjustments
        refreshPausedVideoFrame()
    }

    private func adjustmentsChanged() {
        invalidateExport()
        recipe.value = showOriginal ? PhotoAdjustmentState() : adjustments
        refreshPausedVideoFrame()
        scheduleRender()
    }

    /// Renders the downsampled photo preview off the main thread; newer requests cancel older ones,
    /// so dragging a slider never queues up stale renders. (Videos render live in the compositor.)
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
        guard hasMedia else { return }
        exportTask?.cancel()
        exportedFile = nil
        isExporting = true

        let exporter = self.exporter
        let processor = self.processor
        let adjustments = self.adjustments
        let isEdited = options.content == .adjusted
        let work: @Sendable () async throws -> URL

        if let video {
            work = {
                try exporter.prepareDirectory()
                if isEdited {
                    let url = exporter.directory.appendingPathComponent(
                        PhotoExportService.fileName(content: .adjusted, fileExtension: "mov"))
                    try await VideoService.exportEdited(video, adjustments: adjustments, processor: processor, to: url)
                    return url
                }
                let url = exporter.directory.appendingPathComponent(
                    PhotoExportService.fileName(content: .original, fileExtension: video.url.pathExtension))
                try FileManager.default.copyItem(at: video.url, to: url)
                return url
            }
        } else if let photo {
            let request = ExportRequest(
                data: photo.data,
                typeIdentifier: photo.typeIdentifier,
                adjustments: adjustments,
                options: options,
                normalizedCrop: isEdited && options.cropToFraming ? normalizedFraming : nil,
                overlays: isEdited && options.burnOverlays ? overlays : OverlayBurnIn()
            )
            work = { try await exporter.export(request) }
        } else {
            return
        }

        exportTask = Task { [weak self] in
            do {
                let url = try await work()
                guard !Task.isCancelled else { return }
                self?.exportedFile = url
            } catch {
                guard !Task.isCancelled else { return }
                let message = (error as? LocalizedError)?.errorDescription ?? "The file couldn't be exported."
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

    // MARK: Save Screen with UI

    /// Closes sheets and the panel, captures the screen with the camera controls, saves it to Photos.
    func saveScreenWithUI() {
        showExport = false
        showAdjustments = false
        isControlPanelOpen = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700)) // let sheets finish dismissing
            guard let self else { return }
            if let video = self.video, let player = self.player {
                // Player layers are invisible to window snapshots, so lay the current frame on top.
                self.snapshotFrame = try? await VideoService.frame(
                    of: video.asset, at: player.currentTime(), composition: player.currentItem?.videoComposition)
                try? await Task.sleep(for: .milliseconds(120))
            }
            do {
                let image = try ScreenCapture.captureKeyWindow()
                self.snapshotFrame = nil
                try await ScreenCapture.saveToPhotos(image)
                self.showToast("Saved to Photos")
            } catch {
                self.snapshotFrame = nil
                let message = (error as? LocalizedError)?.errorDescription ?? "The screen couldn't be saved."
                self.alert = AppAlert(title: "Couldn't Save Screen", message: message)
            }
        }
    }

    private func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
