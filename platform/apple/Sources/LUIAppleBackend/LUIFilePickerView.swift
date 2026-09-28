import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif

/// Non-visual `file-picker` node: presents the platform file importer,
/// photo library picker, or camera capture when the `request` property
/// changes to a new token while `enabled` is true.
///
/// Handshake: a new `request` token presents the picker for `source`
/// (`"files"` default, `"photos"`, `"camera"`). A completed pick emits
/// `picked` with a JSON payload echoing the request token plus a `files`
/// array of `{path, name, content-type}` entries; a cancelled (or failed)
/// presentation emits `dismiss`. Picked URLs are kept accessible — security
/// scope started for document picks, temp copies for photo/camera picks —
/// until the `completion` property echoes the same request token or the
/// node is dropped. Only one request is in flight at a time: a token
/// arriving while another is retained is ignored.
///
/// `types` is a comma-separated list of UTIs; for `files` it becomes the
/// importer's allowed content types, for `photos`/`camera` it narrows the
/// media to image and/or movie. `camera` is iOS-only — on other platforms
/// the request is answered with `dismiss` without presenting anything.
struct LUIFilePickerView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    /// Picked files held until `completion` acknowledges the request token.
    private struct RetainedFile {
        let url: URL
        /// True when `startAccessingSecurityScopedResource` succeeded —
        /// only those URLs need `stopAccessingSecurityScopedResource`.
        let securityScoped: Bool
        /// True for temp copies we own (photo/camera captures) — deleted on release.
        let temporary: Bool
    }

    /// The request token currently being served: presenting, or picked and
    /// awaiting its `completion`. Cleared on cancel or completion match.
    @State private var operation: LUIWireValue?
    /// Whether the current presentation already produced a result —
    /// `.fileImporter` on iOS never invokes its completion on cancel, so a
    /// presentation ending with `handled == false` means the user cancelled.
    @State private var handled = false
    @State private var presented = false
    @State private var retained: [RetainedFile] = []
    #if canImport(PhotosUI)
    @State private var photoSelection: [PhotosPickerItem] = []
    #endif

    var body: some View {
        ForEach(model.visibleChildren, id: \.self) { childID in
            LUIAnyNodeView(nodeID: childID, backend: backend)
        }
        .fileImporter(
            isPresented: filesPresented,
            allowedContentTypes: allowedTypes,
            allowsMultipleSelection: allowsMultiple
        ) { result in
            handleFileImport(result)
        }
        #if canImport(PhotosUI)
        .modifier(
            LUIPhotosPickerModifier(
                presented: photosPresented,
                selection: $photoSelection,
                multiple: allowsMultiple,
                filter: photoFilter
            )
        )
        .onChange(of: photoSelection) { _, items in
            handlePhotoSelection(items)
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: cameraPresented) {
            LUICameraPicker(mediaTypes: cameraMediaTypes) { outcome in
                handleCamera(outcome)
            }
            .ignoresSafeArea()
        }
        #endif
        .onAppear {
            evaluate()
            evaluateCompletion()
        }
        .onChange(of: request) { evaluate() }
        .onChange(of: completion) { evaluateCompletion() }
        .onChange(of: presented) { _, isPresented in
            // Cancel detection for presentations without their own cancel
            // callback (iOS `.fileImporter`, `.photosPicker`). Both state
            // writes of a pick land in one transaction, so a non-empty
            // photoSelection means the selection handler will claim it.
            guard !isPresented, operation != nil, !handled else { return }
            #if canImport(PhotosUI)
            if source == "photos", !photoSelection.isEmpty { return }
            #endif
            finishCancelled()
        }
        .onDisappear { releaseRetained() }
    }

    // MARK: - properties

    private var request: LUIWireValue? {
        model.property(.request)
    }

    private var completion: LUIWireValue? {
        model.property(.completion)
    }

    private var source: String {
        model.property(.source)?.stringValue ?? "files"
    }

    private var allowsMultiple: Bool {
        model.property(.multiple)?.boolValue ?? false
    }

    private var enabled: Bool {
        model.isEnabled
    }

    private var typeIdentifiers: [String] {
        guard let raw = model.property(.types)?.stringValue else { return [] }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var allowedTypes: [UTType] {
        let parsed = typeIdentifiers.map { UTType($0) ?? UTType(importedAs: $0) }
        return parsed.isEmpty ? [.item] : parsed
    }

    #if canImport(PhotosUI)
    private var photoFilter: PHPickerFilter {
        guard model.property(.types)?.stringValue != nil else {
            return .any(of: [.images, .videos])
        }
        var filters: [PHPickerFilter] = []
        if allowedTypes.contains(where: { $0.conforms(to: .image) }) {
            filters.append(.images)
        }
        if allowedTypes.contains(where: { $0.conforms(to: .movie) }) {
            filters.append(.videos)
        }
        return filters.isEmpty ? .any(of: [.images, .videos]) : .any(of: filters)
    }
    #endif

    private var cameraMediaTypes: [UTType] {
        guard model.property(.types)?.stringValue != nil else {
            return [.image, .movie]
        }
        var media: [UTType] = []
        if allowedTypes.contains(where: { $0.conforms(to: .image) }) { media.append(.image) }
        if allowedTypes.contains(where: { $0.conforms(to: .movie) }) { media.append(.movie) }
        return media.isEmpty ? [.image] : media
    }

    // MARK: - presentation bindings

    private var filesPresented: Binding<Bool> {
        Binding(
            get: { presented && source == "files" },
            set: { if !$0 { presented = false } }
        )
    }

    #if canImport(PhotosUI)
    private var photosPresented: Binding<Bool> {
        Binding(
            get: { presented && source == "photos" },
            set: { if !$0 { presented = false } }
        )
    }
    #endif

    #if os(iOS)
    private var cameraPresented: Binding<Bool> {
        Binding(
            get: { presented && source == "camera" },
            set: { if !$0 { presented = false } }
        )
    }
    #endif

    // MARK: - state machine

    private func evaluate() {
        guard let request, operation == nil, enabled else { return }
        operation = request
        handled = false
        if source == "camera" {
            #if os(iOS)
            presented = true
            #else
            // No camera capture on macOS: answer the request with a cancel.
            finishCancelled()
            #endif
        } else {
            presented = true
        }
    }

    private func evaluateCompletion() {
        guard let completion, let operation, completion == operation else { return }
        releaseRetained()
        self.operation = nil
    }

    private func finishPicked(files: [RetainedFile]) {
        guard let operation else { return }
        handled = true
        retained = files
        emitPicked(token: operation, files: files)
        presented = false
    }

    private func finishCancelled() {
        handled = true
        releaseRetained()
        operation = nil
        try? backend.performDismiss(node: model.id)
    }

    private func releaseRetained() {
        for file in retained {
            if file.securityScoped {
                file.url.stopAccessingSecurityScopedResource()
            }
            if file.temporary {
                try? FileManager.default.removeItem(at: file.url)
            }
        }
        retained = []
    }

    // MARK: - results

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls) where !urls.isEmpty:
            let files = urls.map { url in
                RetainedFile(
                    url: url,
                    securityScoped: url.startAccessingSecurityScopedResource(),
                    temporary: false
                )
            }
            finishPicked(files: files)
        default:
            // macOS reports cancel here as a failure; on iOS the completion
            // is never called on cancel (see the `presented` onChange).
            if !handled { finishCancelled() }
        }
    }

    #if canImport(PhotosUI)
    private func handlePhotoSelection(_ items: [PhotosPickerItem]) {
        guard operation != nil, source == "photos", !items.isEmpty else { return }
        photoSelection = []
        Task {
            var files: [RetainedFile] = []
            for item in items {
                guard let file = await Self.importPhotoItem(item) else { continue }
                files.append(file)
            }
            if files.isEmpty {
                finishCancelled()
            } else {
                finishPicked(files: files)
            }
        }
    }

    private static func importPhotoItem(_ item: PhotosPickerItem) async -> RetainedFile? {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            return nil
        }
        let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "bin"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lui-picked-\(UUID().uuidString)")
            .appendingPathExtension(ext)
        guard (try? data.write(to: url)) != nil else { return nil }
        return RetainedFile(url: url, securityScoped: false, temporary: true)
    }
    #endif

    #if os(iOS)
    private func handleCamera(_ outcome: LUICameraPicker.Outcome) {
        switch outcome {
        case let .captured(url):
            finishPicked(files: [
                RetainedFile(url: url, securityScoped: false, temporary: true),
            ])
        case .cancelled:
            finishCancelled()
        }
    }
    #endif

    // MARK: - payload

    private func emitPicked(token: LUIWireValue, files: [RetainedFile]) {
        let request: Any = switch token {
        case let .string(value): value
        case let .int(value): NSNumber(value: value)
        case let .bool(value): NSNumber(value: value)
        case let .double(value): NSNumber(value: value)
        }
        let entries = files.map { file -> [String: Any] in
            [
                "path": file.url.path,
                "name": file.url.lastPathComponent,
                "content-type": Self.contentType(of: file.url),
            ]
        }
        let payload: [String: Any] = ["request": request, "files": entries]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        try? backend.performPicked(node: model.id, payload: json)
    }

    private static func contentType(of url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.contentTypeKey]),
           let mime = values.contentType?.preferredMIMEType {
            return mime
        }
        if let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return mime
        }
        return "application/octet-stream"
    }
}

#if canImport(PhotosUI)
/// The array-selection `photosPicker` overloads differ by `maxSelectionCount`
/// (non-optional `Int`), so branching happens inside a modifier.
private struct LUIPhotosPickerModifier: ViewModifier {
    let presented: Binding<Bool>
    @Binding var selection: [PhotosPickerItem]
    let multiple: Bool
    let filter: PHPickerFilter

    func body(content: Content) -> some View {
        if multiple {
            content.photosPicker(
                isPresented: presented,
                selection: $selection,
                matching: filter
            )
        } else {
            content.photosPicker(
                isPresented: presented,
                selection: $selection,
                maxSelectionCount: 1,
                matching: filter
            )
        }
    }
}
#endif

#if os(iOS)
/// `UIImagePickerController` wrapper for `source == "camera"`. Captures land
/// as temp files we own (released on `completion` or node drop), matching
/// the file-pick retention contract.
struct LUICameraPicker: UIViewControllerRepresentable {
    enum Outcome {
        case captured(URL)
        case cancelled
    }

    let mediaTypes: [UTType]
    let completion: (Outcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = mediaTypes.map(\.identifier)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate,
        UIImagePickerControllerDelegate {
        let completion: (Outcome) -> Void

        init(completion: @escaping (Outcome) -> Void) {
            self.completion = completion
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(.cancelled)
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = captureURL(info: info) {
                completion(.captured(url))
            } else {
                completion(.cancelled)
            }
        }

        private func captureURL(
            info: [UIImagePickerController.InfoKey: Any]
        ) -> URL? {
            if let url = info[.mediaURL] as? URL {
                return copy(url, extension: "mov")
            }
            if let url = info[.imageURL] as? URL {
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                return copy(url, extension: ext)
            }
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.9) {
                let url = tempURL(extension: "jpg")
                return (try? data.write(to: url)) != nil ? url : nil
            }
            return nil
        }

        private func copy(_ source: URL, extension ext: String) -> URL? {
            let destination = tempURL(extension: ext)
            return (try? FileManager.default.copyItem(at: source, to: destination))
                != nil ? destination : nil
        }

        private func tempURL(extension ext: String) -> URL {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("lui-picked-\(UUID().uuidString)")
                .appendingPathExtension(ext)
        }
    }
}
#endif
