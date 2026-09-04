# PasteQueue — setup

A minimal menu-bar utility: ⌃⌘C collects text copies in order, ⌃⌘V pastes them
back one at a time, FIFO (first copied, first pasted).

## Creating the Xcode project

1. Xcode → File → New → Project → macOS → App
2. Interface: SwiftUI, Life Cycle: SwiftUI App
3. Delete the auto-generated `ContentView.swift` and the default `@main` App file
4. Drag in the four files from this folder: `PasteQueueApp.swift`, `PasteStack.swift`,
   `HotkeyManager.swift`, `PasteStackMenu.swift`

## Signing & Capabilities

- **Team**: your personal Apple Developer team (same one you already use for VoiceInk)
- **App Sandbox: OFF.** This is the one that actually matters — a sandboxed app
  cannot post synthetic keyboard events or globally monitor keystrokes. If the
  target has an App Sandbox entitlement checked by default, uncheck it.
- No other special entitlements needed.

## First run

1. Build and run (⌘R)
2. macOS will prompt for Accessibility permission the first time
   `HotkeyManager.start()` calls `AXIsProcessTrustedWithOptions`. Approve it in
   System Settings → Privacy & Security → Accessibility.
3. Known annoyance: with ad-hoc/dev signing, every rebuild can register as a
   "new" app to macOS, so you may have to re-approve Accessibility after each
   rebuild during development. Same thing you ran into with VoiceInk — once
   you're happy with it, archiving/signing consistently makes this go away.

## Using it

1. ⌃⌘C on your first field (e.g. street) — starts collecting
2. ⌃⌘C on each next field, in the order you want them pasted
3. Switch to the destination, ⌃⌘V — pastes the first item
4. ⌃⌘V again — pastes the next one, and so on until the queue is empty
5. Click the menu bar icon any time to see what's queued, or hit Clear

## Where to go from here

- Currently plain text only (`NSPasteboard.string(forType: .string)`).
  Extending to images/files means checking additional `NSPasteboard.PasteboardType`
  cases in `PasteStack.checkPasteboard()` — e.g. `.fileURL`, `.tiff`/`.png`.
- No persistence — the queue lives in memory and resets when you quit. That's
  intentional for this use case; add it later if you ever want the queue to
  survive a relaunch.
- If you want this properly notarized/distributable instead of just running
  locally, that's a separate step (Developer ID signing + notarization) —
  not needed for personal use on your own Mac.
