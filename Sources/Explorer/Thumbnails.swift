import SwiftUI
import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Async Quick Look thumbnails (images, videos, PDFs) with an in-memory cache.
@MainActor
final class ThumbCache {
    static let shared = ThumbCache()
    private let cache = NSCache<NSString, NSImage>()
    private var inflight: [String: Task<NSImage?, Never>] = [:]

    static func supportsThumbnail(_ url: URL) -> Bool {
        guard let t = UTType(filenameExtension: url.pathExtension) else { return false }
        return t.conforms(to: .image) || t.conforms(to: .movie) || t.conforms(to: .pdf)
    }

    func cached(_ item: FileItem, points: CGFloat) -> NSImage? { cache.object(forKey: key(item, points) as NSString) }

    func thumbnail(for item: FileItem, points: CGFloat) async -> NSImage? {
        let k = key(item, points)
        if let hit = cache.object(forKey: k as NSString) { return hit }
        if let t = inflight[k] { return await t.value }
        let url = item.url
        let task = Task { () -> NSImage? in
            let req = QLThumbnailGenerator.Request(
                fileAt: url, size: CGSize(width: points, height: points),
                scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
            return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: req).nsImage
        }
        inflight[k] = task
        let img = await task.value
        inflight[k] = nil
        if let img { cache.setObject(img, forKey: k as NSString) }
        return img
    }

    private func key(_ item: FileItem, _ points: CGFloat) -> String {
        "\(item.url.path)|\(item.modified.timeIntervalSince1970)|\(item.size)|\(Int(points))"
    }
}

/// Icon that upgrades itself to a real thumbnail for images, videos and PDFs.
struct ThumbIcon: View {
    let item: FileItem
    let size: CGFloat
    @State private var thumb: NSImage?

    var body: some View {
        Group {
            if let thumb {
                Image(nsImage: thumb)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            } else {
                ItemIcon(item: item, size: size)
            }
        }
        .task(id: "\(item.id)|\(item.modified)|\(Int(size))") {
            guard !item.isFolder, ThumbCache.supportsThumbnail(item.url) else { thumb = nil; return }
            thumb = ThumbCache.shared.cached(item, points: size)
            if thumb == nil { thumb = await ThumbCache.shared.thumbnail(for: item, points: size) }
        }
    }
}
