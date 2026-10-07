import SwiftUI
import QuickLook
import AppKit

struct WindowSpec: Codable, Hashable {
    var url: URL
    var id = UUID()
}

// MARK: - Root

struct ContentView: View {
    @State private var state: ExplorerState

    init(start: URL) {
        let s = ExplorerState(start: start)
        Launch.apply(to: s)
        _state = State(initialValue: s)
    }

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 190, ideal: 240, max: 420)
        } detail: {
            VStack(spacing: 0) {
                CommandBar(state: state)
                Divider()
                HStack(spacing: 0) {
                    Group {
                        if state.viewMode == .details { DetailsList(state: state) } else { IconsGrid(state: state) }
                    }
                    .overlay { if state.isSearching { ProgressView().controlSize(.small) } }
                    if state.showDetailsPane { Divider(); DetailsPane(state: state) }
                }
                Divider()
                StatusBar(state: state)
            }
            .background(Theme.background)
        }
        .navigationTitle(state.title)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { state.goBack() } label: { Image(systemName: "arrow.left") }
                    .disabled(state.back.isEmpty).help("Back")
                Button { state.goForward() } label: { Image(systemName: "arrow.right") }
                    .disabled(state.forward.isEmpty).help("Forward")
                Button { state.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(!state.canGoUp).help("Up to parent folder")
            }
            ToolbarItem(placement: .principal) {
                AddressBar(state: state).frame(minWidth: 320, idealWidth: 560, maxWidth: .infinity)
            }
        }
        .searchable(text: $state.searchText, placement: .toolbar, prompt: "Search \(state.title)")
        .onChange(of: state.searchText) { state.search() }
        .onChange(of: state.showHidden) { state.search() }
        .focusedSceneValue(\.explorer, state)
        .quickLookPreview($state.quickLook, in: state.selectedItems.map(\.url))
        .sheet(isPresented: Binding(get: { state.propertiesTarget != nil }, set: { if !$0 { state.propertiesTarget = nil } })) {
            if let t = state.propertiesTarget { PropertiesView(state: state, urls: t) }
        }
        .alert("Explorer", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: { Text(state.errorMessage ?? "") }
        .background(WindowAccessor())
        .frame(minWidth: 800, minHeight: 460)
    }
}

// MARK: - Navigation pane

struct SidebarView: View {
    @Bindable var state: ExplorerState

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    struct Quick: Hashable { let title: String; let icon: String; let color: Color; let url: URL }
    private var defaults: [Quick] {
        let h = Self.home
        let all: [Quick] = [
            Quick(title: "Desktop", icon: "menubar.dock.rectangle", color: .blue, url: h.appending(path: "Desktop")),
            Quick(title: "Downloads", icon: "arrow.down.circle.fill", color: .green, url: h.appending(path: "Downloads")),
            Quick(title: "Documents", icon: "doc.text.fill", color: .gray, url: h.appending(path: "Documents")),
            Quick(title: "Pictures", icon: "photo.fill", color: .teal, url: h.appending(path: "Pictures")),
            Quick(title: "Music", icon: "music.note", color: .red, url: h.appending(path: "Music")),
            Quick(title: "Videos", icon: "film.fill", color: .purple, url: h.appending(path: "Movies")),
        ]
        return all.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .map { Quick(title: $0.title, icon: $0.icon, color: $0.color, url: $0.url.normalized) }
    }

    private var roots: [TreeNode] {
        var r = [TreeNode(url: Self.home, title: NSUserName()),
                 TreeNode(url: URL(filePath: "/"), title: "Macintosh HD")]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        r += vols.filter { $0.path != "/" }.map { TreeNode(url: $0) }
        return r
    }

    var body: some View {
        List(selection: Binding<URL?>(get: { state.current }, set: { if let u = $0 { state.go(to: u) } })) {
            Section {
                Label { Text("Home") } icon: { Image(systemName: "house.fill").foregroundStyle(Theme.accent) }
                    .tag(Self.home.normalized)
            }
            Section("Quick access") {
                ForEach(defaults, id: \.url) { q in
                    Label { Text(q.title) } icon: { Image(systemName: q.icon).foregroundStyle(q.color) }
                        .tag(q.url)
                        .dropDestination(for: URL.self) { urls, _ in state.drop(urls, into: q.url); return true }
                }
                ForEach(state.pinned.filter { p in !defaults.contains { $0.url == p } }, id: \.self) { url in
                    Label { Text(url.lastPathComponent) } icon: { Image(systemName: "folder.fill").foregroundStyle(Theme.folder) }
                        .tag(url)
                        .dropDestination(for: URL.self) { urls, _ in state.drop(urls, into: url); return true }
                        .contextMenu { Button("Unpin from Quick access") { state.togglePin(url) } }
                }
            }
            Section("This Mac") {
                OutlineGroup(roots, children: \.children) { node in
                    HStack(spacing: 6) {
                        if roots.contains(where: { $0.url == node.url }) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: node.url.path)).resizable().frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "folder.fill").foregroundStyle(Theme.folder)
                        }
                        Text(node.title).lineLimit(1)
                    }
                    .tag(node.url)
                    .dropDestination(for: URL.self) { urls, _ in state.drop(urls, into: node.url); return true }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.pane)
    }
}

// MARK: - Address bar

struct AddressBar: View {
    @Bindable var state: ExplorerState
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: "folder.fill").foregroundStyle(Theme.folder).padding(.leading, 8)
            if state.editingPath {
                TextField("Path", text: $state.pathText)
                    .textFieldStyle(.plain).focused($focused)
                    .onSubmit { state.goToPath(state.pathText) }
                    .onExitCommand { state.editingPath = false }
                    .onChange(of: focused) { if !focused { state.editingPath = false } }
                    .padding(.horizontal, 8)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(Array(state.breadcrumbs.enumerated()), id: \.offset) { i, c in
                                if i > 0 {
                                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(.secondary).padding(.horizontal, 2)
                                }
                                Button(c.title) { state.go(to: c.url) }
                                    .buttonStyle(.borderless).foregroundStyle(.primary).padding(.horizontal, 4)
                                    .id(i)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .onAppear { proxy.scrollTo(state.breadcrumbs.count - 1, anchor: .trailing) }
                    .onChange(of: state.current) { proxy.scrollTo(state.breadcrumbs.count - 1, anchor: .trailing) }
                }
                Spacer(minLength: 0)
            }
            Button { state.reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
                .buttonStyle(.borderless).padding(.trailing, 8).help("Refresh (⌘R)")
        }
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(state.editingPath ? Theme.accent : Theme.divider, lineWidth: state.editingPath ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { state.editingPath = true }
        .onChange(of: state.editingPath) { if state.editingPath { state.pathText = state.current.path; focused = true } }
    }
}

// MARK: - Command bar

struct CommandBar: View {
    let state: ExplorerState

    private func icon(_ name: String, _ help: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: name).frame(width: 22, height: 22) }
            .disabled(disabled).help(help)
    }

    var body: some View {
        let none = state.selection.isEmpty
        HStack(spacing: 2) {
            Menu {
                NewMenuItems(state: state)
            } label: { Label("New", systemImage: "plus.circle.fill").foregroundStyle(Theme.accent) }
            sep
            icon("scissors", "Cut (⌘X)", disabled: none) { state.cut() }
            icon("doc.on.doc", "Copy (⌘C)", disabled: none) { state.copy() }
            icon("doc.on.clipboard", "Paste (⌘V)", disabled: !state.hasClipboard) { state.paste() }
            icon("pencil.line", "Rename (F2)", disabled: state.selection.count != 1) { state.beginRename() }
            icon("square.and.arrow.up", "Share", disabled: none) { state.share() }
            icon("trash", "Delete (⌘⌫)", disabled: none) { state.trash() }
            sep
            Menu { SortMenuItems(state: state); Divider(); Menu("Group by") { GroupMenuItems(state: state) } }
                label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            Menu { ViewMenuItems(state: state) } label: { Label("View", systemImage: state.viewMode.systemImage) }
            if state.selection.count == 1, let u = state.selection.first, state.isArchive(u) {
                sep
                Button { state.extract(u) } label: { Label("Extract all", systemImage: "archivebox") }
            }
            Menu {
                Button("Select all") { state.selectAll() }
                Button("Select none") { state.selectNone() }
                Button("Invert selection") { state.invertSelection() }
                Divider()
                Button("Open in Terminal") { state.openInTerminal() }
                Button("Reveal in Finder") { state.reveal() }
                Button("Properties") { state.propertiesTarget = state.selection.isEmpty ? [state.current] : Array(state.selection) }
            } label: { Image(systemName: "ellipsis") }
            Spacer()
            Button { state.showDetailsPane.toggle() } label: {
                Image(systemName: "sidebar.right").foregroundStyle(state.showDetailsPane ? Theme.accent : .primary)
            }.help("Details pane (⌥⇧P)")
        }
        .buttonStyle(.borderless)
        .menuStyle(.borderlessButton)
        .labelStyle(.titleAndIcon)
        .font(.system(size: 12.5))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Theme.background)
    }

    private var sep: some View { Divider().frame(height: 18).padding(.horizontal, 4) }
}

// MARK: - Status bar

struct StatusBar: View {
    let state: ExplorerState

    var body: some View {
        let sel = state.selectedItems
        let total = sel.filter { !$0.isFolder }.reduce(Int64(0)) { $0 + $1.size }
        let n = state.displayed.count
        HStack(spacing: 10) {
            Text("\(n) item\(n == 1 ? "" : "s")")
            if !sel.isEmpty {
                Divider().frame(height: 12)
                Text("\(sel.count) item\(sel.count == 1 ? "" : "s") selected" + (total > 0 ? "  \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))" : ""))
            }
            Spacer()
            if !state.searchText.isEmpty { Text("Search results in \(state.title)") }
            Button { state.viewMode = .details } label: { Image(systemName: "list.bullet.below.rectangle") }
                .foregroundStyle(state.viewMode == .details ? Theme.accent : .secondary).help("Details")
            Button { state.viewMode = .large } label: { Image(systemName: "square.grid.2x2") }
                .foregroundStyle(state.viewMode == .large ? Theme.accent : .secondary).help("Large icons")
        }
        .buttonStyle(.borderless)
        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(Theme.background)
    }
}
