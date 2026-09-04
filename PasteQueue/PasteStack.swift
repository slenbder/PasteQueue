import AppKit
import Combine
import os

private let logger = Logger(subsystem: "com.slenbder.pastequeue", category: "PasteStack")

/// Holds the FIFO queue of copied items and drives clipboard polling + synthetic paste.
/// FIFO by design: first thing you copy is the first thing that gets pasted.
final class PasteStack: ObservableObject {
    static let shared = PasteStack()

    private enum StopReason: String {
        case manualToggle
        case queueDrained
    }

    /// Soft cap so a runaway collecting session can't grow the queue forever.
    static let maxQueueSize = 99

    @Published var queue: [QueuedClipboardItem] = []
    @Published var isCollecting: Bool = false
    @Published var isAccessibilityTrusted: Bool

    private let pasteboard: PasteboardProviding
    private var pollTimer: Timer?
    private var lastChangeCount: Int

    // Own copies of captured files live here instead of referencing the original external
    // path. Some source paths (Photos.app derivatives, other sandboxed apps' containers)
    // only grant this process a read handle for the instant of the readObjects() call —
    // by the time pasteNext() hands the URL to another process via the pasteboard, the
    // sandbox extension needed for THAT process to read it can't be created, so
    // writeObjects() reports success while no bytes ever arrive. Copying the bytes into
    // our own Application Support directory at capture time sidesteps that entirely: the
    // file we hand out at paste time is one we actually own.
    private static let clipboardFilesDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupport.appendingPathComponent("PasteQueue/ClipboardFiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excludable = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludable.setResourceValues(resourceValues)
        return directory
    }()

    init(pasteboard: PasteboardProviding = NSPasteboard.general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        self.isAccessibilityTrusted = AXIsProcessTrusted()
        // A force-quit while the queue held file items leaves their copies orphaned on
        // disk with nothing left in memory to clean them up — sweep once at startup.
        Self.cleanupOrphanedFiles(referencedBy: queue)
    }

    func refreshAccessibilityStatus() {
        isAccessibilityTrusted = AXIsProcessTrusted()
    }

    func toggleCollecting() {
        isCollecting.toggle()
        logger.debug("toggleCollecting isCollecting=\(self.isCollecting, privacy: .public) queue.count=\(self.queue.count, privacy: .public)")
        if isCollecting {
            // Don't pick up whatever was already on the clipboard before we started.
            lastChangeCount = pasteboard.changeCount
            startPolling()
        } else {
            stopCollecting(reason: .manualToggle)
        }
    }

    private func stopCollecting(reason: StopReason) {
        isCollecting = false
        stopPolling()
        logger.debug("stopCollecting reason=\(reason.rawValue, privacy: .public) queue.count=\(self.queue.count, privacy: .public)")
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // Internal (not private) so tests can drive polling ticks directly instead of racing a real Timer.
    func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        let previousChangeCount = lastChangeCount
        lastChangeCount = pasteboard.changeCount
        logger.debug("checkPasteboard changeCount \(previousChangeCount, privacy: .public) -> \(self.lastChangeCount, privacy: .public)")

        guard queue.count < Self.maxQueueSize else { return }

        // File detection must run BEFORE image detection: copying a file in Finder (⌘C on a
        // file) puts a file URL (public.file-url) on the pasteboard, not raw image bytes. If we
        // ask readObjects(forClasses: [NSImage.self]) first, NSImage will still "succeed" against
        // that URL, but by falling back to the generic file-type icon instead of decoding the
        // file's actual content — so a copied jpg/png pastes back as a wrong, non-representative
        // icon bitmap. Catching the file URL first preserves the original bytes/format by
        // immediately copying the file into our own storage (see clipboardFilesDirectory) and
        // queuing a URL to that copy, not the external one.
        //
        // This intentionally catches ANY copied file, not just images — same raw pasteboard
        // mechanics apply whether it's a jpg or a txt/pdf/whatever else copied from Finder.
        //
        // Both this and the NSImage branch below go straight to the real pasteboard (not behind
        // PasteboardProviding) for the same reason: they're the one AppKit API that already knows
        // how to do this correctly without us hand-listing UTI types. Untested by design — same as
        // the write side, which has always talked to NSPasteboard.general directly.
        let fileURLs = (NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]) ?? []

        if !fileURLs.isEmpty {
            // Multi-selection copies (Finder, Photos) hand back every selected file in one
            // array — queue each as its own item, in the order the pasteboard gave them
            // (that's Finder's/Photos' own selection order; not ours to second-guess).
            for fileURL in fileURLs {
                guard queue.count < Self.maxQueueSize else { break }
                let itemID = UUID()
                let originalFilename = fileURL.lastPathComponent
                guard let storedURL = Self.copyToClipboardStorage(fileURL, itemID: itemID) else { continue }
                queue.append(QueuedClipboardItem(id: itemID, content: .file(url: storedURL, originalFilename: originalFilename)))
                logger.debug("queue append type=file queue.count=\(self.queue.count, privacy: .public)")
            }
        } else if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            queue.append(QueuedClipboardItem(content: .image(image)))
            logger.debug("queue append type=image queue.count=\(self.queue.count, privacy: .public)")
        } else if let str = pasteboard.string(forType: .string), !str.isEmpty {
            queue.append(QueuedClipboardItem(content: .text(str)))
            logger.debug("queue append type=text queue.count=\(self.queue.count, privacy: .public)")
        }
    }

    /// Copies a captured file's bytes into our own storage under a name derived from the
    /// queue item's own id (not the source filename) so two different source files that
    /// happen to share a name never collide on disk.
    private static func copyToClipboardStorage(_ sourceURL: URL, itemID: UUID) -> URL? {
        var destinationURL = clipboardFilesDirectory.appendingPathComponent(itemID.uuidString)
        let ext = sourceURL.pathExtension
        if !ext.isEmpty {
            destinationURL = destinationURL.appendingPathExtension(ext)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            print("[DEBUG capture] copy failed for \(sourceURL): \(error)")
            return nil
        }
    }

    private static func deleteStoredFile(for item: QueuedClipboardItem) {
        guard case .file(let url, _) = item.content else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func cleanupOrphanedFiles(referencedBy queue: [QueuedClipboardItem]) {
        let referencedNames = Set(queue.compactMap { item -> String? in
            guard case .file(let url, _) = item.content else { return nil }
            return url.lastPathComponent
        })
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: clipboardFilesDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        for fileURL in contents where !referencedNames.contains(fileURL.lastPathComponent) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func pasteNext() {
        guard !queue.isEmpty else { return }
        let item = queue.removeFirst()
        logger.debug("queue removeFirst queue.count=\(self.queue.count, privacy: .public)")

        // Stop collecting (which invalidates the poll timer) BEFORE writing to the pasteboard
        // below. Our own write bumps NSPasteboard's changeCount just like a real user copy
        // would; if the timer were still alive when that happens, the next 0.25s tick would
        // mistake our own paste-back for a fresh copy and re-queue the item we just popped.
        // Ordering this first closes that window for the "queue just drained" case.
        if queue.isEmpty {
            stopCollecting(reason: .queueDrained)
        }

        let pb = NSPasteboard.general
        let clearContentsResult = pb.clearContents()
        print("[DEBUG paste] clearContents changeCount: \(clearContentsResult)")
        switch item.content {
        case .text(let str):
            pb.setString(str, forType: .string)
        case .image(let image):
            pb.writeObjects([image])
        case .file(let url, _):
            print("[DEBUG paste] URL: \(url.path)")
            print("[DEBUG paste] fileExists: \(FileManager.default.fileExists(atPath: url.path))")
            let writeObjectsResult = pb.writeObjects([url as NSURL])
            print("[DEBUG paste] writeObjects success: \(writeObjectsResult)")
        }
        // Still collecting with items left in the queue means the timer is still running —
        // sync lastChangeCount to our own write's new changeCount too, otherwise the next
        // checkPasteboard() tick sees "changed" and re-queues this same item anyway.
        lastChangeCount = pb.changeCount

        simulateCommandV()

        // Deleting the stored copy right here (synchronously) would race the synthetic ⌘V:
        // that keystroke is only just now being posted to the event tap, and the receiving
        // app resolves the pasteboard's file-url flavor on its own schedule afterward — an
        // immediate delete could remove the file before that read happens, reintroducing the
        // exact "reports success but nothing pastes" failure this on-disk copy exists to fix.
        // A short delay gives that read time to complete before cleanup runs.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Self.deleteStoredFile(for: item)
        }
    }

    func clear() {
        for item in queue {
            Self.deleteStoredFile(for: item)
        }
        queue.removeAll()
        logger.debug("queue clear queue.count=\(self.queue.count, privacy: .public)")
    }

    /// Removes a single queue entry by its stable id, not by content match — two entries
    /// can carry equal content (e.g. the same text copied twice in a row), so matching by
    /// content could remove the wrong one of a pair of duplicates.
    func remove(id: UUID) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        let removed = queue.remove(at: index)
        Self.deleteStoredFile(for: removed)
        logger.debug("queue remove queue.count=\(self.queue.count, privacy: .public)")
    }

    /// Reorders queue entries in place (array move, not remove+insert) so ids stay stable —
    /// matches List's onMove(perform:) signature directly.
    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
        logger.debug("queue move queue.count=\(self.queue.count, privacy: .public)")
    }

    private func simulateCommandV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9 // ANSI 'V'

        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
