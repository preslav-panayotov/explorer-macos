import SwiftUI
import AppKit

// MARK: - Keyboard handling shared by all views

struct ListKeys: ViewModifier {
    let state: ExplorerState
    var columns: () -> Int = { 1 }
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .simultaneousGesture(TapGesture().onEnded { focused = true })
            .onAppear { focused = true }
            .onChange(of: state.current) { focused = true }
            .onChange(of: state.renameTarget) { if state.renameTarget == nil { focused = true } }
            .onKeyPress(phases: [.down, .repeat]) { p in
                guard state.renameTarget == nil else { return .ignored }
                let shift = p.modifiers.contains(.shift)
                if p.modifiers.contains(.command) { return .ignored }
                let cols = max(1, columns())
                switch p.key {
                case .upArrow: state.moveSelection(-cols, extend: shift)
                case .downArrow: state.moveSelection(cols, extend: shift)
                case .leftArrow where cols > 1: state.moveSelection(-1, extend: shift)
                case .rightArrow where cols > 1: state.moveSelection(1, extend: shift)
                case .home: state.moveSelection(-100_000, extend: shift)
                case .end: state.moveSelection(100_000, extend: shift)
                case .return: if !state.selection.isEmpty { state.open(state.selection) }
                case .space:
                    if let u = state.selection.first { state.quickLook = u } else { return .ignored }
                case .escape: state.selectNone()
                default:
                    guard !p.modifiers.contains(.control), !p.characters.isEmpty,
                          p.characters.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) })
                    else { return .ignored }
                    state.typeSelect(p.characters)
                }
                return .handled
            }
    }
}

/// Inline rename field (Explorer renames in place).
struct RenameField: View {
    let state: ExplorerState
    var alignment: TextAlignment = .leading
    @FocusState private var focus: Bool

    var body: some View {
        @Bindable var state = state
        TextField("", text: $state.renameText)
            .textFieldStyle(.plain)
            .multilineTextAlignment(alignment)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(Theme.background)
            .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1.5))
            .focused($focus)
            .onSubmit { state.commitRename() }
            .onExitCommand { state.renameTarget = nil }
            .onChange(of: focus) { if !focus { state.commitRename() } }
            .onAppear {
                focus = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let t = NSApp.keyWindow?.firstResponder as? NSTextView {
                        let base = (t.string as NSString).deletingPathExtension as NSString
                        t.setSelectedRange(NSRange(location: 0, length: base.length))
                    }
                }
            }
    }
}

/// Reports a row's frame (for drag-box selection) and hover (for right-click selection).
struct RowTracking: ViewModifier {
    let state: ExplorerState
    let url: URL
    @Binding var hover: Bool

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("content")) } action: { state.rowFrames[url] = $0 }
            .onHover { h in hover = h; state.noteHover(url, h) }
    }
}

/// Rubber-band selection rectangle + gesture for the empty background of a list.
struct MarqueeLayer: View {
    let state: ExplorerState

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { state.selectNone() }
                .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("content"))
                    .onChanged { v in
                        let r = CGRect(x: min(v.startLocation.x, v.location.x), y: min(v.startLocation.y, v.location.y),
                                       width: abs(v.location.x - v.startLocation.x), height: abs(v.location.y - v.startLocation.y))
                        state.updateMarquee(r, additive: NSEvent.modifierFlags.contains(.command))
                    }
                    .onEnded { _ in state.endMarquee() })
            if let r = state.marquee {
                Rectangle().fill(Theme.accent.opacity(0.18))
                    .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1))
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .allowsHitTesting(false)
            }
        }
    }
}

func clickModifiers() -> (shift: Bool, toggle: Bool) {
    let f = NSEvent.modifierFlags
    return (f.contains(.shift), f.contains(.command) || f.contains(.control))
}

// MARK: - Details

struct DetailsList: View {
    let state: ExplorerState

    var body: some View {
        let groups = state.groups
        VStack(spacing: 0) {
            HeaderRow(state: state)
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .top) {
                        MarqueeLayer(state: state)
                        LazyVStack(spacing: 0) {
                            ForEach(groups, id: \.title) { g in
                                if state.group != .none { GroupHeader(title: g.title, count: g.items.count) }
                                ForEach(g.items) { item in DetailRow(state: state, item: item).id(item.url) }
                            }
                        }
                    }
                    .coordinateSpace(name: "content")
                    .frame(maxWidth: .infinity, minHeight: 300)
                }
                .onChange(of: state.anchor) { if let a = state.anchor, state.marquee == nil { proxy.scrollTo(a) } }
            }
            .contextMenu { FileContextMenu(state: state, sel: []) }
        }
        .background(Theme.background)
        .modifier(ListKeys(state: state))
        .dropDestination(for: URL.self) { urls, _ in state.drop(urls, into: state.current); return true }
    }
}

struct GroupHeader: View {
    let title: String, count: Int
    var body: some View {
        HStack(spacing: 8) {
            Text("\(title) (\(count))").font(.system(size: 13)).foregroundStyle(Theme.accent)
            Rectangle().fill(Theme.divider).frame(height: 1)
        }
        .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
    }
}

private struct HeaderRow: View {
    let state: ExplorerState

    private func col(_ title: String, _ key: PartialKeyPath<FileItem>, _ width: Binding<CGFloat>,
                     trailing: Bool = false) -> some View {
        let active = state.sortOrder.first?.keyPath == key
        let asc = state.sortOrder.first?.order == .forward
        return HStack(spacing: 0) {
            Button { state.setSort(key) } label: {
                HStack(spacing: 4) {
                    if trailing { Spacer(minLength: 0) }
                    Text(title).font(.system(size: 12)).foregroundStyle(active ? Theme.accent : Theme.secondary)
                    if active { Image(systemName: asc ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.secondary) }
                    if !trailing { Spacer(minLength: 0) }
                }
                .padding(.horizontal, 8).frame(maxHeight: .infinity).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Rectangle().fill(Theme.divider).frame(width: 1).padding(.vertical, 4)
                .overlay(Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { if $0 { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1).onChanged { v in
                        width.wrappedValue = max(60, width.wrappedValue + v.translation.width)
                    }))
        }
        .frame(width: width.wrappedValue)
    }

    var body: some View {
        @Bindable var s = state
        HStack(spacing: 0) {
            col("Name", \FileItem.name, $s.nameW)
            col("Date modified", \FileItem.modified, $s.dateW)
            col("Type", \FileItem.kind, $s.kindW)
            col("Size", \FileItem.sizeKey, $s.sizeW, trailing: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, 10)
        .frame(height: 28)
        .background(Theme.background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.divider).frame(height: 1) }
    }
}

private struct DetailRow: View {
    let state: ExplorerState
    let item: FileItem
    @State private var hover = false

    var body: some View {
        let selected = state.selection.contains(item.url)
        let renaming = state.renameTarget == item.url
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ItemIcon(item: item, size: 18)
                if renaming { RenameField(state: state) }
                else { Text(item.name).lineLimit(1) }
            }
            .padding(.horizontal, 8).frame(width: state.nameW + 1, alignment: .leading)
            Text(item.modified.formatted(date: .numeric, time: .shortened))
                .padding(.horizontal, 8).frame(width: state.dateW + 1, alignment: .leading)
            Text(item.kind).lineLimit(1)
                .padding(.horizontal, 8).frame(width: state.kindW + 1, alignment: .leading)
            Text(item.sizeText).monospacedDigit()
                .padding(.horizontal, 8).frame(width: state.sizeW + 1, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12.5))
        .foregroundStyle(Color.primary.opacity(item.isHidden ? 0.55 : 1))
        .padding(.leading, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 4)
            .fill(selected ? Theme.selection : (hover ? Theme.hover : .clear))
            .padding(.horizontal, 4))
        .contentShape(Rectangle())
        .modifier(RowTracking(state: state, url: item.url, hover: $hover))
        .onTapGesture {
            let m = clickModifiers()
            state.click(item, shift: m.shift, toggle: m.toggle)
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded { state.open([item.url]) })
        .draggable(item.url)
        .contextMenu { FileContextMenu(state: state, sel: selected ? state.selection : [item.url]) }
    }
}

// MARK: - Icon / list grids

struct IconsGrid: View {
    let state: ExplorerState
    @State private var width: CGFloat = 800

    private var mode: ViewMode { state.viewMode }
    private var horizontal: Bool { mode == .small || mode == .list }
    private var cell: CGFloat {
        switch mode { case .extraLarge: 140; case .large: 112; case .medium: 90; case .small: 210; default: 240 }
    }
    private var columnCount: Int { max(1, Int((width - 24) / (cell + 6))) }

    var body: some View {
        let groups = state.groups
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .top) {
                    MarqueeLayer(state: state)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups, id: \.title) { g in
                            if state.group != .none { GroupHeader(title: g.title, count: g.items.count) }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: cell, maximum: cell), spacing: 6, alignment: .top)],
                                      alignment: .leading, spacing: horizontal ? 2 : 8) {
                                ForEach(g.items) { item in
                                    Cell(state: state, item: item, mode: mode).id(item.url)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .coordinateSpace(name: "content")
                .frame(maxWidth: .infinity, minHeight: 300)
            }
            .onChange(of: state.anchor) { if let a = state.anchor, state.marquee == nil { proxy.scrollTo(a) } }
        }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { width = g.size.width } })
        .background(Theme.background)
        .contextMenu { FileContextMenu(state: state, sel: []) }
        .modifier(ListKeys(state: state, columns: { columnCount }))
        .dropDestination(for: URL.self) { urls, _ in state.drop(urls, into: state.current); return true }
    }

    private struct Cell: View {
        let state: ExplorerState
        let item: FileItem
        let mode: ViewMode
        @State private var hover = false

        var body: some View {
            let selected = state.selection.contains(item.url)
            let renaming = state.renameTarget == item.url
            let horizontal = mode == .small || mode == .list
            Group {
                if horizontal {
                    HStack(spacing: 6) {
                        ItemIcon(item: item, size: 16)
                        if renaming { RenameField(state: state) } else { Text(item.name).lineLimit(1) }
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 6).frame(height: 24)
                } else {
                    VStack(spacing: 4) {
                        ThumbIcon(item: item, size: mode.iconSize)
                        if renaming { RenameField(state: state, alignment: .center) }
                        else { Text(item.name).lineLimit(2).multilineTextAlignment(.center) }
                    }.padding(6).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 12.5))
            .opacity(item.isHidden ? 0.55 : 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Theme.selection : (hover ? Theme.hover : .clear)))
            .contentShape(Rectangle())
            .modifier(RowTracking(state: state, url: item.url, hover: $hover))
            .onTapGesture {
                let m = clickModifiers()
                state.click(item, shift: m.shift, toggle: m.toggle)
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { state.open([item.url]) })
            .draggable(item.url)
            .contextMenu { FileContextMenu(state: state, sel: selected ? state.selection : [item.url]) }
        }
    }
}
