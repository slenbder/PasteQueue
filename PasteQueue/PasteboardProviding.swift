import AppKit

/// Narrow read-only view of NSPasteboard that PasteStack depends on.
/// Lets tests substitute a mock instead of touching the real system pasteboard.
protocol PasteboardProviding {
    var changeCount: Int { get }
    func string(forType type: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: PasteboardProviding {}
