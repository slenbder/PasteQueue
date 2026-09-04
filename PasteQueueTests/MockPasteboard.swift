@testable import PasteQueue
import AppKit

final class MockPasteboard: PasteboardProviding {
    var changeCount: Int = 0
    var stringValue: String?

    func string(forType type: NSPasteboard.PasteboardType) -> String? {
        stringValue
    }
}
