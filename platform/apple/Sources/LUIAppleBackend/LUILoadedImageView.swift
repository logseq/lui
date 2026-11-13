import SwiftUI
import ImageIO

/// Keeps existing AsyncImage presentation. Hosts requesting intrinsic size
/// read source metadata only after AsyncImage successfully displays that URL.
struct LUILoadedImageView: View {
    let model: LUINodeModel
    let backend: LUIAppleBackend
    let url: URL
    var body: some View {
        let source = url.absoluteString
        let requested = backend.hostQueries.imageQueries.contains(model.id)
        AsyncImage(url: url) { image in
            image.resizable()
                .task(id: requested ? source : nil) {
                    guard requested, let size = await LUIImageDecode.naturalSize(url: url),
                          !Task.isCancelled else { return }
                    backend.reportLoadedImage(model: model, source: source, size: size)
                }
        } placeholder: {
            Color.clear
        }
        .onDisappear {
            if backend.hostQueries.images[model.id]?.model === model {
                backend.hostQueries.images[model.id] = nil
            }
        }
    }
}

enum LUIImageDecode {
    static func naturalSize(url: URL) async -> CGSize? {
        let task = Task.detached(priority: .userInitiated) { () -> CGSize? in
            let data: Data
            if url.isFileURL {
                guard let contents = try? Data(contentsOf: url) else { return nil }
                data = contents
            } else {
                guard let (contents, response) = try? await URLSession.shared.data(from: url),
                      (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
                data = contents
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
                  width.doubleValue > 0, height.doubleValue > 0 else { return nil }
            return CGSize(width: width.doubleValue, height: height.doubleValue)
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }
}
