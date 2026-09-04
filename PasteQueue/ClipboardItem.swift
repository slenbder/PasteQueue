import AppKit

enum ClipboardItem: Equatable {
    case text(String)
    case image(NSImage)
    // url points at our own copy under ClipboardFiles, not the original source path —
    // originalFilename is carried separately purely for display, since the copy's name
    // is UUID-based (see PasteStack.copyToClipboardStorage).
    case file(url: URL, originalFilename: String)

    static func == (lhs: ClipboardItem, rhs: ClipboardItem) -> Bool {
        switch (lhs, rhs) {
        case (.text(let l), .text(let r)):
            return l == r
        case (.image(let l), .image(let r)):
            return l === r
        case (.file(let lURL, _), .file(let rURL, _)):
            return lURL == rURL
        default:
            return false
        }
    }
}

/// Wraps a ClipboardItem with an identity that's stable regardless of content.
/// Needed because the queue can hold two entries with equal content (e.g. the same
/// text copied twice in a row) — identifying a specific queue slot by content match
/// would risk deleting/targeting the wrong one of a pair of duplicates.
struct QueuedClipboardItem: Identifiable, Equatable {
    let id: UUID
    let content: ClipboardItem

    init(id: UUID = UUID(), content: ClipboardItem) {
        self.id = id
        self.content = content
    }
}
