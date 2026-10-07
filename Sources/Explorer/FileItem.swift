import AppKit
import UniformTypeIdentifiers

extension URL {
    /// Canonical form (standardized, no trailing slash) so URLs compare equal.
    var normalized: URL { URL(filePath: standardizedFileURL.path, directoryHint: .notDirectory) }
}

struct FileItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isHidden: Bool
    let size: Int64
    let modified: Date
    let kind: String

    /// A folder you can navigate into (packages such as .app open like files).
    var isFolder: Bool { isDirectory && !isPackage }
    var sizeKey: Int64 { isFolder ? -1 : size }
    var sizeText: String {
        isFolder ? "" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey,
        .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
    ]

    init?(url: URL) {
        guard var v = try? url.resourceValues(forKeys: Set(Self.keys)) else { return nil }
        if v.isSymbolicLink == true,
           let r = try? url.resolvingSymlinksInPath().resourceValues(forKeys: Set(Self.keys)) {
            v = r
        }
        self.url = url.normalized
        name = url.lastPathComponent
        isDirectory = v.isDirectory ?? false
        isPackage = v.isPackage ?? false
        isHidden = v.isHidden ?? name.hasPrefix(".")
        size = Int64(v.fileSize ?? 0)
        modified = v.contentModificationDate ?? .distantPast
        kind = v.localizedTypeDescription ?? (isDirectory ? "Folder" : "File")
    }

    static func list(_ dir: URL) throws -> [FileItem] {
        try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])
            .compactMap { FileItem(url: $0) }
    }
}

@MainActor
enum IconCache {
    private static var cache: [String: NSImage] = [:]
    private static let folder = NSWorkspace.shared.icon(for: .folder)

    static func icon(for item: FileItem) -> NSImage {
        if item.isFolder { return folder }
        let ext = item.url.pathExtension.lowercased()
        if item.isPackage || ext.isEmpty { return NSWorkspace.shared.icon(forFile: item.url.path) }
        if let i = cache[ext] { return i }
        let i = NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
        cache[ext] = i
        return i
    }
}

/// Lazy node for the navigation-pane folder tree.
struct TreeNode: Identifiable, Hashable {
    let url: URL
    let title: String
    var id: URL { url }

    init(url: URL, title: String? = nil) {
        self.url = url.normalized
        self.title = title ?? FileManager.default.displayName(atPath: url.path)
    }

    /// Sub-folders, or nil when there are none (hides the disclosure arrow).
    var children: [TreeNode]? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles]) else { return nil }
        let dirs = urls.filter {
            let v = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return v?.isDirectory == true && v?.isPackage != true
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        .map { TreeNode(url: $0, title: $0.lastPathComponent) }
        return dirs.isEmpty ? nil : dirs
    }
}
