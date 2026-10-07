import AppKit
import UniformTypeIdentifiers

extension ExplorerState {
    // MARK: New

    func newItem(_ kind: NewKind) {
        if kind == .folder { newFolder(); return }
        let (base, ext, data): (String, String, Data) = switch kind {
        case .text: ("New Text Document", "txt", Data())
        case .rtf: ("New Rich Text Document", "rtf", Data("{\\rtf1\\ansi }".utf8))
        case .markdown: ("New Markdown Document", "md", Data())
        case .html: ("New HTML Document", "html", Data("<!DOCTYPE html>\n<html><body></body></html>\n".utf8))
        default: ("New Compressed (zipped) Folder", "zip",
                  Data([0x50, 0x4B, 0x05, 0x06] + [UInt8](repeating: 0, count: 18)))
        }
        let url = Self.uniqueURL(in: current, name: "\(base).\(ext)", suffix: " (1)").normalized
        do {
            try data.write(to: url)
            record(.create([url]))
            reload()
            selection = [url]
            beginRename(url)
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Shortcuts (macOS aliases)

    @discardableResult
    func makeShortcut(to target: URL, in dir: URL) -> URL? {
        let dest = Self.uniqueURL(in: dir, name: target.lastPathComponent + " - Shortcut", suffix: " (1)")
        do {
            let data = try target.bookmarkData(options: .suitableForBookmarkFile)
            try URL.writeBookmarkData(data, to: dest)
            return dest.normalized
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    func createShortcuts(_ urls: Set<URL>? = nil) {
        let made = (urls ?? selection).compactMap { makeShortcut(to: $0, in: current) }
        if !made.isEmpty { record(.create(made)); reload(); selection = Set(made) }
    }

    func pasteShortcuts() {
        let src = clipboard.isEmpty ? (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []) : clipboard
        let made = src.compactMap { makeShortcut(to: $0, in: current) }
        if !made.isEmpty { record(.create(made)); reload(); selection = Set(made) }
    }

    func newShortcutViaPicker() {
        let p = NSOpenPanel()
        p.message = "Choose the item the shortcut should point to"
        p.canChooseDirectories = true
        guard p.runModal() == .OK, let u = p.url else { return }
        if let made = makeShortcut(to: u, in: current) { record(.create([made])); reload(); selection = [made] }
    }

    // MARK: Archives

    private func run(_ exe: String, _ args: [String], cwd: URL? = nil, then: @escaping @MainActor (Bool) -> Void) {
        Task.detached {
            let p = Process()
            p.executableURL = URL(filePath: exe)
            p.arguments = args
            p.currentDirectoryURL = cwd
            p.standardError = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            let ok = (try? p.run()) != nil && { p.waitUntilExit(); return p.terminationStatus == 0 }()
            await MainActor.run { then(ok) }
        }
    }

    func compress(_ urls: Set<URL>? = nil, into dir: URL? = nil) {
        let list = Array(urls ?? selection).sorted { $0.path < $1.path }
        guard let first = list.first else { return }
        let destDir = dir ?? current
        let name = list.count == 1 ? first.deletingPathExtension().lastPathComponent : "Archive"
        let dest = Self.uniqueURL(in: destDir, name: name + ".zip", suffix: " (1)")
        let parent = first.deletingLastPathComponent()
        let sameParent = list.allSatisfy { $0.deletingLastPathComponent() == parent }
        let args = ["-r", "-q", dest.path] + (sameParent ? list.map(\.lastPathComponent) : list.map(\.path))
        run("/usr/bin/zip", args, cwd: sameParent ? parent : nil) { ok in
            if ok { self.record(.create([dest.normalized])); self.reload(); self.selection = [dest.normalized] }
            else { self.errorMessage = "Couldn't compress the selection." }
        }
    }

    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "cpio", "iso"]
    func isArchive(_ u: URL) -> Bool { Self.archiveExts.contains(u.pathExtension.lowercased()) }

    func extract(_ u: URL) {
        let dest = Self.uniqueURL(in: u.deletingLastPathComponent(), name: u.deletingPathExtension().lastPathComponent, suffix: " (1)")
        do { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false) }
        catch { errorMessage = error.localizedDescription; return }
        let zip = u.pathExtension.lowercased() == "zip"
        run(zip ? "/usr/bin/ditto" : "/usr/bin/tar", zip ? ["-x", "-k", u.path, dest.path] : ["-xf", u.path, "-C", dest.path]) { ok in
            if ok { self.record(.create([dest.normalized])); self.reload(); self.selection = [dest.normalized] }
            else { try? FileManager.default.removeItem(at: dest); self.errorMessage = "Couldn't extract “\(u.lastPathComponent)”." }
        }
    }

    // MARK: Open with / share / send to

    func openWithApps(_ u: URL) -> [URL] {
        let apps = NSWorkspace.shared.urlsForApplications(toOpen: u)
        return Array(apps.prefix(14))
    }

    func open(_ urls: Set<URL>, with app: URL) {
        NSWorkspace.shared.open(Array(urls), withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    func chooseAppAndOpen(_ urls: Set<URL>) {
        let p = NSOpenPanel()
        p.directoryURL = URL(filePath: "/Applications")
        p.allowedContentTypes = [.application]
        p.message = "Choose an app to open the selection with"
        if p.runModal() == .OK, let app = p.url { open(urls, with: app) }
    }

    func share(_ urls: Set<URL>? = nil) {
        let list = Array(urls ?? selection)
        guard !list.isEmpty, let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: list)
        let mouse = view.window.map { view.convert($0.mouseLocationOutsideOfEventStream, from: nil) } ?? .zero
        picker.show(relativeTo: NSRect(origin: mouse, size: .init(width: 1, height: 1)), of: view, preferredEdge: .minY)
    }

    func mailRecipient(_ urls: Set<URL>) { NSSharingService(named: .composeEmail)?.perform(withItems: Array(urls)) }

    var sendToVolumes: [URL] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [])
            .filter { $0.path != "/" }
    }

    func copyOrMove(_ urls: Set<URL>, move: Bool) {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.canCreateDirectories = true
        p.prompt = move ? "Move" : "Copy"
        p.message = move ? "Move the selected items to…" : "Copy the selected items to…"
        guard p.runModal() == .OK, let dest = p.url else { return }
        transfer(Array(urls), into: dest.normalized, move: move)
    }

    // MARK: Network

    func isRemote(_ volume: URL) -> Bool {
        (try? volume.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false
    }

    /// Mounted network shares (SMB / NFS / AFP / WebDAV…).
    var networkVolumes: [URL] {
        _ = volumesVersion
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeIsLocalKey], options: [.skipHiddenVolumes]) ?? []
        return vols.filter { isRemote($0) }
    }

    func connectToServer() {
        let a = NSAlert()
        a.messageText = "Connect to server"
        a.informativeText = "Enter a server address, for example smb://server/share or nfs://host/path."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "smb://server/share"
        a.accessoryView = field
        a.addButton(withTitle: "Connect"); a.addButton(withTitle: "Cancel")
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: text), let scheme = url.scheme, ["smb", "nfs", "afp", "ftp", "http", "https", "vnc"].contains(scheme.lowercased()) else {
            errorMessage = "“\(text)” isn't a valid server address."; return
        }
        NSWorkspace.shared.open(url)   // macOS mounts the share; it then appears under Network
    }

    // MARK: Misc

    func openInTerminal(_ dir: URL? = nil) {
        NSWorkspace.shared.open([dir ?? current], withApplicationAt: URL(filePath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func isImage(_ u: URL) -> Bool { UTType(filenameExtension: u.pathExtension)?.conforms(to: .image) ?? false }

    func setDesktopBackground(_ u: URL) {
        do { for s in NSScreen.screens { try NSWorkspace.shared.setDesktopImageURL(u, for: s, options: [:]) } }
        catch { errorMessage = error.localizedDescription }
    }

    func rotate(_ urls: Set<URL>, degrees: Int) {
        for u in urls where isImage(u) {
            run("/usr/bin/sips", ["-r", String(degrees), u.path]) { _ in self.reload() }
        }
    }

    func printFiles(_ urls: Set<URL>) {
        run("/usr/bin/lpr", urls.map(\.path)) { ok in if !ok { self.errorMessage = "Couldn't print (no default printer?)." } }
    }
}
