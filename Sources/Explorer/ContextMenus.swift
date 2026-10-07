import SwiftUI
import AppKit

// MARK: - Shared menu pieces (command bar + background menu)

struct ViewMenuItems: View {
    let state: ExplorerState
    var body: some View {
        ForEach(ViewMode.allCases) { m in
            Toggle(m.rawValue, isOn: Binding(get: { state.viewMode == m }, set: { _ in state.viewMode = m }))
        }
        Divider()
        Toggle("Details pane", isOn: Binding(get: { state.showDetailsPane }, set: { state.showDetailsPane = $0 }))
        Menu("Show") {
            Toggle("Hidden items", isOn: Binding(get: { state.showHidden }, set: { state.showHidden = $0 }))
        }
    }
}

struct SortMenuItems: View {
    let state: ExplorerState
    private let cols: [(String, PartialKeyPath<FileItem>)] = [
        ("Name", \FileItem.name), ("Date modified", \FileItem.modified),
        ("Type", \FileItem.kind), ("Size", \FileItem.sizeKey),
    ]
    var body: some View {
        ForEach(cols, id: \.0) { c in
            Toggle(c.0, isOn: Binding(get: { state.sortKey == c.1 },
                                      set: { _ in state.applySort(c.1, ascending: state.sortAscending) }))
        }
        Divider()
        Toggle("Ascending", isOn: Binding(get: { state.sortAscending },
                                          set: { _ in state.applySort(state.sortKey ?? \FileItem.name, ascending: true) }))
        Toggle("Descending", isOn: Binding(get: { !state.sortAscending },
                                           set: { _ in state.applySort(state.sortKey ?? \FileItem.name, ascending: false) }))
    }
}

struct GroupMenuItems: View {
    let state: ExplorerState
    var body: some View {
        ForEach(GroupKey.allCases) { g in
            Toggle(g.rawValue, isOn: Binding(get: { state.group == g }, set: { _ in state.group = g }))
        }
    }
}

struct NewMenuItems: View {
    let state: ExplorerState
    var body: some View {
        Button { state.newItem(.folder) } label: { Label("Folder", systemImage: "folder.badge.plus") }
        Button { state.newShortcutViaPicker() } label: { Label("Shortcut", systemImage: "arrow.uturn.right.square") }
        Divider()
        ForEach(NewKind.allCases.filter { $0 != .folder }, id: \.self) { k in
            Button(k.rawValue) { state.newItem(k) }
        }
    }
}

// MARK: - Context menu

struct FileContextMenu: View {
    let state: ExplorerState
    let sel: Set<URL>

    var body: some View {
        if sel.isEmpty { BackgroundMenu(state: state) } else { SelectionMenu(state: state, sel: sel) }
    }
}

/// Right-click on empty space (Windows 11: View, Sort by, Group by, Refresh, Undo, Paste, New, Properties…).
private struct BackgroundMenu: View {
    let state: ExplorerState

    var body: some View {
        Menu("View") { ViewMenuItems(state: state) }
        Menu("Sort by") { SortMenuItems(state: state) }
        Menu("Group by") { GroupMenuItems(state: state) }
        Button("Refresh") { state.reload() }
        Divider()
        Button(state.undoLabel ?? "Undo") { state.undo() }.disabled(state.undoLabel == nil)
        Divider()
        Button { state.paste() } label: { Label("Paste", systemImage: "doc.on.clipboard") }.disabled(!state.hasClipboard)
        Button("Paste shortcut") { state.pasteShortcuts() }.disabled(!state.hasClipboard)
        Divider()
        Button { state.openInTerminal() } label: { Label("Open in Terminal", systemImage: "terminal") }
        Button("Select all") { state.selectAll() }
        Button("Invert selection") { state.invertSelection() }
        Divider()
        Menu("New") { NewMenuItems(state: state) }
        Divider()
        Button("Properties") { state.propertiesTarget = [state.current] }
    }
}

/// Right-click on files/folders.
private struct SelectionMenu: View {
    let state: ExplorerState
    let sel: Set<URL>
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let list = sel.compactMap { state.item(for: $0) }
        let single = list.count == 1 ? list.first : nil
        let allFiles = list.allSatisfy { !$0.isFolder }

        // Windows 11 icon row: Cut · Copy · Rename · Share · Delete
        Button { state.cut(sel) } label: { Label("Cut", systemImage: "scissors") }
        Button { state.copy(sel) } label: { Label("Copy", systemImage: "doc.on.doc") }
        if single != nil { Button { state.beginRename(sel.first) } label: { Label("Rename", systemImage: "pencil") } }
        Button { state.share(sel) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { state.trash(sel) } label: { Label("Delete", systemImage: "trash") }
        Divider()

        Button("Open") { state.open(sel) }
        if let s = single {
            if s.isFolder {
                Button("Open in new tab") { WindowTabs.pendingParent = NSApp.keyWindow; openWindow(value: WindowSpec(url: s.url)) }
                Button("Open in new window") { openWindow(value: WindowSpec(url: s.url)) }
                Button(state.isPinned(s.url) ? "Unpin from Quick access" : "Pin to Quick access") { state.togglePin(s.url) }
            } else {
                OpenWithMenu(state: state, sel: sel, item: s)
            }
            if state.isArchive(s.url) { Button("Extract All…") { state.extract(s.url) } }
        }
        Button("Compress to ZIP file") { state.compress(sel) }
        Button("Copy as path") { state.copyPaths(sel) }
        Button("Properties") { state.propertiesTarget = Array(sel) }
        Divider()

        Menu("Show more options") {
            Button("Quick Look") { state.quickLook = sel.first }
            if allFiles { Button("Print") { state.printFiles(sel) } }
            if let s = single, state.isImage(s.url) {
                Button("Set as desktop background") { state.setDesktopBackground(s.url) }
                Button("Rotate right") { state.rotate(sel, degrees: 90) }
                Button("Rotate left") { state.rotate(sel, degrees: 270) }
            }
            Divider()
            Menu("Send to") {
                Button("Desktop") { state.transfer(Array(sel), into: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop"), move: false) }
                Button("Documents") { state.transfer(Array(sel), into: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Documents"), move: false) }
                Button("Compressed (zipped) folder") { state.compress(sel) }
                Button("Mail recipient") { state.mailRecipient(sel) }
                ForEach(state.sendToVolumes, id: \.self) { v in
                    Button(FileManager.default.displayName(atPath: v.path)) { state.transfer(Array(sel), into: v, move: false) }
                }
            }
            Button("Copy to folder…") { state.copyOrMove(sel, move: false) }
            Button("Move to folder…") { state.copyOrMove(sel, move: true) }
            Button("Create shortcut") { state.createShortcuts(sel) }
            Divider()
            Button("Open in Terminal") { state.openInTerminal(single?.isFolder == true ? single!.url : state.current) }
            Button("Reveal in Finder") { state.reveal(sel) }
            Divider()
            Button("Delete permanently…", role: .destructive) { state.deletePermanently(sel) }
        }
    }
}

private struct OpenWithMenu: View {
    let state: ExplorerState
    let sel: Set<URL>
    let item: FileItem

    var body: some View {
        Menu("Open with") {
            let def = NSWorkspace.shared.urlForApplication(toOpen: item.url)
            ForEach(state.openWithApps(item.url), id: \.self) { app in
                Button {
                    state.open(sel, with: app)
                } label: {
                    Text(FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
                         + (app == def ? " (default)" : ""))
                }
            }
            Divider()
            Button("Choose another app…") { state.chooseAppAndOpen(sel) }
        }
    }
}
