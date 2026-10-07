import SwiftUI
import AppKit

/// Windows 11 File Explorer palette (light + dark).
enum Theme {
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let isDark = a.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255,
                           blue: CGFloat(v & 255) / 255, alpha: 1)
        })
    }
    static let background = dyn(0xFFFFFF, 0x202020)
    static let pane = dyn(0xF3F3F3, 0x2B2B2B)
    static let selection = dyn(0xCCE8FF, 0x0F3A5A)
    static let selectionInactive = dyn(0xE5E5E5, 0x383838)
    static let hover = dyn(0xE5F3FF, 0x2F2F2F)
    static let accent = dyn(0x0067C0, 0x4CC2FF)
    static let folder = dyn(0xFFC83D, 0xFFC83D)
    static let divider = dyn(0xE0E0E0, 0x3A3A3A)
    static let secondary = dyn(0x5C5C5C, 0xB0B0B0)
}

/// File/folder icon. Folders use the Windows-style yellow glyph.
struct ItemIcon: View {
    let item: FileItem
    var size: CGFloat = 18

    var body: some View {
        if item.isFolder {
            Image(systemName: "folder.fill")
                .resizable().aspectRatio(contentMode: .fit)
                .foregroundStyle(Theme.folder)
                .frame(width: size, height: size * 0.85)
                .frame(width: size, height: size)
        } else {
            Image(nsImage: IconCache.icon(for: item))
                .resizable().aspectRatio(contentMode: .fit).frame(width: size, height: size)
        }
    }
}
