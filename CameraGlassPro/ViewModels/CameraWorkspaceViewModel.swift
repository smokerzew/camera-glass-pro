import AVFoundation
import Observation
import QuartzCore
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct AppAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// One item picked in a multi-selection; loaded when it's shown.
struct LibraryEntry: Identifiable {
    enum Source {
        case library(PhotosPickerItem)
        case file(URL)
    }

    let id = UUID()
    let source: Source
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
    /// AI edit: true while the on-device model works; the last result or problem to show.
    private(set) var isAskingAI = false
    private(set) var aiMessage: String?
    /// The edit just before and right after the last AI edit (same photo), to show and undo what it moved.
    private(set) var aiBefore: PhotoAdjustmentState?
    private(set) var aiAfter: PhotoAdjustmentState?
    @ObservationIgnored private var aiMediaID: UUID?

    // MARK: Video playback
    private(set) var player: AVPlayer?
    private(set) var isPlaying = false
    private(set) var playbackTime: Double = 0
    /// Still frame laid over the player while the screen is captured (snapshots can't see AVPlayerLayer).
    private(set) var snapshotFrame: CGImage?
    /// True while "Save Video with UI" is recording the screen.
    private(set) var isRecordingUI = false
    /// Trim range of the loaded video, in seconds.
    private(set) var trimStart: Double = 0
    private(set) var trimEnd: Double = 0
    var showTrim = false

    // MARK: Pro tools (display only)
    private(set) var scopeMode: ScopeMode = .off
    private(set) var scopeData: ScopeData?
    private(set) var focusPeaking = false
    /// Highlight clipping stripes.
    private(set) var zebras = false
    /// Peaking/zebra overlay for photos (videos get it inside the live compositor).
    private(set) var overlayImage: CGImage?

    // MARK: Tap to focus / expose
    /// Where the yellow focus box sits, in viewfinder points (nil = hidden).
    private(set) var focusPoint: CGPoint?
    private(set) var focusPulse = 0
    private(set) var isAELocked = false
    private(set) var isFocusDimmed = false

    // MARK: Photographic Styles pad
    var showStylesPad = false

    // MARK: Crop editor
    var showCropEditor = false

    // MARK: Subject (Color Splash, Background Swap)
    var showSubjectPicker = false
    var showBackgroundPhotoPicker = false
    /// Photo chosen for Background Swap (preview resolution; used for preview, video and export).
    private(set) var customBackground: CGImage?

    // MARK: Live Photos and effects
    /// True while the Live Photo motion plays (touch and hold the LIVE badge).
    var isPlayingLive = false
    var showEffectsPicker = false
    /// FX pop-up (speed blur, tilt-shift, double exposure, blur/pixelate, shuffle) and the brush editor.
    var showFXPicker = false
    var showRedactionEditor = false
    /// Whether Live Photos made from videos keep the video's sound (saved preference).
    private(set) var livePhotoSound = true
    private(set) var isRenderingEffect = false
    private(set) var effectMessage = ""

    // MARK: Filter picker
    var showFilterPicker = false
    /// Small previews of every filter on the current photo/video (rendered when the picker opens).
    private(set) var filterThumbnails: [PhotoFilter: CGImage] = [:]

    // MARK: Live Text
    private(set) var liveTextEnabled = false
    private(set) var recognizedText: [RecognizedText] = []
    private(set) var isRecognizingText = false
    var showTextSheet = false

    // MARK: Undo / presets
    private(set) var canUndo = false
    private(set) var canRedo = false
    private(set) var presets: [StylePreset] = []

    // MARK: Library (multi-select) and session restore
    private(set) var library: [LibraryEntry] = []
    private(set) var libraryIndex = 0

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
    /// Real Portrait on (subject sharp, background blurred); part of the edit, so it exports.
    var depthEffect: Bool { adjustments.portrait }
    /// Aperture slider / lighting picker visibility.
    var isApertureDialVisible = false
    var isLightingPickerVisible = false
    /// True while Vision looks for the subject of a photo.
    private(set) var isFindingSubject = false
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
    /// Curved zoom dial (shown by swiping the zoom row or tapping the active zoom value).
    private(set) var isZoomDialVisible = false
    /// Drag position of zoomed media, -1...1 per axis (see `FramingGeometry.visibleRect`).
    private(set) var pan: CGPoint = .zero
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
    /// Set when the edit changed since the last preview render started.
    @ObservationIgnored private var renderNeeded = false
    /// The next picked second photo is for Double Exposure rather than Background Swap.
    @ObservationIgnored private var pendingDoubleExposure = false
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var depthTagTask: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var importGeneration = UUID()
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var videoOutput: AVPlayerItemVideoOutput?
    @ObservationIgnored private var scopeTask: Task<Void, Never>?
    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private var stopRecordingRequested = false
    @ObservationIgnored private var dialHideTask: Task<Void, Never>?
    @ObservationIgnored private var undoStack: [PhotoAdjustmentState] = []
    @ObservationIgnored private var redoStack: [PhotoAdjustmentState] = []
    @ObservationIgnored private var lastUndoPoint = Date.distantPast
    @ObservationIgnored private var entryEdits: [UUID: PhotoAdjustmentState] = [:]
    @ObservationIgnored private var textTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnailTask: Task<Void, Never>?
    @ObservationIgnored private var focusTask: Task<Void, Never>?
    @ObservationIgnored private var effectTask: Task<Void, Never>?
    /// Portrait subject mask for the current photo preview (computed once per photo).
    @ObservationIgnored private var previewSubjectMask: CIImage?
    @ObservationIgnored private var previewSubjectSource: CGImage?
    @ObservationIgnored private var exposureDragStart: Double?
    @ObservationIgnored private var restoringState: SessionState?
    private let sessionStore: SessionStore?

    init(
        importer: PhotoImporting = PhotoImportService(),
        processor: ImageProcessingService = .shared,
        exporter: PhotoExportService = PhotoExportService(),
        defaults: UserDefaults = .standard,
        sessionStore: SessionStore? = nil
    ) {
        self.sessionStore = sessionStore
        self.importer = importer
        self.processor = processor
        self.exporter = exporter
        self.defaults = defaults
        gridStyle = GridStyle(rawValue: defaults.string(forKey: SettingsKey.gridStyle) ?? "") ?? .thirds
        showLevel = defaults.bool(forKey: SettingsKey.showLevel)
        exportFormat = ExportFormat(rawValue: defaults.string(forKey: SettingsKey.exportFormat) ?? "") ?? .jpeg
        topBarControls = CameraControl.decode(defaults.string(forKey: SettingsKey.topBarControls))
        presets = StylePreset.load(from: defaults)
        livePhotoSound = defaults.object(forKey: SettingsKey.livePhotoSound) as? Bool ?? true
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
    var mediaSize: CGSize? {
        if photo != nil, let image = displayedImage { return CGSize(width: image.width, height: image.height) }
        return photo?.previewSize ?? video?.displaySize
    }

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
        if isRecordingUI { stopRecordingRequested = true; return }
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

    /// Picks up to 20 items; each keeps its own edits while you swipe between them.
    func importFromLibrary(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        startLibrary(items.map { LibraryEntry(source: .library($0)) })
    }

    func importFromFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            startLibrary(urls.map { LibraryEntry(source: .file($0)) })
        case .failure(let error):
            let mapped = PhotoImportError.map(error)
            if mapped != .cancelled {
                alert = AppAlert(title: "File Import Failed", message: mapped.errorDescription ?? "")
            }
        }
    }

    private func startLibrary(_ entries: [LibraryEntry]) {
        restoringState = nil // a new import replaces any restore in progress
        library = entries
        entryEdits = [:]
        libraryIndex = 0
        load(entries[0])
    }

    var currentEntryID: UUID? { library.indices.contains(libraryIndex) ? library[libraryIndex].id : nil }
    var hasNext: Bool { libraryIndex + 1 < library.count }
    var hasPrevious: Bool { libraryIndex > 0 && !library.isEmpty }

    func showNext() { showEntry(at: libraryIndex + 1) }
    func showPrevious() { showEntry(at: libraryIndex - 1) }

    func showEntry(at index: Int) {
        guard library.indices.contains(index), index != libraryIndex else { return }
        if let current = currentEntryID { entryEdits[current] = adjustments }
        libraryIndex = index
        load(library[index])
    }

    private func load(_ entry: LibraryEntry) {
        switch entry.source {
        case .library(let item): importFromLibrary(item)
        case .file(let url): importFile(url)
        }
    }

    private func importFromLibrary(_ item: PhotosPickerItem) {
        if item.supportedContentTypes.contains(where: { VideoService.isVideo($0) }) {
            beginImport(message: "Loading video…") { _ in
                guard let file = try await item.loadTransferable(type: PickedVideoFile.self) else {
                    throw PhotoImportError.loadFailed
                }
                return .video(try await VideoService.load(localURL: file.url))
            }
        } else if LivePhotoSupport.isLivePhoto(item) {
            beginImport(message: "Loading Live Photo…") { importer in
                var photo = try await importer.loadImage(from: item)
                if let live = try? await item.loadTransferable(type: PHLivePhoto.self) {
                    photo.livePhoto = live
                    photo.pairedVideoURL = try? await LivePhotoSupport.extractPairedVideo(from: live)
                }
                return .photo(photo)
            }
        } else {
            beginImport(message: "Loading from Photos…") { .photo(try await $0.loadImage(from: item)) }
        }
    }

    private func importFile(_ url: URL) {
        if VideoService.isVideo(UTType(filenameExtension: url.pathExtension)) {
            beginImport(message: "Loading video…") { _ in
                let local = try await Task.detached { try VideoService.copyFromFiles(url) }.value
                return .video(try await VideoService.load(localURL: local))
            }
        } else {
            beginImport(message: "Loading file…") { .photo(try await $0.loadImage(from: url)) }
        }
    }

    // MARK: Session restore

    /// Reopens the last photo or video with its edits, framing, mode and trim (called once at launch).
    func restoreLastSession() {
        guard !hasMedia, !isImporting, let store = sessionStore, let state = store.loadState() else { return }
        startLibrary([LibraryEntry(source: .file(store.mediaURL(for: state)))])
        restoringState = state // set after startLibrary, which clears it
    }

    /// Saves the current edits and framing (called when the app goes to the background).
    func saveSessionState() {
        guard let store = sessionStore, hasMedia, restoringState == nil else { return }
        try? store.saveState(currentSessionState(fileName: sessionFileName))
    }

    @ObservationIgnored private var sessionFileName = ""

    private func currentSessionState(fileName: String) -> SessionState {
        SessionState(
            kind: video != nil ? .video : .photo,
            fileName: fileName,
            adjustments: adjustments,
            mode: mode.rawValue,
            zoom: Double(zoom),
            aspect: aspect.rawValue,
            panX: Double(pan.x),
            panY: Double(pan.y),
            trimStart: trimStart,
            trimEnd: trimEnd
        )
    }

    /// Copies the new media into the session store in the background, then writes its state.
    private func persistSessionMedia(_ media: ImportedMedia) {
        guard let store = sessionStore else { return }
        let photoData: Data?
        let videoURL: URL?
        let fileName: String
        switch media {
        case .photo(let photo):
            photoData = photo.data
            videoURL = nil
            let ext = photo.typeIdentifier.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"
            fileName = "media." + ext
        case .video(let video):
            photoData = nil
            videoURL = video.url
            fileName = "media." + (video.url.pathExtension.isEmpty ? "mov" : video.url.pathExtension)
        }
        sessionFileName = fileName
        let state = currentSessionState(fileName: fileName)
        Task.detached(priority: .utility) {
            try? store.saveMedia(photoData: photoData, videoURL: videoURL, fileName: fileName)
            try? store.saveState(state)
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
                self.restoringState = nil
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
        clearFocus()
        let restoring = restoringState
        if let restoring {
            adjustments = restoring.adjustments.clamped()
        } else if let id = currentEntryID, let saved = entryEdits[id] {
            adjustments = saved
        } else if !defaults.bool(forKey: SettingsKey.keepAdjustmentsOnReplace) {
            adjustments = PhotoAdjustmentState()
        }
        clearUndoHistory()
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

        if let restoring {
            mode = CameraMode(rawValue: restoring.mode) ?? mode
            setZoom(CGFloat(restoring.zoom))
            aspect = AspectRatioOption(rawValue: restoring.aspect) ?? .original
            setPan(CGPoint(x: restoring.panX, y: restoring.panY))
            if video != nil, restoring.trimEnd > restoring.trimStart {
                setTrim(start: restoring.trimStart, end: restoring.trimEnd)
            }
            sessionFileName = restoring.fileName
            restoringState = nil
            modeChanged()
        } else {
            persistSessionMedia(media)
        }
        isImporting = false
        importSuccessCount += 1
        recognizedText = []
        if liveTextEnabled { recognizeText() }
        isPlayingLive = false
        autoPlayLivePhoto()
    }

    // MARK: Video playback

    private func setUpPlayer(for video: ImportedVideo) async {
        let item = AVPlayerItem(asset: video.asset)
        do {
            item.videoComposition = try await VideoService.composition(for: video.asset, recipe: recipe, processor: processor)
        } catch {
            alert = AppAlert(title: "Video Effects Unavailable", message: "The video will play without adjustments.")
        }
        // Taps composed frames (after adjustments) for the exposure scopes.
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        videoOutput = output
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.loopToTrimStart() }
        }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 4), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.playbackTime = time.seconds.isFinite ? time.seconds : 0 }
        }
        self.player = player
        playbackTime = 0
        trimStart = 0
        trimEnd = video.duration
        player.playImmediately(atRate: playbackRate)
        isPlaying = true
        updateVideoScopeSampling()
    }

    private func tearDownPlayer() {
        scopeTask?.cancel()
        scopeTask = nil
        videoOutput = nil
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
        if isPlaying { player.pause() } else { player.playImmediately(atRate: playbackRate) }
        isPlaying.toggle()
        if liveTextEnabled {
            // Boxes only make sense on a still frame: clear while playing, re-scan when paused.
            if isPlaying { recognizedText = [] } else { recognizeText() }
        }
    }

    // MARK: Live Text

    func setLiveText(_ enabled: Bool) {
        liveTextEnabled = enabled
        if enabled { recognizeText() } else { textTask?.cancel(); recognizedText = [] }
    }

    /// Finds text in the photo, or in the current video frame (pausing the video).
    func recognizeText() {
        textTask?.cancel()
        guard liveTextEnabled, hasMedia else { recognizedText = []; return }
        isRecognizingText = true
        let photoImage = photo != nil ? displayedImage : nil
        let video = self.video
        let player = self.player
        if video != nil, isPlaying {
            player?.pause()
            isPlaying = false
        }
        textTask = Task { [weak self] in
            var image = photoImage
            if image == nil, let video, let player {
                image = try? await VideoService.frame(
                    of: video.asset, at: player.currentTime(), composition: player.currentItem?.videoComposition)
            }
            guard let image else {
                self?.isRecognizingText = false
                return
            }
            let found = await Task.detached(priority: .userInitiated) {
                (try? LiveTextService.recognize(in: image)) ?? []
            }.value
            guard !Task.isCancelled, let self else { return }
            self.recognizedText = found
            self.isRecognizingText = false
            if found.isEmpty { self.showToast("No text found") }
        }
    }

    func copyText(_ line: RecognizedText) {
        UIPasteboard.general.string = line.text
        showToast("Copied")
    }

    /// 1× normally; ¼× in SLO-MO and 8× in TIME-LAPSE.
    var playbackRate: Float { mode.playbackRate }

    /// Re-applies the speed when the mode changes during playback.
    func modeChanged() {
        if mode == .portrait, hasMedia, !adjustments.portrait { setDepth(true) }
        guard let player, isPlaying else { return }
        player.rate = playbackRate
    }

    // MARK: Trim

    var videoDuration: Double { video?.duration ?? 0 }
    var isTrimmed: Bool { video != nil && (trimStart > 0.05 || trimEnd < videoDuration - 0.05) }

    var trimRange: CMTimeRange? {
        guard isTrimmed else { return nil }
        return CMTimeRange(start: CMTime(seconds: trimStart, preferredTimescale: 600),
                           end: CMTime(seconds: trimEnd, preferredTimescale: 600))
    }

    /// Sets the trim; keeps at least half a second and stays inside the video.
    func setTrim(start: Double, end: Double) {
        let duration = videoDuration
        guard duration > 0 else { return }
        let minimumLength = min(0.5, duration)
        let newEnd = min(max(end, minimumLength), duration)
        let newStart = min(max(start, 0), newEnd - minimumLength)
        trimStart = newStart
        trimEnd = newEnd
        player?.currentItem?.forwardPlaybackEndTime = newEnd < duration - 0.05
            ? CMTime(seconds: newEnd, preferredTimescale: 600) : .invalid
        invalidateExport()
    }

    func resetTrim() { setTrim(start: 0, end: videoDuration) }

    /// Shows the frame at `seconds` while a trim handle is dragged.
    func scrub(to seconds: Double) {
        guard let player else { return }
        if isPlaying { player.pause(); isPlaying = false }
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func loopToTrimStart() {
        guard let player else { return }
        player.seek(to: CMTime(seconds: trimStart, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying { player.rate = playbackRate }
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

    func setPan(_ value: CGPoint) {
        pan = FramingGeometry.clampPan(value)
    }

    /// Shows the zoom dial and hides it again 2 s after the last interaction.
    func showZoomDial() {
        isZoomDialVisible = true
        dialHideTask?.cancel()
        dialHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.isZoomDialVisible = false
        }
    }

    func resetFraming() {
        pan = .zero
        zoom = ZoomLimits.clamp(CGFloat(defaults.object(forKey: SettingsKey.defaultZoom) as? Double ?? 1))
        aspect = AspectRatioOption(rawValue: defaults.string(forKey: SettingsKey.defaultAspect) ?? "") ?? .original
    }

    /// Current viewfinder framing in normalized image coordinates, used by "crop to framing" photo export.
    var normalizedFraming: CGRect? {
        guard photo != nil, let mediaSize else { return nil }
        return FramingGeometry.normalizedVisibleRect(
            image: mediaSize, ratio: previewRatio, zoom: zoom, fill: true, pan: pan)
    }

    // MARK: Depth

    func setDepth(_ enabled: Bool) {
        if adjustments.portrait != enabled {
            recordUndoPoint(force: true)
            adjustments.portrait = enabled
            adjustmentsChanged()
        }
        if !enabled { isApertureDialVisible = false; isLightingPickerVisible = false }
        depthTag = enabled ? "PORTRAIT" : "PORTRAIT OFF"
        depthTagTask?.cancel()
        depthTagTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.depthTag = nil
        }
    }

    // MARK: Portrait aperture and lighting

    func setAperture(_ value: Double) {
        recordUndoPoint()
        adjustments.aperture = min(max(value, 1.4), 16)
        adjustmentsChanged()
    }

    func setLighting(_ lighting: PortraitLighting) {
        guard lighting != adjustments.lighting else { return }
        recordUndoPoint(force: true)
        adjustments.lighting = lighting
        adjustmentsChanged()
        showLightingTag()
    }

    /// Flashes the lighting name (e.g. STUDIO LIGHT) like the Camera app.
    private func showLightingTag() {
        depthTag = adjustments.lighting.label
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
            || scopeMode != .off || focusPeaking || zebras || liveTextEnabled
    }

    func setAdjustment(_ parameter: AdjustmentParameter, to value: Double) {
        recordUndoPoint()
        adjustments[parameter] = value
        adjustmentsChanged()
    }

    func resetAdjustment(_ parameter: AdjustmentParameter) {
        recordUndoPoint(force: true)
        adjustments.reset(parameter)
        adjustmentsChanged()
    }

    // MARK: Tap to focus / expose

    /// Tap: moves the focus box and meters exposure for the tapped area. Long press (`lock`) adds
    /// AE/AF LOCK, which keeps the box and exposure until you tap somewhere else.
    func focus(atView point: CGPoint, mediaPoint: CGPoint?, lock: Bool) {
        if isAELocked && !lock { isAELocked = false }
        focusPoint = point
        focusPulse += 1
        isFocusDimmed = false
        if lock { isAELocked = true }
        if let mediaPoint { meterExposure(at: mediaPoint) }
        scheduleFocusDim()
    }

    func clearFocus() {
        focusTask?.cancel()
        focusPoint = nil
        isAELocked = false
        isFocusDimmed = false
    }

    /// Drag up/down while the box is showing to slide the ☀︎ exposure (one undo step per drag).
    func beginExposureDrag() {
        focusTask?.cancel()
        isFocusDimmed = false
        exposureDragStart = adjustments.exposure
        recordUndoPoint(force: true)
    }

    func updateExposureDrag(by verticalTranslation: CGFloat) {
        guard let start = exposureDragStart else { return }
        adjustments[.exposure] = start - Double(verticalTranslation) / 120
        adjustmentsChanged()
    }

    func endExposureDrag() {
        exposureDragStart = nil
        scheduleFocusDim()
    }

    var isDraggingExposure: Bool { exposureDragStart != nil }

    /// Box goes dim after 2 s and away after 6 s (stays while AE/AF locked).
    private func scheduleFocusDim() {
        focusTask?.cancel()
        focusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.isFocusDimmed = true
            guard !self.isAELocked else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self.focusPoint = nil
        }
    }

    /// EV that brings an area of the given sRGB luminance (0...1) to mid-gray, damped like auto-exposure.
    nonisolated static func meteredExposure(regionLuma: Double) -> Double {
        let linear = max(0.002, pow(min(max(regionLuma, 0), 1), 2.2))
        return min(max(log2(0.18 / linear) * 0.8, -2), 2)
    }

    private func meterExposure(at mediaPoint: CGPoint) {
        let photoImage = photo != nil ? displayedImage : nil
        let video = self.video
        let time = player?.currentTime() ?? .zero
        let processor = self.processor
        Task { [weak self] in
            var source = photoImage
            if source == nil, let video {
                source = try? await VideoService.frame(of: video.asset, at: time, composition: nil)
            }
            guard let source else { return }
            let luma = await Task.detached(priority: .userInitiated) {
                processor.averageLuma(of: source, around: mediaPoint, radius: 0.08)
            }.value
            guard let self, let luma else { return }
            self.recordUndoPoint(force: true)
            self.adjustments[.exposure] = Self.meteredExposure(regionLuma: luma)
            self.adjustmentsChanged()
        }
    }

    // MARK: Photographic Styles

    func openStylesPad() {
        showCropEditor = false
        showSubjectPicker = false
        isControlPanelOpen = false
        showFilterPicker = false
        showEffectsPicker = false
        showFXPicker = false
        showStylesPad = true
    }

    func setStyle(_ style: PhotographicStyle) {
        guard style != adjustments.style else { return }
        recordUndoPoint(force: true)
        adjustments.style = style
        adjustmentsChanged()
    }

    /// Pad position: `tone` up/down, `color` left/right, both -1...1.
    func setStylePad(tone: Double, color: Double) {
        recordUndoPoint()
        adjustments.styleTone = min(max(tone, -1), 1)
        adjustments.styleColor = min(max(color, -1), 1)
        adjustmentsChanged()
    }

    func setStylePalette(_ value: Double) {
        recordUndoPoint()
        adjustments.stylePalette = min(max(value, 0), 1)
        adjustmentsChanged()
    }

    func resetStylePad() {
        recordUndoPoint(force: true)
        adjustments.styleTone = 0
        adjustments.styleColor = 0
        adjustments.stylePalette = 1
        adjustmentsChanged()
    }

    // MARK: Live Photos and effects

    /// Motion source for Loop, Bounce, Long Exposure and Live Photo: the video, or a Live Photo's clip.
    var effectSourceAsset: AVAsset? {
        if let video { return video.asset }
        return photo?.pairedVideoURL.map { AVURLAsset(url: $0) }
    }

    var canMakeEffects: Bool { effectSourceAsset != nil }

    func openEffectsPicker() {
        showCropEditor = false
        showSubjectPicker = false
        isControlPanelOpen = false
        showFilterPicker = false
        showStylesPad = false
        showEffectsPicker = true
    }

    /// Plays a Live Photo's motion once (used when LIVE is on and a Live Photo opens).
    private func autoPlayLivePhoto() {
        guard livePreference, photo?.livePhoto != nil else { return }
        isPlayingLive = true
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.isPlayingLive = false
        }
    }

    func runEffect(_ effect: LiveEffect) {
        guard let asset = effectSourceAsset else { return }
        showEffectsPicker = false
        showFXPicker = false
        effectTask?.cancel()
        isRenderingEffect = true
        effectMessage = effect == .livePhoto ? "Making Live Photo…" : "Creating \(effect.title.capitalized)…"

        let processor = self.processor
        let recipe = adjustments
        let isVideo = video != nil
        let range = trimRange
        let keySeconds = player?.currentTime().seconds ?? 0
        let withSound = livePhotoSound
        effectTask = Task { [weak self] in
            do {
                let duration = try await asset.load(.duration)
                let full = CMTimeRange(start: .zero, duration: duration)
                let available = isVideo ? (range ?? full) : full
                switch effect {
                case .loop, .bounce:
                    let url = try LiveEffectsService.newURL("mov")
                    try await LiveEffectsService.renderMovie(
                        from: asset, times: LiveEffectsService.sequence(for: effect, in: available),
                        adjustments: recipe, processor: processor, to: url)
                    try Task.checkCancellation()
                    self?.showEffectResult(url, toast: "\(effect.title.capitalized) created")
                case .longExposure:
                    let data = try await LiveEffectsService.longExposure(
                        from: asset, range: available, adjustments: recipe, processor: processor)
                    try Task.checkCancellation()
                    let url = try LiveEffectsService.newURL("jpg")
                    try data.write(to: url)
                    self?.showEffectResult(url, toast: "Long Exposure created")
                case .livePhoto:
                    // The whole video (or the trimmed part) becomes the motion; the frame on screen is the photo.
                    let key = CMTime(seconds: min(max(keySeconds, available.start.seconds), available.end.seconds - 0.05),
                                     preferredTimescale: 600)
                    let pair = try await LiveEffectsService.makeLivePhoto(
                        from: asset, range: available, keyTime: key, adjustments: recipe, processor: processor,
                        includeAudio: withSound)
                    try Task.checkCancellation()
                    try await LiveEffectsService.saveLivePhotoToLibrary(photo: pair.photo, video: pair.video)
                    self?.showToast("Live Photo saved to Photos")
                }
            } catch is CancellationError {
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "The effect couldn't be created."
                self?.alert = AppAlert(title: "Couldn't Create Effect", message: message)
            }
            self?.isRenderingEffect = false
        }
    }

    func setLivePhotoSound(_ enabled: Bool) {
        livePhotoSound = enabled
        defaults.set(enabled, forKey: SettingsKey.livePhotoSound)
    }

    func cancelEffect() {
        effectTask?.cancel()
        isRenderingEffect = false
    }

    /// Adds an effect's output as a new item after the current one and shows it (the original stays).
    private func showEffectResult(_ url: URL, toast message: String) {
        if let current = currentEntryID { entryEdits[current] = adjustments }
        let entry = LibraryEntry(source: .file(url))
        let index = min(libraryIndex + 1, library.count)
        library.insert(entry, at: index)
        entryEdits[entry.id] = PhotoAdjustmentState() // the effect already includes the edits
        libraryIndex = index
        load(entry)
        showToast(message)
    }

    // MARK: Crop, rotate, flip, straighten

    func openCropEditor() {
        guard photo != nil else { return }
        isControlPanelOpen = false
        showFilterPicker = false
        showStylesPad = false
        showEffectsPicker = false
        showFXPicker = false
        showSubjectPicker = false
        showCropEditor = true
    }

    /// Commits the crop editor's result as one undoable edit.
    func setGeometry(crop: CGRect, rotation: Int, flipped: Bool, straighten: Double,
                     perspectiveVertical: Double = 0, perspectiveHorizontal: Double = 0) {
        var next = adjustments
        next.cropRect = crop
        next.rotation = ((rotation % 4) + 4) % 4
        next.flipped = flipped
        next.straighten = min(max(straighten, -45), 45)
        next.perspectiveVertical = min(max(perspectiveVertical, -1), 1)
        next.perspectiveHorizontal = min(max(perspectiveHorizontal, -1), 1)
        guard next != adjustments else { return }
        recordUndoPoint(force: true)
        adjustments = next
        setPan(.zero)
        adjustmentsChanged()
    }

    /// The photo with the current look and the given rotation/flip/straighten, uncropped (for the editor).
    func geometryPreview(rotation: Int, flipped: Bool, straighten: Double,
                         perspectiveVertical: Double = 0, perspectiveHorizontal: Double = 0) async -> CGImage? {
        guard let source = photo?.preview else { return nil }
        var recipe = adjustments
        recipe.cropRect = PhotoAdjustmentState.fullCrop
        recipe.rotation = rotation
        recipe.flipped = flipped
        recipe.straighten = straighten
        recipe.perspectiveVertical = perspectiveVertical
        recipe.perspectiveHorizontal = perspectiveHorizontal
        recipe.grain = 0
        let mask = previewSubjectSource === source ? previewSubjectMask : nil
        let background = customBackground.map { CIImage(cgImage: $0) }
        let processor = self.processor
        return await Task.detached(priority: .userInitiated) {
            processor.renderPreview(source, adjustments: recipe, subjectMask: mask, backgroundPhoto: background)
        }.value
    }

    /// Vision's horizon angle for the photo, as a straighten value (nil if no horizon is found).
    func autoStraightenValue() async -> Double? {
        guard let source = photo?.preview else { return nil }
        return await Task.detached(priority: .userInitiated) {
            ImageProcessingService.horizonStraighten(for: source)
        }.value
    }

    // MARK: Subject: Color Splash and Background Swap

    func openSubjectPicker() {
        showCropEditor = false
        isControlPanelOpen = false
        showFilterPicker = false
        showStylesPad = false
        showEffectsPicker = false
        showFXPicker = false
        showSubjectPicker = true
    }

    func setColorSplash(_ enabled: Bool) {
        guard enabled != adjustments.colorSplash else { return }
        recordUndoPoint(force: true)
        adjustments.colorSplash = enabled
        adjustmentsChanged()
    }

    /// Choosing PHOTO… without a background photo yet opens the picker first.
    func setBackground(_ style: BackgroundStyle) {
        if style == .photo && customBackground == nil {
            showBackgroundPhotoPicker = true
            return
        }
        guard style != adjustments.background else { return }
        recordUndoPoint(force: true)
        adjustments.background = style
        adjustmentsChanged()
    }

    /// Loads the photo to put behind the subject, then switches the background to it.
    func setCustomBackground(from item: PhotosPickerItem) {
        let importer = self.importer
        Task { [weak self] in
            do {
                let photo = try await importer.loadImage(from: item)
                guard let self else { return }
                self.customBackground = photo.preview
                self.recipe.backgroundPhoto = CIImage(cgImage: photo.preview)
                self.recordUndoPoint(force: true)
                if self.pendingDoubleExposure {
                    // Picked for Double Exposure, not as a new background.
                    self.pendingDoubleExposure = false
                    self.adjustments.doubleExposure = max(self.adjustments.doubleExposure, 0.7)
                } else {
                    self.adjustments.background = .photo
                }
                self.adjustmentsChanged()
            } catch {
                let mapped = PhotoImportError.map(error)
                if mapped != .cancelled {
                    self?.alert = AppAlert(title: "Couldn't Use Photo", message: mapped.errorDescription ?? "")
                }
            }
        }
    }

    func setFilter(_ filter: PhotoFilter) {
        guard filter != adjustments.filter else { return }
        recordUndoPoint(force: true)
        adjustments.filter = filter
        adjustments = Self.withFilmTexture(adjustments)
        adjustmentsChanged()
    }

    /// Opens the glass filter pop-up and renders a live preview tile for each filter.
    func openFilterPicker() {
        showCropEditor = false
        showSubjectPicker = false
        isControlPanelOpen = false
        showStylesPad = false
        showEffectsPicker = false
        showFXPicker = false
        showFilterPicker = true
        renderFilterThumbnails()
    }

    private func renderFilterThumbnails() {
        thumbnailTask?.cancel()
        guard let source = photo?.preview ?? video?.poster else { filterThumbnails = [:]; return }
        let recipe = adjustments
        let processor = self.processor
        thumbnailTask = Task { [weak self] in
            let tiles = await Task.detached(priority: .userInitiated) { () -> [PhotoFilter: CGImage] in
                let full = CIImage(cgImage: source)
                let scale = 160 / max(full.extent.width, full.extent.height, 1)
                let small = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                var result: [PhotoFilter: CGImage] = [:]
                for filter in PhotoFilter.allCases {
                    var state = recipe
                    state.filter = filter
                    state.portrait = false
                    state.colorSplash = false
                    state.background = .original
                    state.grain = 0 // tiles show the look itself, not grain
                    state.skinSmoothing = 0 // and skip face detection for every tile
                    state.filterStrength = 1
                    let output = processor.apply(state, to: small)
                    if let image = processor.context.createCGImage(output, from: output.extent) {
                        result[filter] = image
                    }
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            self?.filterThumbnails = tiles
        }
    }

    /// A film stock also brings its grain (and CineStill its halation), but never overrides values you set.
    static func withFilmTexture(_ state: PhotoAdjustmentState) -> PhotoAdjustmentState {
        let texture: (grain: Double, size: GrainSize, halation: Double)?
        switch state.filter {
        case .portra: texture = (0.25, .fine, 0)
        case .ektar: texture = (0.15, .fine, 0)
        case .gold: texture = (0.3, .medium, 0)
        case .fuji400h: texture = (0.25, .fine, 0)
        case .cinestill: texture = (0.35, .medium, 0.55)
        case .trix: texture = (0.5, .coarse, 0)
        default: texture = nil
        }
        guard let texture else { return state }
        var next = state
        if next.grain == 0 {
            next.grain = texture.grain
            next.grainSize = texture.size
        }
        if next.halation == 0 { next.halation = texture.halation }
        return next
    }

    func cycleFilter() {
        recordUndoPoint(force: true)
        adjustments.filter = adjustments.filter.next
        adjustmentsChanged()
    }

    func setFilterStrength(_ strength: Double) {
        recordUndoPoint() // one drag = one undo step
        adjustments.filterStrength = min(max(strength, 0), 1)
        adjustmentsChanged()
    }

    func setMixer(_ band: ColorBand, _ channel: MixerChannel, to value: Double) {
        recordUndoPoint()
        adjustments.colorMixer[band, channel] = value
        adjustmentsChanged()
    }

    func resetMixer(_ band: ColorBand? = nil) {
        recordUndoPoint(force: true)
        if let band {
            for channel in MixerChannel.allCases { adjustments.colorMixer[band, channel] = 0 }
        } else {
            adjustments.colorMixer = ColorMixer()
        }
        adjustmentsChanged()
    }

    func setRegionEdit(_ region: PhotoRegion, _ control: RegionEdit.Control, to value: Double) {
        recordUndoPoint() // one drag = one undo step
        adjustments[region][keyPath: control.keyPath] = value.isFinite ? min(max(value, -1), 1) : 0
        adjustmentsChanged()
    }

    func resetRegionEdits() {
        recordUndoPoint(force: true)
        adjustments.subjectEdit = RegionEdit()
        adjustments.backgroundEdit = RegionEdit()
        adjustments.skyEdit = RegionEdit()
        adjustmentsChanged()
    }

    /// Describe an edit in words; Apple's on-device model sets the editor's controls (one undo step).
    func applyAIEdit(_ request: String) {
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAskingAI, let source = photo?.preview ?? video?.poster else { return }
        isAskingAI = true
        aiMessage = nil
        let processor = self.processor
        let current = adjustments
        Task { [weak self] in
            let facts = await Task.detached(priority: .userInitiated) { () -> String in
                let input = CIImage(cgImage: source)
                let hasFaces = !ImageProcessingService.faceRects(in: input, extent: input.extent).isEmpty
                return processor.photoFacts(for: source, hasFaces: hasFaces)
            }.value
            do {
                let plan = try await AIEditService.plan(for: text, current: current, photoFacts: facts)
                guard let self else { return }
                let before = self.adjustments
                let next = plan.applied(to: before)
                if next != before {
                    self.recordUndoPoint(force: true)
                    self.adjustments = next
                    self.adjustmentsChanged()
                }
                self.aiBefore = before
                self.aiAfter = next
                self.aiMediaID = self.photo?.id ?? self.video?.id
                self.aiMessage = plan.summary.isEmpty ? "Done." : plan.summary
            } catch {
                self?.aiMessage = error.localizedDescription
            }
            self?.isAskingAI = false
        }
    }

    /// What the last AI edit changed on this photo, for highlighting (empty when it no longer applies).
    var aiChangedParameters: Set<AdjustmentParameter> {
        guard let before = aiBefore, let after = aiAfter, aiMediaID == (photo?.id ?? video?.id) else { return [] }
        return Set(AdjustmentParameter.allCases.filter { after[$0] != before[$0] })
    }

    /// "Exposure +0.4 EV · Warmth +20 · Look: Portra 400", or nil when there is nothing to show.
    var aiChangeSummary: String? {
        guard let before = aiBefore, let after = aiAfter, aiMediaID == (photo?.id ?? video?.id) else { return nil }
        var parts = AdjustmentParameter.allCases.filter { after[$0] != before[$0] }
            .map { "\($0.title) \($0.format(after[$0]))" }
        if after.filter != before.filter { parts.append("Look: \(after.filter.label)") }
        if after.subjectEdit != before.subjectEdit { parts.append("Subject") }
        if after.backgroundEdit != before.backgroundEdit { parts.append("Background") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }

    /// Puts back the edit from before the last AI edit (itself undoable).
    func revertAIEdit() {
        guard let before = aiBefore, aiMediaID == (photo?.id ?? video?.id) else { return }
        recordUndoPoint(force: true)
        adjustments = before
        clearAIEdit()
        adjustmentsChanged()
    }

    func clearAIEdit() {
        aiBefore = nil
        aiAfter = nil
        aiMessage = nil
    }

    // MARK: Graduated and radial filters

    func addLocal(_ shape: LocalAdjustment.Shape) {
        guard adjustments.localAdjustments.count < LocalAdjustment.limit else { return }
        recordUndoPoint(force: true)
        adjustments.localAdjustments.append(LocalAdjustment(shape: shape))
        adjustmentsChanged()
    }

    func updateLocal(_ id: UUID, _ change: (inout LocalAdjustment) -> Void) {
        guard let index = adjustments.localAdjustments.firstIndex(where: { $0.id == id }) else { return }
        recordUndoPoint() // one drag = one undo step
        change(&adjustments.localAdjustments[index])
        adjustments.localAdjustments[index] = adjustments.localAdjustments[index].clamped
        adjustmentsChanged()
    }

    func removeLocal(_ id: UUID) {
        recordUndoPoint(force: true)
        adjustments.localAdjustments.removeAll { $0.id == id }
        adjustmentsChanged()
    }

    // MARK: FX

    func openFXPicker() {
        showCropEditor = false
        showSubjectPicker = false
        isControlPanelOpen = false
        showFilterPicker = false
        showStylesPad = false
        showEffectsPicker = false
        showFXPicker = true
    }

    /// One drag of an FX slider is one undo step.
    func setEffect(_ path: WritableKeyPath<PhotoAdjustmentState, Double>, to value: Double) {
        recordUndoPoint()
        adjustments[keyPath: path] = value.isFinite ? value : 0
        adjustmentsChanged()
    }

    /// Double exposure needs a second photo: the first time, pick one (shared with Background Swap's photo).
    func setDoubleExposure(_ amount: Double) {
        if amount > 0, customBackground == nil {
            pendingDoubleExposure = true
            showBackgroundPhotoPicker = true
            return
        }
        setEffect(\.doubleExposure, to: min(max(amount, 0), 1))
    }

    func chooseDoubleExposurePhoto() {
        pendingDoubleExposure = true
        showBackgroundPhotoPicker = true
    }

    func setFaceRedaction(_ mode: Redaction) {
        guard mode != adjustments.faceRedaction else { return }
        recordUndoPoint(force: true)
        adjustments.faceRedaction = mode
        adjustmentsChanged()
    }

    func addRedactionStroke(_ stroke: RedactionStroke) {
        guard !stroke.points.isEmpty, adjustments.redactionStrokes.count < RedactionStroke.limit else { return }
        recordUndoPoint(force: true)
        adjustments.redactionStrokes.append(stroke)
        adjustmentsChanged()
    }

    func removeLastRedactionStroke() {
        guard !adjustments.redactionStrokes.isEmpty else { return }
        recordUndoPoint(force: true)
        adjustments.redactionStrokes.removeLast()
        adjustmentsChanged()
    }

    func clearRedactionStrokes() {
        guard !adjustments.redactionStrokes.isEmpty else { return }
        recordUndoPoint(force: true)
        adjustments.redactionStrokes = []
        adjustmentsChanged()
    }

    /// A random look: another filter at a random strength, sometimes with grain, halation or a vignette.
    func shuffleLook() {
        guard hasMedia else { return }
        recordUndoPoint(force: true)
        adjustments = Self.shuffled(adjustments)
        adjustmentsChanged()
        showToast(adjustments.filter.label)
    }

    static func shuffled(_ state: PhotoAdjustmentState) -> PhotoAdjustmentState {
        var next = state
        next.filter = PhotoFilter.allCases.filter { $0 != .none && $0 != state.filter }.randomElement() ?? .vivid
        next.filterStrength = [0.7, 0.85, 1].randomElement() ?? 1
        next.grain = [0, 0, 0.15, 0.25, 0.35].randomElement() ?? 0
        next.grainSize = GrainSize.allCases.randomElement() ?? .medium
        next.halation = [0, 0, 0, 0.3].randomElement() ?? 0
        next.vignette = [0, 0, 0.15, 0.3].randomElement() ?? 0
        return next
    }

    /// Saves the edited subject as a transparent PNG sticker to Photos and copies it.
    func makeSticker() {
        guard let source = photo?.preview else { return }
        let processor = self.processor
        let recipe = adjustments.withoutGeometry
        let cached = previewSubjectSource === source ? previewSubjectMask : nil
        let background = customBackground.map { CIImage(cgImage: $0) }
        isRenderingEffect = true
        effectMessage = "Making sticker…"
        effectTask?.cancel()
        effectTask = Task { [weak self] in
            let png = await Task.detached(priority: .userInitiated) { () -> Data? in
                let input = CIImage(cgImage: source)
                guard let mask = cached ?? SubjectMasker.mask(for: input) else { return nil }
                let edited = processor.apply(recipe, to: input, subjectMask: mask, backgroundPhoto: background)
                return processor.stickerPNG(edited: edited, mask: mask)
            }.value
            guard let self else { return }
            self.isRenderingEffect = false
            guard let png else { return self.showToast("No subject found") }
            ScreenCapture.copyPNG(png)
            do {
                try await ScreenCapture.savePNGToPhotos(png)
                self.showToast("Sticker saved to Photos and copied")
            } catch {
                self.showToast("Sticker copied. Allow Photos access to save it.")
            }
        }
    }

    /// Turns the photo into a short "3D" clip: the subject floats in front of a moving background.
    func makeParallaxVideo() {
        guard let source = photo?.preview else { return }
        let processor = self.processor
        let recipe = adjustments.withoutGeometry
        let cached = previewSubjectSource === source ? previewSubjectMask : nil
        let background = customBackground.map { CIImage(cgImage: $0) }
        showSubjectPicker = false
        isRenderingEffect = true
        effectMessage = "Making 3D video…"
        effectTask?.cancel()
        effectTask = Task { [weak self] in
            do {
                let url = try LiveEffectsService.newURL("mov")
                let made = try await Task.detached(priority: .userInitiated) { () -> Bool in
                    let input = CIImage(cgImage: source)
                    guard let mask = cached ?? SubjectMasker.mask(for: input) else { return false }
                    let edited = processor.apply(recipe, to: input, subjectMask: mask, backgroundPhoto: background)
                    try await ParallaxVideo.render(edited: edited, mask: mask, processor: processor, to: url)
                    return true
                }.value
                guard let self else { return }
                self.isRenderingEffect = false
                if made { self.showEffectResult(url, toast: "3D video created") } else { self.showToast("No subject found") }
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isRenderingEffect = false
                self.alert = AppAlert(title: "3D Video Failed", message: error.localizedDescription)
            }
        }
    }

    func setGrainSize(_ size: GrainSize) {
        guard size != adjustments.grainSize else { return }
        recordUndoPoint(force: true)
        adjustments.grainSize = size
        adjustmentsChanged()
    }

    /// Magic-wand Auto: sets the light and color sliders from the unedited photo or video frame.
    func autoEnhance() {
        guard let source = photo?.preview ?? video?.poster else { return }
        let processor = self.processor
        let current = adjustments
        Task { [weak self] in
            let next = await Task.detached(priority: .userInitiated) { processor.autoEnhanced(current, for: source) }.value
            guard let self, self.adjustments == current, next != current else { return } // edited meanwhile: keep that
            self.recordUndoPoint(force: true)
            self.adjustments = next
            self.adjustmentsChanged()
        }
    }

    func setNightLook(_ enabled: Bool) {
        recordUndoPoint(force: true)
        adjustments.nightLook = enabled
        adjustmentsChanged()
    }

    func resetAllAdjustments() {
        recordUndoPoint(force: true)
        adjustments = PhotoAdjustmentState()
        adjustmentsChanged()
    }

    // MARK: Undo / redo

    /// Saves the current recipe before a change. Rapid changes (one slider drag) share one undo step.
    private func recordUndoPoint(force: Bool = false) {
        let now = Date()
        if force || now.timeIntervalSince(lastUndoPoint) > 0.6 {
            undoStack.append(adjustments)
            if undoStack.count > 50 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastUndoPoint = now
        updateUndoState()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(adjustments)
        adjustments = previous
        lastUndoPoint = .distantPast
        updateUndoState()
        adjustmentsChanged()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(adjustments)
        adjustments = next
        lastUndoPoint = .distantPast
        updateUndoState()
        adjustmentsChanged()
    }

    private func clearUndoHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
        updateUndoState()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    // MARK: Style presets

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets.removeAll { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
        presets.append(StylePreset(name: trimmed, adjustments: adjustments))
        StylePreset.save(presets, to: defaults)
    }

    func applyPreset(_ preset: StylePreset) {
        recordUndoPoint(force: true)
        adjustments = preset.adjustments.clamped()
        adjustmentsChanged()
    }

    func deletePreset(_ preset: StylePreset) {
        presets.removeAll { $0.id == preset.id }
        StylePreset.save(presets, to: defaults)
    }

    /// Hold-to-compare: shows the unedited photo or video while held.
    func setShowOriginal(_ value: Bool) {
        showOriginal = value
        recipe.value = value ? PhotoAdjustmentState() : adjustments
        refreshPausedVideoFrame()
        refreshPhotoAnalysis()
    }

    // MARK: Scopes and focus peaking

    func setScopeMode(_ mode: ScopeMode) {
        scopeMode = mode
        if mode == .off { scopeData = nil }
        refreshPhotoAnalysis()
        updateVideoScopeSampling()
    }

    func setFocusPeaking(_ enabled: Bool) {
        focusPeaking = enabled
        recipe.peaking = enabled
        overlaysChanged()
    }

    func setZebras(_ enabled: Bool) {
        zebras = enabled
        recipe.zebras = enabled
        overlaysChanged()
    }

    private func overlaysChanged() {
        if !focusPeaking && !zebras { overlayImage = nil }
        refreshPausedVideoFrame()
        refreshPhotoAnalysis()
    }

    /// Recomputes scope data / peaking overlay for the photo currently on screen (off the main thread).
    private func refreshPhotoAnalysis() {
        analysisTask?.cancel()
        guard photo != nil, let image = displayedImage, scopeMode != .off || focusPeaking || zebras else { return }
        let wantsScopes = scopeMode != .off
        let wantsPeaking = focusPeaking
        let wantsZebras = zebras
        let processor = self.processor
        analysisTask = Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> (ScopeData?, CGImage?) in
                (wantsScopes ? ScopeData.compute(from: image) : nil,
                 wantsPeaking || wantsZebras
                    ? processor.renderAnalysisOverlay(image, peaking: wantsPeaking, zebras: wantsZebras) : nil)
            }.value
            guard !Task.isCancelled, let self, self.displayedImage === image else { return }
            if wantsScopes { self.scopeData = result.0 }
            if wantsPeaking || wantsZebras { self.overlayImage = result.1 }
        }
    }

    /// While scopes are on and a video is loaded, samples composed frames about 4 times a second.
    private func updateVideoScopeSampling() {
        scopeTask?.cancel()
        scopeTask = nil
        guard scopeMode != .off, video != nil else { return }
        scopeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sampleVideoScopes()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func sampleVideoScopes() async {
        guard let output = videoOutput else { return }
        let time = output.itemTime(forHostTime: CACurrentMediaTime())
        guard output.hasNewPixelBuffer(forItemTime: time) || scopeData == nil,
              let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }
        let processor = self.processor
        let orientation = video?.exifOrientation ?? 1
        let wantsPortrait = (video?.displaySize.height ?? 0) > (video?.displaySize.width ?? 0)
        let data = await Task.detached(priority: .utility) { () -> ScopeData? in
            var frame = CIImage(cvPixelBuffer: buffer)
            // Decoded frames arrive in the track's stored orientation; turn them upright so
            // RGB Parade's left/right matches the picture. Skip if they're already upright.
            if (frame.extent.height > frame.extent.width) != wantsPortrait {
                frame = frame.oriented(forExifOrientation: orientation)
            }
            let scale = 160 / max(frame.extent.width, 1)
            let small = frame.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let image = processor.context.createCGImage(small, from: small.extent) else { return nil }
            return ScopeData.compute(from: image)
        }.value
        guard !Task.isCancelled, scopeMode != .off, let data else { return }
        scopeData = data
    }

    private func adjustmentsChanged() {
        invalidateExport()
        recipe.value = showOriginal ? PhotoAdjustmentState() : adjustments
        refreshPausedVideoFrame()
        scheduleRender()
    }

    /// Renders the downsampled photo preview off the main thread. One render runs at a time; edits made
    /// meanwhile fold into one follow-up render of the newest settings, so slider drags never stack up
    /// GPU work and the screen always ends on the latest edit. (Videos render live in the compositor.)
    private func scheduleRender() {
        guard let source = photo?.preview else {
            renderNeeded = false
            renderedPreview = nil
            return
        }
        guard !adjustments.isIdentity else {
            renderNeeded = false
            renderedPreview = source
            refreshPhotoAnalysis()
            return
        }
        renderNeeded = true
        guard renderTask == nil else { return }
        renderTask = Task { [weak self] in
            while let self, self.renderNeeded {
                self.renderNeeded = false
                await self.renderLatest()
            }
            self?.renderTask = nil
        }
    }

    private func renderLatest() async {
        guard let source = photo?.preview else { return }
        let recipe = adjustments
        guard !recipe.isIdentity else { return }
        let processor = self.processor
        let backgroundPhoto = customBackground.map { CIImage(cgImage: $0) }
        // The subject mask is found once per photo (also when there is none, so it isn't searched again).
        if recipe.needsSubject, previewSubjectSource !== source {
            isFindingSubject = true
            let found = await Task.detached(priority: .userInitiated) {
                SubjectMasker.mask(for: CIImage(cgImage: source))
            }.value
            guard photo?.preview === source else { return }
            previewSubjectMask = found
            previewSubjectSource = source
            isFindingSubject = false
            if found == nil { showToast("No subject found") }
        }
        let mask = previewSubjectSource === source ? previewSubjectMask : nil
        // No subject in this photo: render without the subject edits instead of searching again every frame.
        let renderRecipe = mask == nil ? recipe.withoutSubjectEdits : recipe
        let rendered = await Task.detached(priority: .userInitiated) {
            processor.renderPreview(source, adjustments: renderRecipe, subjectMask: mask, backgroundPhoto: backgroundPhoto)
        }.value
        // A reset to no edits while this rendered already showed the original: keep it.
        guard photo?.preview === source, !adjustments.isIdentity else { return }
        if let rendered {
            renderedPreview = rendered
            refreshPhotoAnalysis()
        } else {
            alert = AppAlert(title: "Adjustment Failed", message: "The preview couldn't be rendered with these settings.")
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
        let speed = Double(playbackRate)
        let trimRange = self.trimRange
        let videoPreset = options.size.videoPreset
        let backgroundPhoto = customBackground.map { CIImage(cgImage: $0) }
        let work: @Sendable () async throws -> URL

        if let video {
            work = {
                try exporter.prepareDirectory()
                if isEdited {
                    let url = exporter.directory.appendingPathComponent(
                        PhotoExportService.fileName(content: .adjusted, fileExtension: "mov"))
                    try await VideoService.exportEdited(video, adjustments: adjustments, processor: processor, to: url,
                                                       timeRange: trimRange, speed: speed, preset: videoPreset,
                                                       backgroundPhoto: backgroundPhoto)
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
                overlays: isEdited && options.burnOverlays ? overlays : OverlayBurnIn(),
                backgroundPhoto: backgroundPhoto
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

    /// Records the screen (video + camera controls) while the video plays through once (up to 60 s),
    /// then saves the recording to Photos. Tap the center control to stop early.
    func saveVideoWithUI() {
        guard let video, let player, !isRecordingUI else { return }
        showExport = false
        showAdjustments = false
        isControlPanelOpen = false
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700)) // let sheets finish dismissing
            guard let self else { return }
            do {
                try await ScreenCapture.startRecording()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "Screen recording couldn't start."
                self.alert = AppAlert(title: "Couldn't Record Screen", message: message)
                return
            }
            self.stopRecordingRequested = false
            self.isRecordingUI = true
            _ = await player.seek(to: CMTime(seconds: self.trimStart, preferredTimescale: 600),
                                  toleranceBefore: .zero, toleranceAfter: .zero)
            player.playImmediately(atRate: self.playbackRate)
            self.isPlaying = true

            // One pass through the trimmed range at the mode's speed, capped at 60 s.
            let length = (self.trimEnd - self.trimStart) / Double(max(self.playbackRate, 0.01))
            let limit = min(max(length, 1), 60)
            let started = Date()
            while !self.stopRecordingRequested, Date().timeIntervalSince(started) < limit {
                try? await Task.sleep(for: .milliseconds(100))
            }

            player.pause()
            self.isPlaying = false
            self.isRecordingUI = false
            do {
                let url = try await ScreenCapture.stopRecording()
                try await ScreenCapture.saveVideoToPhotos(url)
                try? FileManager.default.removeItem(at: url)
                self.showToast("Video saved to Photos")
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? "The recording couldn't be saved."
                self.alert = AppAlert(title: "Couldn't Save Video", message: message)
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
