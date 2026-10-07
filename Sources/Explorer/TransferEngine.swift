import Foundation
import Darwin
import Observation

/// Thread-safe byte/progress counter shared between the copy thread and the UI.
final class ByteCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var done: Int64 = 0
    private var total: Int64 = 0
    private var lastInFile: Int64 = 0
    private var cancelled = false
    private var name = ""

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
    func setTotal(_ t: Int64) { lock.withLock { total = t } }
    func beginItem(_ n: String) { lock.withLock { name = n; lastInFile = 0 } }
    func beginFile() { lock.withLock { lastInFile = 0 } }
    func progress(copiedInFile c: Int64) { lock.withLock { done += max(0, c - lastInFile); lastInFile = c } }
    var snapshot: (fraction: Double, name: String) {
        lock.withLock { (total > 0 ? min(1, Double(done) / Double(total)) : 0, name) }
    }
}

@MainActor @Observable
final class TransferJob {
    let title: String
    let count: Int
    var fraction = 0.0
    var currentName = ""
    var visible = false          // shown only if the job takes a moment
    @ObservationIgnored let counter = ByteCounter()
    @ObservationIgnored let started = Date()

    init(title: String, count: Int) { self.title = title; self.count = count }
    func cancel() { counter.cancel() }
}

enum TransferEngine {
    /// Recursive copy via copyfile(3): preserves metadata, clones on APFS, reports progress, supports cancel.
    static func copy(_ src: URL, to dst: URL, counter: ByteCounter) throws {
        let st = copyfile_state_alloc()
        defer { copyfile_state_free(st) }
        let cb: copyfile_callback_t = { what, stage, state, _, _, ctx in
            guard let ctx else { return Int32(COPYFILE_CONTINUE) }
            let c = Unmanaged<ByteCounter>.fromOpaque(ctx).takeUnretainedValue()
            if c.isCancelled { return Int32(COPYFILE_QUIT) }
            if what == COPYFILE_RECURSE_FILE && stage == COPYFILE_START { c.beginFile() }
            if what == COPYFILE_COPY_DATA && stage == COPYFILE_PROGRESS, let state {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                c.progress(copiedInFile: Int64(copied))
            }
            return Int32(COPYFILE_CONTINUE)
        }
        copyfile_state_set(st, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(cb, to: UnsafeRawPointer.self))
        copyfile_state_set(st, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(counter).toOpaque())
        counter.beginFile()
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_CLONE)
        if copyfile(src.path, dst.path, st, flags) != 0 {
            if counter.isCancelled { throw CocoaError(.userCancelled) }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                          userInfo: [NSLocalizedDescriptionKey: "Couldn't copy “\(src.lastPathComponent)”: \(String(cString: strerror(errno)))."])
        }
    }

    static func totalBytes(_ urls: [URL]) -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        for u in urls {
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if v?.isDirectory == true {
                if let en = fm.enumerator(at: u, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
                    for case let f as URL in en {
                        let fv = try? f.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                        if fv?.isDirectory != true { total += Int64(fv?.fileSize ?? 0) }
                    }
                }
            } else { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }
}
