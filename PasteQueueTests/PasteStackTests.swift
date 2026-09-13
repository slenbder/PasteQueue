@testable import PasteQueue
import AppKit
import XCTest

final class PasteStackTests: XCTestCase {
    override func setUpWithError() throws {
        // checkPasteboard() checks for an image on the real NSPasteboard.general directly
        // (by design — see PasteStack.checkPasteboard). Clear it so these text-path tests
        // aren't at the mercy of whatever image happens to be on the host's real clipboard.
        NSPasteboard.general.clearContents()
    }

    func testFIFOOrder() {
        let mock = MockPasteboard()
        let stack = PasteStack(pasteboard: mock)

        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()

        mock.changeCount = 2
        mock.stringValue = "B"
        stack.checkPasteboard()

        mock.changeCount = 3
        mock.stringValue = "C"
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.map(\.content), [.text("A"), .text("B"), .text("C")])

        stack.pasteNext()
        XCTAssertEqual(stack.queue.map(\.content), [.text("B"), .text("C")], "A should have been popped first")

        stack.pasteNext()
        XCTAssertEqual(stack.queue.map(\.content), [.text("C")], "B should have been popped second")

        stack.pasteNext()
        XCTAssertTrue(stack.queue.isEmpty, "C should have been popped third")
    }

    func testRemoveByIdDeletesTheCorrectDuplicate() {
        let mock = MockPasteboard()
        let stack = PasteStack(pasteboard: mock)

        mock.changeCount = 1
        mock.stringValue = "Считаю"
        stack.checkPasteboard()

        mock.changeCount = 2
        mock.stringValue = "Считаю"
        stack.checkPasteboard()

        mock.changeCount = 3
        mock.stringValue = "C"
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.count, 3)
        let middleID = stack.queue[1].id

        stack.remove(id: middleID)

        XCTAssertEqual(stack.queue.map(\.content), [.text("Считаю"), .text("C")], "should remove the entry at that specific id, not any entry with equal content")
        XCTAssertFalse(stack.queue.contains { $0.id == middleID })
    }

    func testEmptyStringsAreNotAddedToQueue() {
        let mock = MockPasteboard()
        let stack = PasteStack(pasteboard: mock)

        mock.changeCount = 1
        mock.stringValue = ""
        stack.checkPasteboard()

        XCTAssertTrue(stack.queue.isEmpty)
    }

    func testPasteNextOnEmptyQueueDoesNotCrash() {
        let stack = PasteStack(pasteboard: MockPasteboard())

        stack.pasteNext()
        stack.pasteNext()

        XCTAssertTrue(stack.queue.isEmpty)
    }

    func testClearEmptiesTheQueue() {
        let mock = MockPasteboard()
        let stack = PasteStack(pasteboard: mock)

        mock.changeCount = 1
        mock.stringValue = "A"
        stack.checkPasteboard()
        mock.changeCount = 2
        mock.stringValue = "B"
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.count, 2)

        stack.clear()

        XCTAssertTrue(stack.queue.isEmpty)
    }

    func testToggleCollectingDoesNotReAddStaleClipboardContentOnRestart() {
        let mock = MockPasteboard()
        mock.changeCount = 1
        mock.stringValue = "A"
        let stack = PasteStack(pasteboard: mock)

        stack.toggleCollecting()
        XCTAssertTrue(stack.isCollecting)

        mock.changeCount = 2
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.map(\.content), [.text("A")])

        stack.toggleCollecting()
        XCTAssertFalse(stack.isCollecting)

        // Re-enabling should resync lastChangeCount to the pasteboard's current state,
        // not re-add the same "A" that's already queued.
        stack.toggleCollecting()
        XCTAssertTrue(stack.isCollecting)
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.map(\.content), [.text("A")], "should not duplicate unchanged clipboard content")

        mock.changeCount = 3
        mock.stringValue = "B"
        stack.checkPasteboard()
        XCTAssertEqual(stack.queue.map(\.content), [.text("A"), .text("B")], "new content after restart should still be picked up")
    }

    func testMultipleImagesAreAllQueued() {
        // checkPasteboard() reads images from the real NSPasteboard.general directly, not
        // through PasteboardProviding (see the file-detection comment in PasteStack for why) —
        // so the mock here only drives changeCount; the actual payload goes on the real pasteboard,
        // same as a multi-selection copy from an app that vends more than one NSImage at once.
        func makeImage(_ color: NSColor) -> NSImage {
            let image = NSImage(size: NSSize(width: 4, height: 4))
            image.lockFocus()
            color.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 0, width: 4, height: 4)).fill()
            image.unlockFocus()
            return image
        }
        let image1 = makeImage(.red)
        let image2 = makeImage(.blue)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image1, image2])

        let mock = MockPasteboard()
        let stack = PasteStack(pasteboard: mock)

        mock.changeCount = 1
        stack.checkPasteboard()

        XCTAssertEqual(stack.queue.count, 2, "both images from a single multi-select copy should be queued, not just the first")
        for entry in stack.queue {
            guard case .image = entry.content else {
                XCTFail("expected every queued entry to be an image")
                return
            }
        }
    }
}
