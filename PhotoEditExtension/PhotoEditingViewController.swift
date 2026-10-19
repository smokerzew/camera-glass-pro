import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Camera Glass inside the Photos app: Edit › ⋯ › Camera Glass. Filters, Photographic Styles and the light and
/// color sliders, using the app's own pipeline. Photos keeps the original plus our recipe (`PhotosEditFormat`),
/// so the edit can be reopened here and changed, or reverted in Photos.
final class PhotoEditingViewController: UIViewController, PHContentEditingController {
    private var input: PHContentEditingInput?
    private let model = PhotoEditModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let host = UIHostingController(rootView: PhotoEditView(model: model))
        host.view.backgroundColor = .black
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    func canHandle(_ adjustmentData: PHAdjustmentData) -> Bool {
        PhotosEditFormat.canHandle(adjustmentData)
    }

    func startContentEditing(with contentEditingInput: PHContentEditingInput, placeholderImage: UIImage) {
        input = contentEditingInput
        let saved = contentEditingInput.adjustmentData.flatMap(PhotosEditFormat.decode) ?? PhotoAdjustmentState()
        model.load(preview: contentEditingInput.displaySizeImage?.cgImage ?? placeholderImage.cgImage, state: saved)
    }

    func finishContentEditing(completionHandler: @escaping (PHContentEditingOutput?) -> Void) {
        guard let input, let url = input.fullSizeImageURL else { completionHandler(nil); return }
        let state = model.state
        DispatchQueue.global(qos: .userInitiated).async {
            let output = PHContentEditingOutput(contentEditingInput: input)
            let processor = ImageProcessingService.shared
            guard let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
                  let recipe = try? PhotosEditFormat.encode(state),
                  let data = try? processor.encode(processor.apply(state, to: source), as: .jpeg, colorSpace: source.colorSpace),
                  (try? data.write(to: output.renderedContentURL, options: .atomic)) != nil
            else { completionHandler(nil); return }
            output.adjustmentData = recipe
            completionHandler(output)
        }
    }

    var shouldShowCancelConfirmation: Bool { model.state != model.startState }

    func cancelContentEditing() {}
}

/// The extension's edit state and its live preview.
@MainActor
@Observable
final class PhotoEditModel {
    private(set) var preview: CGImage?
    private(set) var rendered: CGImage?
    private(set) var startState = PhotoAdjustmentState()
    var state = PhotoAdjustmentState() { didSet { if state != oldValue { render() } } }
    @ObservationIgnored private var renderTask: Task<Void, Never>?

    func load(preview: CGImage?, state: PhotoAdjustmentState) {
        self.preview = preview
        startState = state
        self.state = state
        render()
    }

    private func render() {
        guard let preview else { return }
        renderTask?.cancel()
        let state = self.state
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30)) // coalesce slider ticks
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                ImageProcessingService.shared.renderPreview(preview, adjustments: state.withoutGeometry)
            }.value
            guard !Task.isCancelled else { return }
            self?.rendered = image
        }
    }
}

/// Photo on top, then Filter / Styles / Light / Color pages in the app's glass style.
struct PhotoEditView: View {
    @Bindable var model: PhotoEditModel
    @State private var page: Page = .filter
    @State private var category: FilterCategory = .classic

    enum Page: String, CaseIterable { case filter, styles, light, color }

    var body: some View {
        VStack(spacing: 12) {
            Group {
                if let image = model.rendered ?? model.preview {
                    Image(decorative: image, scale: 1).resizable().scaledToFit()
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 12) {
                GlassTabs(tabs: Page.allCases, selection: $page) { $0.rawValue.capitalized }
                switch page {
                case .filter: filterPage
                case .styles: stylesPage
                case .light: sliders(.light)
                case .color: sliders(.color)
                }
            }
            .padding(14)
            .cameraGlass(.regular, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .onAppear { category = model.state.filter == .none ? .classic : model.state.filter.category }
    }

    private var filterPage: some View {
        VStack(spacing: 10) {
            GlassTabs(tabs: FilterCategory.allCases, selection: $category) { $0.title }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip("Original", selected: model.state.filter == .none) { model.state.filter = .none }
                    ForEach(category.filters, id: \.self) { filter in
                        chip(filter.label, selected: model.state.filter == filter) { model.state.filter = filter }
                    }
                }
            }
            GlassSliderRow(title: "Strength", value: model.state.filterStrength) { model.state.filterStrength = $0 }
                .opacity(model.state.filter == .none ? 0.4 : 1)
                .disabled(model.state.filter == .none)
        }
    }

    private var stylesPage: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PhotographicStyle.allCases) { style in
                        chip(style.label, selected: model.state.style == style) { model.state.style = style }
                    }
                }
            }
            GlassSliderRow(title: "Tone", value: model.state.styleTone, range: -1...1,
                           display: { "\(Int(($0 * 100).rounded()))" }) { model.state.styleTone = $0 }
            GlassSliderRow(title: "Color", value: model.state.styleColor, range: -1...1,
                           display: { "\(Int(($0 * 100).rounded()))" }) { model.state.styleColor = $0 }
        }
    }

    private func sliders(_ group: AdjustGroup) -> some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(AdjustmentParameter.allCases.filter { $0.group == group }) { parameter in
                    GlassSliderRow(title: parameter.title, value: model.state[parameter], range: parameter.range,
                                   display: { parameter.format($0) }) { model.state[parameter] = $0 }
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Color.yellow : .white)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .cameraGlass(selected ? .selected : .interactive, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
