import SwiftUI
import AppKit

struct ExplorerKey: FocusedValueKey { typealias Value = ExplorerState }
extension FocusedValues {
    var explorer: ExplorerState? {
        get { self[ExplorerKey.self] }
        set { self[ExplorerKey.self] = newValue }
    }
}

/// "Open in new tab": opens a window then attaches it to the current one as a native macOS tab.
@MainActor
enum WindowTabs {
    static var pendingParent: NSWindow?
    private static var registry: [(state: ExplorerState, window: NSWindow)] = []

    static func register(_ s: ExplorerState, _ w: NSWindow) {
        registry.removeAll { $0.window === w || !$0.window.isVisible && $0.window.contentView == nil }
        registry.append((s, w))
    }

    /// When the app is cold-started by `explorermac <dir>`, SwiftUI also opens its default home window.
    /// Close those untouched default windows once the requested folder window exists.
    static func closeUntouchedDefaults(except keep: ExplorerState) {
        let home = FileManager.default.homeDirectoryForCurrentUser.normalized
        for (s, w) in registry where s !== keep && s.back.isEmpty && s.current == home && s.selection.isEmpty {
            w.close()
        }
    }
    static func configure(_ w: NSWindow) {
        w.tabbingIdentifier = "explorer"
        if let p = pendingParent, p !== w {
            pendingParent = nil
            p.addTabbedWindow(w, ordered: .above)
            w.makeKeyAndOrderFront(nil)
        }
    }
}

struct WindowAccessor: NSViewRepresentable {
    let state: ExplorerState
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { WindowTabs.configure(w); WindowTabs.register(state, w); state.installRightClickMonitor(for: w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Command-line options (handy for demos/screenshots):
/// `--path <dir> --view <mode> --group <key> --details-pane --hidden --select a,b`
enum Launch {
    static let launchTime = Date()
    static func value(_ key: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: key), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static var path: URL? { value("--path").map { URL(filePath: NSString(string: $0).expandingTildeInPath) } }

    @MainActor static func apply(to s: ExplorerState) {
        if let v = value("--view"), let m = ViewMode.allCases.first(where: { $0.rawValue.lowercased() == v.lowercased() }) { s.viewMode = m }
        if let g = value("--group"), let k = GroupKey.allCases.first(where: { $0.rawValue.lowercased() == g.lowercased() }) { s.group = k }
        if CommandLine.arguments.contains("--details-pane") { s.showDetailsPane = true }
        if CommandLine.arguments.contains("--hidden") { s.showHidden = true }
        if let names = value("--select")?.split(separator: ",").map(String.init) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(700))
                s.selection = Set(s.displayed.filter { names.contains($0.name) }.map(\.url))
            }
        }
    }
}

extension Launch {
    /// Parses `explorermac://open?path=…&select=…` or a plain `file://` URL.
    static func parse(_ url: URL) -> (dir: URL, select: String?)? {
        if url.isFileURL {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }
            return isDir.boolValue ? (canonical(url), nil) : (canonical(url.deletingLastPathComponent()), url.lastPathComponent)
        }
        guard url.scheme == "explorermac",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let path = items.first(where: { $0.name == "path" })?.value else { return nil }
        let dir = URL(filePath: path)
        guard FileManager.default.fileExists(atPath: dir.path) else { return nil }
        return (canonical(dir), items.first(where: { $0.name == "select" })?.value)
    }

    /// Fixes letter-case typed in the terminal (`/users` → `/Users`) without resolving symlinks.
    static func canonical(_ url: URL) -> URL {
        let n = url.normalized
        if let c = (try? n.resourceValues(forKeys: [.canonicalPathKey]))?.canonicalPath,
           c.lowercased() == n.path.lowercased() { return URL(filePath: c).normalized }
        return n
    }
}

@main
struct ExplorerApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        _ = Launch.launchTime
        if CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
        if CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
    }

    var body: some Scene {
        WindowGroup("Explorer", for: WindowSpec.self) { $spec in
            ContentView(start: spec.url)
        } defaultValue: {
            WindowSpec(url: Launch.path ?? FileManager.default.homeDirectoryForCurrentUser)
        }
        .defaultSize(width: 1180, height: 740)
        .commands { ExplorerCommands() }
    }
}

@MainActor
private func textResponder() -> NSText? { NSApp.keyWindow?.firstResponder as? NSText }

struct ExplorerCommands: Commands {
    @FocusedValue(\.explorer) private var ex: ExplorerState?
    @Environment(\.openWindow) private var openWindow

    private let f2 = KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!))
    private var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Install ‘explorermac’ Command…") { CLIInstaller.install() }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(value: WindowSpec(url: ex?.current ?? home)) }.keyboardShortcut("n")
            Button("New Tab") {
                WindowTabs.pendingParent = NSApp.keyWindow
                openWindow(value: WindowSpec(url: ex?.current ?? home))
            }.keyboardShortcut("t")
            Button("New Folder") { ex?.newFolder() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Divider()
            Button("Properties") { if let e = ex { e.propertiesTarget = e.selection.isEmpty ? [e.current] : Array(e.selection) } }
                .keyboardShortcut(.return, modifiers: .option)
        }
        CommandGroup(replacing: .undoRedo) {
            Button(ex?.undoLabel ?? "Undo") {
                if textResponder() != nil { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { ex?.undo() }
            }.keyboardShortcut("z")
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { if let t = textResponder() { t.cut(nil) } else { ex?.cut() } }.keyboardShortcut("x")
            Button("Copy") { if let t = textResponder() { t.copy(nil) } else { ex?.copy() } }.keyboardShortcut("c")
            Button("Paste") { if let t = textResponder() { t.paste(nil) } else { ex?.paste() } }.keyboardShortcut("v")
            Button("Select All") { if let t = textResponder() { t.selectAll(nil) } else { ex?.selectAll() } }.keyboardShortcut("a")
            Button("Invert Selection") { ex?.invertSelection() }.keyboardShortcut("i", modifiers: [.command, .shift])
            Divider()
            Button("Rename") { ex?.beginRename() }.keyboardShortcut(f2, modifiers: [])
            Button("Move to Trash") { ex?.trash() }.keyboardShortcut(.delete, modifiers: .command)
            Button("Delete Permanently…") { ex?.deletePermanently() }.keyboardShortcut(.delete, modifiers: .shift)
            Button("Delete") {
                if textResponder() != nil { NSApp.sendAction(#selector(NSResponder.deleteBackward(_:)), to: nil, from: nil) }
                else { ex?.trash() }
            }.keyboardShortcut(.delete, modifiers: [])
        }
        CommandMenu("Go") {
            Button("Back") { ex?.goBack() }.keyboardShortcut("[")
            Button("Forward") { ex?.goForward() }.keyboardShortcut("]")
            Button("Up") { ex?.goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
            Button("Refresh") { ex?.reload() }.keyboardShortcut("r")
            Divider()
            Button("Address Bar") { ex?.editingPath = true }.keyboardShortcut("l")
            Button("Home") { ex?.go(to: home) }.keyboardShortcut("h", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Menu("Layout") {
                ForEach(Array(ViewMode.allCases.enumerated()), id: \.element) { i, m in
                    Button(m.rawValue) { ex?.viewMode = m }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
            }
            Button("Details Pane") { ex?.showDetailsPane.toggle() }.keyboardShortcut("p", modifiers: [.option, .shift])
            Button("Hidden Items") { ex?.showHidden.toggle() }.keyboardShortcut(".", modifiers: [.command, .shift])
        }
    }
}
