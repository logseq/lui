import Foundation

/// Demo-owned copies survive the picker's completion acknowledgement.
/// Files are copied on this actor, in selection order, without loading their
/// bytes into memory. Duplicate source paths reuse the currently staged copy.
actor GalleryComposerImports {
    struct Batch: Sendable {
        let payload: String
        let created: Set<String>
    }

    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("lui-composer-demo-\(UUID().uuidString)")
    private var sources: [String: String] = [:]
    private var pending: Set<String> = []
    private var latestRevision = -1
    private var currentPaths: Set<String> = []

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func stage(_ payload: String) -> Batch? {
        guard let data = payload.data(using: .utf8),
              var envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = envelope["files"] as? [[String: Any]] else { return nil }
        var files: [[String: Any]] = []
        var created: Set<String> = []
        var failures = envelope["failures"] as? Int ?? 0
        for var entry in entries {
            guard let path = entry["path"] as? String else { failures += 1; continue }
            if let copy = sources[path], FileManager.default.fileExists(atPath: copy) {
                entry["path"] = copy
                files.append(entry)
                continue
            }
            sources.removeValue(forKey: path)
            guard sources.count < 8 else { failures += 1; continue }
            let source = URL(fileURLWithPath: path)
            let destination = directory.appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(source.lastPathComponent)
            do {
                let values = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true, let size = values.fileSize,
                      size <= 50 * 1024 * 1024 else { failures += 1; continue }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: destination)
                let copied = try destination.resourceValues(forKeys: [.fileSizeKey])
                guard let copiedSize = copied.fileSize, copiedSize <= 50 * 1024 * 1024 else {
                    try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                    failures += 1
                    continue
                }
                sources[path] = destination.path
                created.insert(destination.path)
                pending.insert(destination.path)
                entry["path"] = destination.path
                files.append(entry)
            } catch {
                try? FileManager.default.removeItem(at: destination.deletingLastPathComponent())
                failures += 1
            }
        }
        envelope["files"] = files
        envelope["failures"] = failures
        guard let output = try? JSONSerialization.data(withJSONObject: envelope),
              let text = String(data: output, encoding: .utf8) else {
            retain(currentPaths, revision: latestRevision, finishing: created)
            return nil
        }
        return Batch(payload: text, created: created)
    }

    /// Pending copies are protected while the model has not yet consumed them.
    func retain(_ paths: Set<String>, revision: Int, finishing: Set<String> = []) {
        if revision >= latestRevision {
            latestRevision = revision
            currentPaths = paths
        }
        pending.subtract(finishing)
        let keep = currentPaths.union(pending)
        for (source, copy) in sources where !keep.contains(copy) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: copy).deletingLastPathComponent())
            sources.removeValue(forKey: source)
        }
    }

    func clear() {
        sources.removeAll()
        pending.removeAll()
        currentPaths.removeAll()
        try? FileManager.default.removeItem(at: directory)
    }
}
