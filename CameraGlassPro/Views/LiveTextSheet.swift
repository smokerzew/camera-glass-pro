import SwiftUI
import Translation
import UIKit

/// Lists the text found in the frame: select, copy, or translate on device (Apple Translation).
struct LiveTextSheet: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isTranslating = false

    private var allText: String { vm.recognizedText.map(\.text).joined(separator: "\n") }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(vm.recognizedText) { line in
                        Text(line.text)
                            .textSelection(.enabled)
                    }
                } footer: {
                    Text("Recognized on this device. Touch and hold a line to select part of it.")
                }
            }
            .navigationTitle("Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button {
                        UIPasteboard.general.string = allText
                    } label: {
                        Label("Copy All", systemImage: "doc.on.doc")
                    }
                    Spacer()
                    Button {
                        isTranslating = true
                    } label: {
                        Label("Translate", systemImage: "translate")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .translationPresentation(isPresented: $isTranslating, text: allText)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .modifier(GlassSheetBackground())
    }
}
