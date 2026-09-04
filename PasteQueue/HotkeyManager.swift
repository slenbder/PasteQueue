import AppKit

/// Registers two global hotkeys system-wide:
///   ⌃⌘C  — toggle collecting mode on/off
///   ⌃⌘V  — pop the next item off the queue and paste it
///
/// Needs BOTH a global and a local monitor. Per NSEvent's own documentation:
/// "your handler will not be called for events that are sent to your own application"
/// (addGlobalMonitorForEvents). PasteQueue becomes the active app the moment the user
/// clicks the status item to open the popover — so a ⌃⌘C pressed while that popover is
/// open targets PasteQueue itself, not "another" app, and the global-only monitor never
/// sees it (isCollecting genuinely never changes; it's not a SwiftUI redraw problem).
/// The local monitor covers exactly that case; the global one covers everything else.
/// Both are passive here (local returns the event unmodified) — nothing else is listening
/// for this exact combo, so there's no conflict in practice.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private init() {}

    func start() {
        requestAccessibilityIfNeeded()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            HotkeyManager.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            HotkeyManager.handle(event)
            return event
        }
    }

    private static func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == [.control, .command] else { return }

        switch event.keyCode {
        case 8: // ANSI 'C'
            PasteStack.shared.toggleCollecting()
        case 9: // ANSI 'V'
            PasteStack.shared.pasteNext()
        default:
            break
        }
    }

    private func requestAccessibilityIfNeeded() {
        // Prompts the system Accessibility permission dialog on first launch if not yet granted.
        // Required for both global key monitoring and posting synthetic CGEvents.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: [String: Any] = [promptKey: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
