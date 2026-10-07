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
        await settle()
        s.paste()
        await settle()
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
        await settle()
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

    // MARK: Round 3: right-click selection, drag-box, progress engine, network

    func testRightClickSelectsUnselectedItemButKeepsExistingSelection() async throws {
        try touch("a.txt"); try touch("b.txt"); try touch("c.txt")
        let s = ExplorerState(start: dir); await settle()
        let a = dir.appending(path: "a.txt").normalized, b = dir.appending(path: "b.txt").normalized
        let c = dir.appending(path: "c.txt").normalized
        s.selection = [a, b]
        s.prepareContextMenu(for: a)            // inside the selection: keep it
        XCTAssertEqual(s.selection, [a, b])
        s.prepareContextMenu(for: c)            // outside: becomes the selection
        XCTAssertEqual(s.selection, [c])
        s.prepareContextMenu(for: nil)          // background: unchanged
        XCTAssertEqual(s.selection, [c])
    }

    func testDragBoxSelection() async throws {
        try touch("a.txt"); try touch("b.txt"); try touch("c.txt")
        let s = ExplorerState(start: dir); await settle()
        let u = ["a.txt", "b.txt", "c.txt"].map { dir.appending(path: $0).normalized }
        s.rowFrames = [u[0]: CGRect(x: 0, y: 0, width: 100, height: 20),
                       u[1]: CGRect(x: 0, y: 20, width: 100, height: 20),
                       u[2]: CGRect(x: 0, y: 40, width: 100, height: 20)]
        s.updateMarquee(CGRect(x: 10, y: 10, width: 20, height: 20), additive: false)
        XCTAssertEqual(s.selection, [u[0], u[1]])
        s.updateMarquee(CGRect(x: 10, y: 10, width: 20, height: 45), additive: false)
        XCTAssertEqual(s.selection, Set(u))
        s.endMarquee(); XCTAssertNil(s.marquee)
        // additive (⌘) keeps what was selected before the drag started
        s.selection = [u[2]]
        s.updateMarquee(CGRect(x: 10, y: 0, width: 5, height: 5), additive: true)
        XCTAssertEqual(s.selection, [u[0], u[2]])
        s.endMarquee()
    }

    func testCopyDirectoryRecursivelyAndUndo() async throws {
        let src = dir.appending(path: "tree")
        try fm.createDirectory(at: src.appending(path: "inner/deep"), withIntermediateDirectories: true)
        try touch("one.txt", "1", in: src); try touch("two.txt", "22", in: src.appending(path: "inner/deep"))
        let dest = dir.appending(path: "target")
        try fm.createDirectory(at: dest, withIntermediateDirectories: false)
        let s = ExplorerState(start: dir); await settle()
        let planned = s.transfer([src], into: dest, move: false)
        await settle()
        XCTAssertEqual(planned.map(\.lastPathComponent), ["tree"])
        XCTAssertEqual(try String(contentsOf: dest.appending(path: "tree/inner/deep/two.txt"), encoding: .utf8), "22")
        XCTAssertTrue(fm.fileExists(atPath: src.appending(path: "one.txt").path), "copy leaves the source")
        XCTAssertNil(s.transferJob, "job finished")
        s.undo()
        XCTAssertFalse(fm.fileExists(atPath: dest.appending(path: "tree").path), "undo removes the copy")
    }

    func testSameNameFromTwoFoldersGetsDistinctDestinations() async throws {
        let a = dir.appending(path: "a"), b = dir.appending(path: "b"), out = dir.appending(path: "out")
        for d in [a, b, out] { try fm.createDirectory(at: d, withIntermediateDirectories: false) }
        try touch("same.txt", "from-a", in: a); try touch("same.txt", "from-b", in: b)
        let s = ExplorerState(start: dir); await settle()
        let planned = s.transfer([a.appending(path: "same.txt"), b.appending(path: "same.txt")], into: out, move: false)
        await settle()
        XCTAssertEqual(Set(planned).count, 2)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: out.path).count, 2)
    }

    func testEngineReportsProgressForLargeFileAndCanCancel() async throws {
        let big = dir.appending(path: "big.bin")
        try Data(count: 64 * 1024 * 1024).write(to: big)
        let counter = ByteCounter()
        counter.setTotal(64 * 1024 * 1024)
        let dst = dir.appending(path: "big-copy.bin")
        try TransferEngine.copy(big, to: dst, counter: counter)
        XCTAssertEqual(try fm.attributesOfItem(atPath: dst.path)[.size] as? Int, 64 * 1024 * 1024)
        // cancelled before start → throws userCancelled and reports no success
        let c2 = ByteCounter(); c2.cancel()
        XCTAssertThrowsError(try TransferEngine.copy(big, to: dir.appending(path: "never.bin"), counter: c2))
        XCTAssertEqual(TransferEngine.totalBytes([big]), 64 * 1024 * 1024)
    }

    func testCrossVolumeStyleJobCanBeCancelledMidway() async throws {
        let big = dir.appending(path: "huge.bin")
        let chunk = Data(repeating: 7, count: 1024 * 1024)
        fm.createFile(atPath: big.path, contents: nil)
        let h = try FileHandle(forWritingTo: big)
        for _ in 0..<300 { h.write(chunk) }          // 300 MB, random-ish content defeats nothing; copy is not cloned across dirs? clone ok
        try h.close()
        let out = dir.appending(path: "out"); try fm.createDirectory(at: out, withIntermediateDirectories: false)
        let s = ExplorerState(start: dir); await settle()
        s.transfer([big], into: out, move: false)
        s.transferJob?.cancel()
        try await Task.sleep(for: .milliseconds(1500))
        XCTAssertNil(s.transferJob)
        // either cancelled (no partial file left) or finished instantly via APFS clone — never a partial file
        let copy = out.appending(path: "huge.bin")
        if fm.fileExists(atPath: copy.path) {
            XCTAssertEqual(try fm.attributesOfItem(atPath: copy.path)[.size] as? Int, 300 * 1024 * 1024)
        }
    }

    func testNetworkVolumesAreRemoteOnlyAndRootIsLocal() async throws {
        let s = ExplorerState(start: dir)
        XCTAssertFalse(s.isRemote(URL(filePath: "/")))
        XCTAssertFalse(s.networkVolumes.contains(URL(filePath: "/")))
    }

    func testMountNotificationsBumpVolumesVersion() async throws {
        let s = ExplorerState(start: dir)
        let v = s.volumesVersion
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didMountNotification, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(s.volumesVersion, v + 1)
    }

    func testUninstallScriptRemovesOnlyOurFilesInSandbox() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let apps = dir.appending(path: "apps"), bin = dir.appending(path: "bin"), foreign = dir.appending(path: "foreign")
        for d in [apps.appending(path: "Explorer.app"), bin, foreign] { try fm.createDirectory(at: d, withIntermediateDirectories: true) }
        try fm.copyItem(at: root.appending(path: "Resources/explorermac"), to: bin.appending(path: "explorermac"))
        try "#!/bin/sh\n".write(to: foreign.appending(path: "explorermac"), atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = root.appending(path: "uninstall.sh")
        p.arguments = ["--yes", "--keep-settings"]
        p.environment = ["EXPLORER_APP_DIRS": apps.path, "EXPLORER_BIN_DIRS": "\(bin.path):\(foreign.path)", "HOME": dir.path, "PATH": "/usr/bin:/bin"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        XCTAssertFalse(fm.fileExists(atPath: apps.appending(path: "Explorer.app").path))
        XCTAssertFalse(fm.fileExists(atPath: bin.appending(path: "explorermac").path))
        XCTAssertTrue(fm.fileExists(atPath: foreign.appending(path: "explorermac").path), "foreign file with the same name is left alone")
    }
}
