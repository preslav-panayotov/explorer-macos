import XCTest
@testable import Explorer

@MainActor
final class ExplorerTests: XCTestCase {
    var dir: URL!
    let fm = FileManager.default

    override func setUp() async throws {
        dir = fm.temporaryDirectory.appending(path: "explorer-test-\(UUID().uuidString)").resolvingSymlinksInPath().normalized
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try? fm.removeItem(at: dir) }

    private func touch(_ name: String, _ text: String = "x", in d: URL? = nil) throws {
        try text.write(to: (d ?? dir).appending(path: name), atomically: true, encoding: .utf8)
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(400)) }

    func testListingSortsFoldersFirst() async throws {
        try touch("b.txt"); try touch("a.txt")
        try fm.createDirectory(at: dir.appending(path: "zdir"), withIntermediateDirectories: false)
        let s = ExplorerState(start: dir); await settle()
        XCTAssertEqual(s.displayed.map(\.name), ["zdir", "a.txt", "b.txt"])
        s.setSort(\.name) // toggles to descending
        XCTAssertEqual(s.displayed.map(\.name), ["zdir", "b.txt", "a.txt"])
    }

    func testHiddenFilesToggle() async throws {
        try touch(".secret"); try touch("v.txt")
        let s = ExplorerState(start: dir); await settle()
        XCTAssertEqual(s.displayed.map(\.name), ["v.txt"])
        s.showHidden = true
        XCTAssertEqual(Set(s.displayed.map(\.name)), [".secret", "v.txt"])
    }

    func testNavigationBackForwardUp() async throws {
        let sub = dir.appending(path: "sub").normalized
        try fm.createDirectory(at: sub, withIntermediateDirectories: false)
        let s = ExplorerState(start: dir); await settle()
        s.go(to: sub)
        XCTAssertEqual(s.current, sub)
        s.goBack(); XCTAssertEqual(s.current, dir)
        s.goForward(); XCTAssertEqual(s.current, sub)
        s.goUp(); XCTAssertEqual(s.current, dir)
        XCTAssertEqual(s.selection, [sub])
    }

    func testNewFolderAndRename() async throws {
        let s = ExplorerState(start: dir); await settle()
        let f1 = s.newFolder()!; s.renameTarget = nil
        let f2 = s.newFolder()!; s.renameTarget = nil
        XCTAssertEqual(f1.lastPathComponent, "New folder")
        XCTAssertEqual(f2.lastPathComponent, "New folder (2)")
        s.beginRename(f1); s.renameText = "Photos"
        let r = s.commitRename()
        XCTAssertEqual(r?.lastPathComponent, "Photos")
        XCTAssertTrue(fm.fileExists(atPath: dir.appending(path: "Photos").path))
        s.beginRename(f2); s.renameText = "Photos"; s.commitRename()
        XCTAssertNotNil(s.errorMessage) // collision refused
    }

    func testCopyPasteWithCollisionNaming() async throws {
        try touch("doc.txt", "hello")
        let s = ExplorerState(start: dir); await settle()
        s.copy([dir.appending(path: "doc.txt")]); s.paste()
        s.paste()
        XCTAssertEqual(try String(contentsOf: dir.appending(path: "doc - Copy.txt"), encoding: .utf8), "hello")
        XCTAssertTrue(fm.fileExists(atPath: dir.appending(path: "doc - Copy (2).txt").path))
    }

    func testCutPasteMoves() async throws {
        let sub = dir.appending(path: "sub").normalized
        try fm.createDirectory(at: sub, withIntermediateDirectories: false)
        try touch("m.txt")
        let s = ExplorerState(start: dir); await settle()
        s.cut([dir.appending(path: "m.txt")])
        s.go(to: sub); s.paste()
        XCTAssertTrue(fm.fileExists(atPath: sub.appending(path: "m.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: dir.appending(path: "m.txt").path))
    }

    func testCannotMoveFolderIntoItself() async throws {
        let sub = dir.appending(path: "sub").normalized
        try fm.createDirectory(at: sub, withIntermediateDirectories: false)
        let s = ExplorerState(start: dir); await settle()
        s.transfer([dir], into: sub, move: false)
        XCTAssertNotNil(s.errorMessage)
    }

    func testTrash() async throws {
        try touch("gone.txt")
        let s = ExplorerState(start: dir); await settle()
        s.trash([dir.appending(path: "gone.txt")])
        XCTAssertFalse(fm.fileExists(atPath: dir.appending(path: "gone.txt").path))
    }

    func testRecursiveSearch() async throws {
        let sub = dir.appending(path: "deep/er")
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try touch("needle.md", in: sub); try touch("hay.txt")
        let s = ExplorerState(start: dir); await settle()
        s.searchText = "NEEDLE"; s.search()
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(s.displayed.map(\.name), ["needle.md"])
    }

    func testFileWatcherPicksUpExternalChange() async throws {
        let s = ExplorerState(start: dir); await settle()
        XCTAssertTrue(s.displayed.isEmpty)
        try touch("late.txt")
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(s.displayed.map(\.name), ["late.txt"])
    }

    func testBadPathReportsError() async throws {
        let s = ExplorerState(start: dir); await settle()
        s.goToPath("/definitely/not/here")
        XCTAssertNotNil(s.errorMessage)
        XCTAssertEqual(s.current, dir)
    }

    func testBreadcrumbs() async throws {
        let s = ExplorerState(start: URL(filePath: "/Users")); await settle()
        XCTAssertEqual(s.breadcrumbs.map(\.url.path), ["/", "/Users"])
    }

    // MARK: Windows-style features

    func testUndoRenameMoveTrashCreate() async throws {
        try touch("a.txt")
        let s = ExplorerState(start: dir); await settle()
        let a = dir.appending(path: "a.txt").normalized
        s.beginRename(a); s.renameText = "b.txt"; s.commitRename()
        XCTAssertEqual(s.undoLabel, "Undo Rename")
        s.undo()
        XCTAssertTrue(fm.fileExists(atPath: a.path))
        s.trash([a]); XCTAssertFalse(fm.fileExists(atPath: a.path))
        s.undo(); XCTAssertTrue(fm.fileExists(atPath: a.path), "trash undone")
        s.copy([a]); s.paste()
        XCTAssertTrue(fm.fileExists(atPath: dir.appending(path: "a - Copy.txt").path))
        s.undo(); XCTAssertFalse(fm.fileExists(atPath: dir.appending(path: "a - Copy.txt").path))
        XCTAssertNil(s.undoLabel)
    }

    func testNewItems() async throws {
        let s = ExplorerState(start: dir); await settle()
        for k in NewKind.allCases where k != .folder { s.newItem(k); s.renameTarget = nil }
        let names = Set(try fm.contentsOfDirectory(atPath: dir.path))
        XCTAssertTrue(names.isSuperset(of: ["New Text Document.txt", "New Markdown Document.md", "New HTML Document.html",
                                            "New Rich Text Document.rtf", "New Compressed (zipped) Folder.zip"]))
        s.newItem(.text); s.renameTarget = nil
        XCTAssertTrue(fm.fileExists(atPath: dir.appending(path: "New Text Document (1).txt").path))
    }

    func testCompressAndExtractRoundTrip() async throws {
        try touch("pay.txt", "payload")
        let s = ExplorerState(start: dir); await settle()
        s.compress([dir.appending(path: "pay.txt")])
        try await Task.sleep(for: .milliseconds(1500))
        let zip = dir.appending(path: "pay.zip")
        XCTAssertTrue(fm.fileExists(atPath: zip.path))
        try fm.removeItem(at: dir.appending(path: "pay.txt"))
        XCTAssertTrue(s.isArchive(zip))
        s.extract(zip)
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertEqual(try String(contentsOf: dir.appending(path: "pay/pay.txt"), encoding: .utf8), "payload")
    }

    func testShortcutIsResolvableAlias() async throws {
        try touch("t.txt")
        let s = ExplorerState(start: dir); await settle()
        s.createShortcuts([dir.appending(path: "t.txt")])
        let alias = dir.appending(path: "t.txt - Shortcut")
        let data = try URL.bookmarkData(withContentsOf: alias)
        var stale = false
        let r = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale)
        XCTAssertEqual(r.lastPathComponent, "t.txt")
    }

    func testGroupingBySizeAndKeyboardSelection() async throws {
        try touch("empty.txt", ""); try touch("tiny.txt", "abc")
        try fm.createDirectory(at: dir.appending(path: "d"), withIntermediateDirectories: false)
        let s = ExplorerState(start: dir); await settle()
        s.group = .size
        XCTAssertEqual(s.groups.map(\.title), ["Unspecified", "Empty", "Tiny (0 – 16 KB)"])
        s.group = .none
        s.moveSelection(1, extend: false)
        XCTAssertEqual(s.selection.count, 1)
        s.moveSelection(1, extend: true)
        XCTAssertEqual(s.selection.count, 2)
        s.invertSelection(); XCTAssertEqual(s.selection.count, 1)
        s.selectAll(); XCTAssertEqual(s.selection.count, 3)
        s.typeSelect("t"); XCTAssertEqual(s.selectedItems.map(\.name), ["tiny.txt"])
    }

    func testPinsPersist() async throws {
        let s = ExplorerState(start: dir); await settle()
        s.togglePin(dir); XCTAssertTrue(s.isPinned(dir))
        s.togglePin(dir); XCTAssertFalse(s.isPinned(dir))
    }

    func testPropertiesAggregates() async throws {
        let sub = dir.appending(path: "p")
        try fm.createDirectory(at: sub, withIntermediateDirectories: false)
        try touch("one.txt", "12345", in: sub)
        let info = PropInfo.compute([sub])
        XCTAssertEqual(info.files, 1); XCTAssertEqual(info.size, 5)
    }

    // MARK: explorermac command + thumbnails

    func testParseExplorermacURL() throws {
        var c = URLComponents(string: "explorermac://open")!
        c.queryItems = [.init(name: "path", value: dir.path), .init(name: "select", value: "a b.txt")]
        let r = try XCTUnwrap(Launch.parse(c.url!))
        XCTAssertEqual(r.dir, dir)
        XCTAssertEqual(r.select, "a b.txt")
        XCTAssertNil(Launch.parse(URL(string: "explorermac://open?path=/definitely/not/here")!))
        XCTAssertNil(Launch.parse(URL(string: "https://example.com")!))
    }

    func testParseFileURLs() throws {
        try touch("f.txt")
        let d = try XCTUnwrap(Launch.parse(dir))
        XCTAssertEqual(d.dir, dir); XCTAssertNil(d.select)
        let f = try XCTUnwrap(Launch.parse(dir.appending(path: "f.txt")))
        XCTAssertEqual(f.dir, dir); XCTAssertEqual(f.select, "f.txt")
    }

    func testLowercasePathIsCanonicalised() throws {
        try XCTSkipUnless(fm.fileExists(atPath: "/users"), "case-sensitive volume")
        var c = URLComponents(string: "explorermac://open")!
        c.queryItems = [.init(name: "path", value: "/users/")]
        XCTAssertEqual(Launch.parse(c.url!)?.dir.path, "/Users")
    }

    private func runCLI(_ args: [String]) throws -> (status: Int32, err: String) {
        let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Resources/explorermac")
        let p = Process(); p.executableURL = script; p.arguments = args
        let e = Pipe(); p.standardError = e; p.standardOutput = Pipe()
        try p.run(); p.waitUntilExit()
        return (p.terminationStatus, String(decoding: e.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))
    }

    func testCLIScriptRejectsMissingPathAndShowsHelp() throws {
        let bad = try runCLI(["/definitely/not/here"])
        XCTAssertEqual(bad.status, 1)
        XCTAssertTrue(bad.err.contains("no such file or directory"))
        XCTAssertEqual(try runCLI(["--help"]).status, 0)
    }

    func testThumbnailGeneratedForImagesOnly() async throws {
        let png = dir.appending(path: "pic.png")
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: png)
        try touch("plain.txt")
        XCTAssertTrue(ThumbCache.supportsThumbnail(png))
        XCTAssertFalse(ThumbCache.supportsThumbnail(dir.appending(path: "plain.txt")))
        let item = try XCTUnwrap(FileItem(url: png))
        let img = await ThumbCache.shared.thumbnail(for: item, points: 64)
        XCTAssertNotNil(img)
        XCTAssertNotNil(ThumbCache.shared.cached(item, points: 64), "second request is served from cache")
    }
}
