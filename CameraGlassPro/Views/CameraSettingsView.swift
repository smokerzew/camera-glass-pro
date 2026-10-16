import SwiftUI

struct CameraSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKey.appearance) private var appearance = AppearanceSetting.dark
    @AppStorage(SettingsKey.controlStyle) private var controlStyle = ControlStyle.glass
    @AppStorage(SettingsKey.controlOpacity) private var controlOpacity = 1.0
    @AppStorage(SettingsKey.gridStyle) private var gridStyle = GridStyle.off
    @AppStorage(SettingsKey.gridOpacity) private var gridOpacity = 0.45
    @AppStorage(SettingsKey.showLevel) private var showLevel = false
    @AppStorage(SettingsKey.showCenter) private var showCenter = false
    @AppStorage(SettingsKey.showModeGuides) private var showModeGuides = true
    @AppStorage(SettingsKey.defaultZoom) private var defaultZoom = 1.0
    @AppStorage(SettingsKey.defaultAspect) private var defaultAspect = AspectRatioOption.original
    @AppStorage(SettingsKey.imageFit) private var imageFit = ImageFit.fill
    @AppStorage(SettingsKey.showImportedBadge) private var showImportedBadge = true
    @AppStorage(SettingsKey.previewBackground) private var previewBackground = PreviewBackground.black
    @AppStorage(SettingsKey.keepAdjustmentsOnReplace) private var keepAdjustments = false
    @AppStorage(SettingsKey.exportContent) private var exportContent = ExportContent.adjusted
    @AppStorage(SettingsKey.exportFormat) private var exportFormat = ExportFormat.jpeg
    @AppStorage(SettingsKey.reduceMotion) private var reduceMotion = false
    @AppStorage(SettingsKey.highContrast) private var highContrast = false
    @AppStorage(SettingsKey.largeLabels) private var largeLabels = false

    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(AppearanceSetting.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Control Style", selection: $controlStyle) {
                        ForEach(ControlStyle.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledSlider(title: "Control Opacity", value: $controlOpacity, range: 0.5...1,
                                  valueText: "\(Int(controlOpacity * 100))%")
                }

                Section {
                    Picker("Grid", selection: $gridStyle) {
                        ForEach(GridStyle.allCases) { Text($0.label).tag($0) }
                    }
                    LabeledSlider(title: "Grid Opacity", value: $gridOpacity, range: 0.15...0.9,
                                  valueText: "\(Int(gridOpacity * 100))%")
                        .disabled(gridStyle == .off)
                    Toggle("Level Guide", isOn: $showLevel)
                    Toggle("Center Guide", isOn: $showCenter)
                    Toggle("Mode Framing Guides", isOn: $showModeGuides)
                } header: {
                    Text("Composition")
                } footer: {
                    Text("Guides are drawn over the preview only. The level guide is a visual reference and doesn't read device sensors.")
                }

                Section("Preview") {
                    Picker("Default Zoom", selection: $defaultZoom) {
                        ForEach(ZoomLimits.presets, id: \.self) { Text(ZoomLimits.label(for: $0) + "×").tag(Double($0)) }
                    }
                    Picker("Default Aspect", selection: $defaultAspect) {
                        ForEach(AspectRatioOption.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Image Fit", selection: $imageFit) {
                        ForEach(ImageFit.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Background", selection: $previewBackground) {
                        ForEach(PreviewBackground.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Show “Imported Photo” Badge", isOn: $showImportedBadge)
                }

                Section {
                    Toggle("Keep Adjustments on Replace", isOn: $keepAdjustments)
                } header: {
                    Text("Image Adjustments")
                } footer: {
                    Text("When off, a newly imported photo starts with neutral adjustments.")
                }

                Section("Export Defaults") {
                    Picker("Export", selection: $exportContent) {
                        ForEach(ExportContent.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Format", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Toggle("Reduce Motion", isOn: $reduceMotion)
                    Toggle("Higher-Contrast Controls", isOn: $highContrast)
                    Toggle("Larger Labels", isOn: $largeLabels)
                } header: {
                    Text("Accessibility")
                } footer: {
                    Text("System Reduce Motion, Increase Contrast and Reduce Transparency are always respected; these add to them.")
                }

                Section {
                    Button("Reset All Preferences", role: .destructive) { confirmReset = true }
                }

                Section("About") {
                    LabeledContent("App", value: "Camera Glass Pro")
                    LabeledContent("Version", value: Self.version)
                    Text("Camera Glass Pro is a camera-inspired workspace for photos you already have. It does not use the camera, capture photos or video, or replace the Camera app. Flash, Live and Timer are visual preferences; Portrait, Video, Cinematic and Pano are preview-only looks. Photos are processed on this device and never uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all preferences?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset Preferences", role: .destructive) { SettingsKey.resetAll() }
            } message: {
                Text("Your current photo and its edits are not affected.")
            }
        }
        .modifier(GlassSheetBackground())
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let valueText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).foregroundStyle(.secondary).monospacedDigit()
            }
            Slider(value: $value, in: range)
                .accessibilityLabel(title)
                .accessibilityValue(valueText)
        }
    }
}
