import SwiftUI

/// Export sheet: choose original vs edited copy, render off the main thread, then hand the file
/// to the native share sheet (which offers Save Image, Files, AirDrop, etc.).
struct PhotoExportView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.exportContent) private var content = ExportContent.adjusted
    @AppStorage(SettingsKey.showCenter) private var showCenter = false
    @AppStorage(SettingsKey.exportSize) private var size = ExportSize.full
    @State private var cropToFraming = false
    @State private var burnOverlays = false

    private var options: ExportOptions {
        ExportOptions(content: content, format: vm.exportFormat, size: size, cropToFraming: cropToFraming, burnOverlays: burnOverlays)
    }

    private var overlays: OverlayBurnIn {
        OverlayBurnIn(gridDivisions: vm.gridStyle.divisions, center: showCenter)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Export", selection: $content) {
                        ForEach(ExportContent.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(footerText)
                }

                if content == .adjusted && isVideo {
                    Section("Edited Copy") {
                        Picker("Size", selection: $size) {
                            ForEach(ExportSize.allCases) { Text($0.videoLabel).tag($0) }
                        }
                    }
                }

                if content == .adjusted && !isVideo {
                    Section("Edited Copy") {
                        Picker("Size", selection: $size) {
                            ForEach(ExportSize.allCases) { Text($0.photoLabel).tag($0) }
                        }
                        Picker("Format", selection: Binding(get: { vm.exportFormat }, set: { vm.setExportFormat($0) })) {
                            ForEach(ExportFormat.allCases) { Text($0.label).tag($0) }
                        }
                        Toggle("Crop to Preview Framing", isOn: $cropToFraming)
                        Toggle("Include Composition Guides", isOn: $burnOverlays)
                            .disabled(overlays.isEmpty)
                    }
                    if cropToFraming || burnOverlays {
                        Section {
                            if cropToFraming {
                                Label("Crops to the current zoom and aspect framing.", systemImage: "crop")
                            }
                            if burnOverlays {
                                Label("Draws the visible grid and center guide into the image.", systemImage: "squareshape.split.3x3")
                            }
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if vm.isExporting {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text(content == .adjusted ? (isVideo ? "Rendering video…" : "Rendering full resolution…") : "Preparing file…")
                        }
                    } else if let file = vm.exportedFile {
                        Label("Ready: \(file.lastPathComponent)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.footnote)
                        ShareLink(item: file, preview: sharePreview(for: file)) {
                            Label("Share or Save", systemImage: "square.and.arrow.up")
                                .font(.body.weight(.semibold))
                        }
                    } else {
                        Button {
                            vm.prepareExport(options: options, overlays: overlays)
                        } label: {
                            Label("Prepare Export", systemImage: "arrow.down.doc")
                                .font(.body.weight(.semibold))
                        }
                        .disabled(!vm.hasMedia)
                    }
                }

                Section {
                    Button {
                        vm.saveScreenWithUI()
                    } label: {
                        Label("Save Screen with UI", systemImage: "camera.viewfinder")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(!vm.hasMedia)

                    if isVideo {
                        Button {
                            vm.saveVideoWithUI()
                        } label: {
                            Label("Save Video with UI", systemImage: "record.circle")
                                .font(.body.weight(.semibold))
                        }
                    }
                } footer: {
                    Text(isVideo
                         ? "Screen saves a still with the camera controls. Video records the screen while your video plays once (up to 60 s; tap the shutter to stop early) and saves it to Photos."
                         : "Saves a screenshot of the viewfinder with the camera controls, as you see it now, to Photos.")
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: options) { vm.invalidateExport() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
        .appAlert(vm)
    }

    private var isVideo: Bool { vm.video != nil }

    private var footerText: String {
        let format = vm.photo?.formatLabel ?? vm.video?.formatLabel ?? "file"
        if content == .original {
            return "Shares the file exactly as imported (\(format)), including any metadata it already had. Nothing is added or changed."
        }
        return isVideo
            ? "Renders a full-quality MOV with your adjustments and filter. The original is untouched."
            : "Renders a full-resolution copy with your adjustments. The original is untouched, and no capture metadata is added."
    }

    private func sharePreview(for file: URL) -> SharePreview<Image, Never> {
        let image = vm.displayedImage.map { Image(decorative: $0, scale: 1) } ?? Image(systemName: "photo")
        return SharePreview(file.lastPathComponent, image: image)
    }
}
