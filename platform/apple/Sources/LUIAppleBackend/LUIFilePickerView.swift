import SwiftUI
import UniformTypeIdentifiers
#if canImport(PhotosUI)
import PhotosUI
#endif

/// A picked file held until `completion` acknowledges the request token.
struct LUIRetainedFile {
    let url: URL
    /// True when `startAccessingSecurityScopedResource` succeeded —
    /// only those URLs need `stopAccessingSecurityScopedResource`.
    let securityScoped: Bool
    /// True for temp copies we own (photo/camera captures) — deleted on release.
    let temporary: Bool
}

/// A file-picker request in flight (`presenting`) or picked and awaiting
/// its `completion` (`awaitingCompletion`). Lives on the backend keyed by
/// node id, not in view state: SwiftUI may tear the view down while the
/// node stays mounted (tab switches, re-layout), and picked URLs must keep
/// their security scope until the app answers with `completion`.
struct LUIFilePickerOperation {
    enum Phase {
        case presenting
        case awaitingCompletion
    }

    let token: LUIWireValue
    var phase: Phase
    var files: [LUIRetainedFile] = []
}

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
/// (or a camera-less device) the request is answered with `dismiss`
/// without presenting anything.
struct LUIFilePickerView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend

    /// Whether the current presentation already produced a result —
    /// `.fileImporter` on iOS never invokes its completion on cancel, so a
    /// presentation ending with `handled == false` means the user cancelled.
    @State private var handled = false
    @State private var presented = false
    #if canImport(PhotosUI)
    @State private var photoSelection: [PhotosPickerItem] = []
    #endif

    private var operation: LUIFilePickerOperation? {
        backend.filePickerOperation(node: model.id)
    }

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
            evaluateCompletion()
            evaluate()
        }
        .onChange(of: request) { evaluate() }
        .onChange(of: completion) { evaluateCompletion() }
        .onChange(of: presented) { _, isPresented in
            // Cancel detection for presentations without their own cancel
            // callback (iOS `.fileImporter`, `.photosPicker`). The photo
            // selection handler marks `handled` before clearing
            // `photoSelection`, so reaching this point means no pick is
            // being imported.
            guard !isPresented, !handled,
                  operation?.phase == .presenting else { return }
            finishCancelled()
        }
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
        // A token equal to `completion` was already acknowledged — mounting
        // it must not re-present.
        guard let request, enabled, request != completion else { return }
        if let operation {
            // One request in flight: the same token re-presents a
            // presentation killed by a view teardown; any other token
            // waits for completion/cancel of the current one.
            guard operation.token == request else { return }
            if operation.phase == .presenting && !presented {
                present()
            }
            return
        }
        backend.setFilePickerOperation(
            node: model.id,
            LUIFilePickerOperation(token: request, phase: .presenting)
        )
        present()
    }

    private func present() {
        handled = false
        if source == "camera" {
            #if os(iOS)
            // Devices without a camera (simulator) throw an Obj-C
            // exception on `sourceType = .camera` — answer with dismiss.
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                presented = true
            } else {
                finishCancelled()
            }
            #else
            finishCancelled()
            #endif
        } else {
            presented = true
        }
    }

    private func evaluateCompletion() {
        guard let completion, let operation, completion == operation.token
        else { return }
        backend.clearFilePickerOperation(node: model.id)
        presented = false
    }

    private func finishPicked(files: [LUIRetainedFile]) {
        guard var operation else {
            // The operation was released (node dropped or completed) before
            // the pick landed — drop the files rather than leaking their
            // security scope / temp copies.
            backend.releaseFilePickerFiles(files)
            return
        }
        handled = true
        operation.phase = .awaitingCompletion
        operation.files = files
        backend.setFilePickerOperation(node: model.id, operation)
        emitPicked(token: operation.token, files: files)
        presented = false
    }

    private func finishCancelled() {
        handled = true
        presented = false
        backend.clearFilePickerOperation(node: model.id)
        try? backend.performDismiss(node: model.id)
    }

    // MARK: - results

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case let .success(urls) where !urls.isEmpty:
            let files = urls.map { url in
                LUIRetainedFile(
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
        // Mark handled before clearing the selection: `presented` flips to
        // false in the same update, and the cancel-detection hook must not
        // fire while the async import below is still running.
        handled = true
        photoSelection = []
        Task {
            var files: [LUIRetainedFile] = []
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

    /// Imports a PhotosPickerItem via a file-based representation — assets
    /// stream to disk instead of materializing as `Data` in memory.
    private static func importPhotoItem(_ item: PhotosPickerItem) async
        -> LUIRetainedFile?
    {
        guard let file = try? await item.loadTransferable(
            type: PhotoFile.self
        ) else {
            return nil
        }
        return LUIRetainedFile(url: file.url, securityScoped: false, temporary: true)
    }

    /// `FileRepresentation` delivers the asset as a temporary file URL;
    /// it is valid only inside the importing closure, so copy it into our
    /// own temp location there.
    private struct PhotoFile: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .data) { received in
                let ext = received.file.pathExtension
                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent("lui-picked-\(UUID().uuidString)")
                    .appendingPathExtension(ext.isEmpty ? "bin" : ext)
                try FileManager.default.copyItem(at: received.file, to: destination)
                return PhotoFile(url: destination)
            }
        }
    }
    #endif

    #if os(iOS)
    private func handleCamera(_ outcome: LUICameraPicker.Outcome) {
        switch outcome {
        case let .captured(url):
            finishPicked(files: [
                LUIRetainedFile(url: url, securityScoped: false, temporary: true),
            ])
        case .cancelled:
            finishCancelled()
        }
    }
    #endif

    // MARK: - payload

    private func emitPicked(token: LUIWireValue, files: [LUIRetainedFile]) {
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
