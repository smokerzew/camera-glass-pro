import SwiftUI

/// Export sheet: choose original vs edited copy, render off the main thread, then hand the file
/// to the native share sheet (which offers Save Image, Files, AirDrop, etc.).
struct PhotoExportView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.exportContent) private var content = ExportContent.adjusted
    @AppStorage(SettingsKey.exportFormat) private var format = ExportFormat.jpeg
    @AppStorage(SettingsKey.gridStyle) private var gridStyle = GridStyle.off
    @AppStorage(SettingsKey.showCenter) private var showCenter = false
    @State private var cropToFraming = false
    @State private var burnOverlays = false

    private var options: ExportOptions {
        ExportOptions(content: content, format: format, cropToFraming: cropToFraming, burnOverlays: burnOverlays)
    }

    private var overlays: OverlayBurnIn {
        OverlayBurnIn(gridDivisions: gridStyle.divisions, center: showCenter)
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
                    Text(content == .original
                         ? "Shares the file exactly as imported (\(vm.photo?.formatLabel ?? "image")), including any metadata it already had. Nothing is added or changed."
                         : "Renders a full-resolution copy with your adjustments. The original is untouched, and no capture metadata is added.")
                }

                if content == .adjusted {
                    Section("Edited Copy") {
                        Picker("Format", selection: $format) {
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
                            Text(content == .adjusted ? "Rendering full resolution…" : "Preparing file…")
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
                        .disabled(vm.photo == nil)
                    }
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

    private func sharePreview(for file: URL) -> SharePreview<Image, Never> {
        let image = vm.displayedImage.map { Image(decorative: $0, scale: 1) } ?? Image(systemName: "photo")
        return SharePreview(file.lastPathComponent, image: image)
    }
}
