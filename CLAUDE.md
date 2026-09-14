# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

PasteQueue is a macOS menu-bar-only utility. ⌃⌘C collects clipboard copies (text, images, or files) in order; ⌃⌘V pastes them back one at a time, FIFO. Minimum target: macOS 13.0, Apple Silicon only.

## Build & test

The project file (`PasteQueue.xcodeproj`) is generated from `project.yml` via XcodeGen — edit `project.yml`, not the `.xcodeproj` directly.

```bash
# Regenerate .xcodeproj after editing project.yml
xcodegen generate

# Build
xcodebuild -scheme PasteQueue -configuration Debug build

# Run all tests
xcodebuild test -scheme PasteQueue -destination 'platform=macOS'
```

Alternatively, use Xcode: ⌘R to run, ⌘U for tests. See the **Manual testing checklist** in README.md for things tests don't cover (image copy/paste, hotkeys, Launch at Login, queue cap, menu bar icon recoloring).

**App Sandbox must be OFF.** A sandboxed app cannot post synthetic keyboard events or register global key monitors — this is a hard requirement, not optional.

## Architecture

Six source files, including one protocol:

| File | Role |
|------|------|
| `PasteQueueApp.swift` | `@main` entry point + `AppDelegate` owning the `NSStatusItem`, count label, and popover |
| `PasteStack.swift` | Singleton model: FIFO queue, clipboard polling, synthetic paste, Launch at Login |
| `HotkeyManager.swift` | Registers global + local `NSEvent` monitors for ⌃⌘C / ⌃⌘V |
| `PasteStackMenu.swift` | SwiftUI popover content with hand-rolled drag-to-reorder |
| `ClipboardItem.swift` | `ClipboardItem` enum (`.text`, `.image`, `.file`) + `QueuedClipboardItem` wrapper |
| `PasteboardProviding.swift` | Protocol over `NSPasteboard` so tests use `MockPasteboard` |

### Data flow

`PasteStack.shared` is the single source of truth. It `@Published var queue` and `@Published var isCollecting`; `AppDelegate` and `PasteStackMenu` both observe it via Combine / `@ObservedObject`.

Clipboard polling runs via a 0.25 s `Timer` while `isCollecting == true`. `checkPasteboard()` is `internal` (not `private`) so tests can call it directly without racing a real timer.

### Critical ordering in `checkPasteboard()`

File detection (`NSURL` with `.urlReadingFileURLsOnly`) **must run before** image detection (`NSImage`). Copying a file in Finder puts a `public.file-url` on the pasteboard; `NSImage` will "succeed" against it, but returns the generic file-type icon instead of the file's actual content. Catching the URL first avoids this.

Both file and image reads bypass `PasteboardProviding` and talk to `NSPasteboard.general` directly — that's intentional and documented in the source.

### File copy-on-capture

When a file is queued, `PasteStack` immediately copies it to `~/Library/Application Support/PasteQueue/ClipboardFiles/` (named by UUID, not by original filename). This sidesteps sandbox extension issues: some source paths (Photos, sandboxed apps) only grant a read handle for the instant of `readObjects()` — the receiving process can't open the original URL later. The stored copy is owned by this process and can always be handed out. Stored files are cleaned up 2 seconds after `pasteNext()` emits the synthetic ⌘V (the delay gives the receiving app time to read from the pasteboard).

### Status item ownership

The menu bar item is managed directly in `AppDelegate` via plain AppKit (`NSStatusItem`), not SwiftUI's `MenuBarExtra`. This is required to get access to `NSStatusBarButton.effectiveAppearance`, which tracks what's actually behind the menu bar (driven by desktop wallpaper, not the system Light/Dark setting). The SwiftUI `MenuBarExtra` API doesn't expose the underlying button.

The count label (`CenteredLabelView`) is a manual `NSView` subclass drawn with `NSString.draw(in:withAttributes:)`. Its frame is recomputed inside the Combine sink (not once at setup) because `NSStatusBarButton` may not have settled to its final size by the time `applicationDidFinishLaunching` runs.

### Hotkey matching

`HotkeyManager` uses `TISCopyCurrentASCIICapableKeyboardLayoutInputSource` + `UCKeyTranslate` to map the physical keyCode to a character under the ASCII-capable hardware layout. This keeps ⌃⌘C/⌃⌘V tracking the physical key under Dvorak/AZERTY while being unaffected by non-Latin input sources (Cyrillic, Japanese, etc.).

Both a global and a local `NSEvent` monitor are registered — the global monitor misses events when PasteQueue itself is the active app (e.g., while the popover is open); the local monitor covers that case.

### Drag-to-reorder in PasteStackMenu

`List(onMove:)` is intentionally avoided: AppKit's List backing draws its own insertion-line and lifted-ghost visuals with no public hook to suppress them. Reordering is hand-rolled with `DragGesture` using a named coordinate space anchored on the `VStack` ancestor (not the row itself), which avoids a feedback loop where the row's own `offset(y:)` modifier would cause translation drift.

## Testing

`PasteQueueTests/MockPasteboard.swift` provides `MockPasteboard: PasteboardProviding`. Tests drive `checkPasteboard()` directly (no timer). The image and file paths read from `NSPasteboard.general` directly (by design), so those tests write to the real pasteboard and call `NSPasteboard.general.clearContents()` in `setUpWithError()`.

## Extending content types

To add a new pasteboard type, add a case to `ClipboardItem`, then add a detection branch in `PasteStack.checkPasteboard()` (keeping file detection first), a paste branch in `pasteNext()`, and a display branch in `QueueRowView.body`.
