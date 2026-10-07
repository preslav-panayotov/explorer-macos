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
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { if let w = v.window { WindowTabs.configure(w) } }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Command-line options (handy for demos/screenshots):
/// `--path <dir> --view <mode> --group <key> --details-pane --hidden --select a,b`
enum Launch {
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

@main
struct ExplorerApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
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
