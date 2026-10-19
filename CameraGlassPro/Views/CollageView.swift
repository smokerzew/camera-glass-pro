import SwiftUI

/// Collage sheet: live preview, the edit setting (each photo's own edit, or the same edit on all), shape and
/// layout. Make Collage opens the result as a new item, which can then be edited as a whole.
struct CollageView: View {
    @Bindable var vm: CameraWorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode: Collage.EditMode = .individual
    @State private var shape: Collage.Shape = .square
    @State private var layoutIndex = 0
    @State private var photos: [CGImage] = []
    @State private var preview: CGImage?
    @State private var loading = true

    private var layouts: [[CGRect]] { Collage.layouts(for: photos.count) }
    private var layout: [CGRect] { layouts.indices.contains(layoutIndex) ? layouts[layoutIndex] : layouts.first ?? [] }

    private struct RenderKey: Equatable {
        let count: Int, layout: Int, shape: Collage.Shape, mode: Collage.EditMode
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    ZStack {
                        if let preview {
                            Image(decorative: preview, scale: 1).resizable().scaledToFit()
                                .accessibilityLabel("Collage preview")
                        } else {
                            ProgressView()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 300)

                    VStack(alignment: .leading, spacing: 6) {
                        Picker("Edits", selection: $mode) {
                            ForEach(Collage.EditMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(mode == .individual
                             ? "Each photo keeps its own edit. Swipe to a photo in the viewfinder and edit it, then come back here."
                             : "The edit on the photo you're viewing goes on every photo in the collage.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Shape", selection: $shape) {
                        ForEach(Collage.Shape.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if layouts.count > 1 {
                        HStack(spacing: 12) {
                            ForEach(layouts.indices, id: \.self) { index in
                                Button { layoutIndex = index } label: {
                                    LayoutIcon(cells: layouts[index], selected: index == layoutIndex)
                                        .frame(width: 54, height: 54)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Layout \(index + 1)")
                                .accessibilityAddTraits(index == layoutIndex ? .isSelected : [])
                            }
                        }
                    }

                    Text("\(photos.count) of the photos you picked, edge to edge. It opens as a new item you can edit as a whole.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .navigationTitle("Collage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Make") { vm.makeCollage(photos, layout: layout, shape: shape) }
                        .fontWeight(.semibold)
                        .disabled(loading || photos.count < 2)
                }
            }
        }
        .task(id: mode) {
            loading = true
            photos = (try? await vm.collagePhotos(mode)) ?? []
            if !layouts.indices.contains(layoutIndex) { layoutIndex = 0 }
            loading = false
        }
        .task(id: RenderKey(count: photos.count, layout: layoutIndex, shape: shape, mode: mode)) {
            let cells = layout, chosen = shape, images = photos
            guard images.count >= 2 else { preview = nil; return }
            preview = await Task.detached(priority: .userInitiated) {
                Collage.render(images.map { CIImage(cgImage: $0) }, layout: cells, shape: chosen, longEdge: 700)
                    .flatMap { ImageProcessingService.shared.context.createCGImage($0, from: $0.extent) }
            }.value
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .appAlert(vm)
    }
}

/// Small drawing of a layout's cells.
private struct LayoutIcon: View {
    let cells: [CGRect]
    let selected: Bool

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                ForEach(cells.indices, id: \.self) { index in
                    let cell = cells[index]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(selected ? Color.yellow.opacity(0.8) : Color.white.opacity(0.35))
                        .frame(width: max(1, cell.width * proxy.size.width - 2), height: max(1, cell.height * proxy.size.height - 2))
                        .offset(x: cell.minX * proxy.size.width + 1, y: cell.minY * proxy.size.height + 1)
                }
            }
        }
        .padding(4)
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.yellow : .white.opacity(0.3), lineWidth: selected ? 2 : 1) }
    }
}
