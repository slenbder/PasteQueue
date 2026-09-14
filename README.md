# PasteQueue

A minimal menu-bar utility: ⌃⌘C collects copies (text or images) in order,
⌃⌘V pastes them back one at a time, FIFO (first copied, first pasted).

## ⌨️ Hotkeys — read this before you buy

PasteQueue uses two global hotkeys. **They are hardcoded in v1 — not
configurable:**

- **⌃⌘C** (Control + Command + C) — start/stop collecting
- **⌃⌘V** (Control + Command + V) — paste the next item in the queue

Check these against any hotkey tools you already have running (Raycast,
Ice, Rectangle, BetterTouchTool, etc.) *before* buying — if either combo
is already bound to something else, it will conflict. Configurable
hotkeys are planned for a future version, not v1.

## Requirements

- macOS 13.0 (Ventura) or later
- Apple Silicon only — Intel Macs are not supported and have not been tested

## Installing

1. Open `PasteQueue.dmg`.
2. Drag `PasteQueue.app` into the `Applications` shortcut in the same window.

## Uninstalling

PasteQueue has no installer and no uninstaller — like most macOS utilities
distributed outside the App Store, removing it is just dragging
`PasteQueue.app` to the Trash. That leaves a few small things behind on disk,
none of which are dangerous, but worth knowing about if you want a fully
clean system:

- **`~/Library/Application Support/PasteQueue/ClipboardFiles/`** — temporary
  copies of files you've queued. The app cleans this up itself on every
  normal launch; the only way anything is left here is if the app was
  force-quit with files still queued and then deleted before being run
  again. Safe to delete manually at any time.
- **`~/Library/Preferences/com.slenbder.pastequeue.plist`** — your Launch at
  Login preference. Safe to delete; `defaults delete com.slenbder.pastequeue`
  also works from Terminal.
- **Launch at Login entry** — macOS does *not* clean this up when you delete
  the app. If you had "Launch at Login" enabled, go to **System Settings →
  General → Login Items & Extensions** after deleting the app and remove
  PasteQueue from that list — it'll otherwise sit there pointing at a Trashed
  app indefinitely.

To remove everything in one pass:
```
rm -rf ~/Library/Application\ Support/PasteQueue
rm -f ~/Library/Preferences/com.slenbder.pastequeue.plist
```
(then check Login Items as above, and empty the Trash).

## How to open it (first launch only)

This build is signed with a personal Apple Developer account, not a paid
Developer ID — it is **not notarized**. macOS Gatekeeper will refuse a plain
double-click the first time ("PasteQueue can't be opened because Apple cannot
check it for malicious software" / "is damaged and can't be opened"). This is
expected, not a broken build. Use one of these, once:

**Option A — right-click to open**
1. In `Applications`, right-click (or Control-click) `PasteQueue.app`.
2. Choose **Open**.
3. Click **Open** again in the dialog that appears.

After this one-time approval, launching normally (double-click, Spotlight,
Dock) works from then on.

**Option B — remove the quarantine flag from Terminal**
```
xattr -r -d com.apple.quarantine /Applications/PasteQueue.app
```
Run once after copying the app to `/Applications`, then launch normally.

Either option works — pick whichever is more convenient. You only need to do
this once per copy of the app; a fresh download/rebuild will need it again.

## First run

1. Launch PasteQueue — a 📋 icon appears in the menu bar (no Dock icon, this
   is a menu-bar-only utility).
2. macOS will prompt for Accessibility permission the first time it tries to
   register the global hotkeys. Approve it in
   **System Settings → Privacy & Security → Accessibility**.
3. If you skip or deny the prompt, the menu bar dropdown shows an
   **⚠️ Accessibility required** item — click it to jump straight to the
   right System Settings pane. The hotkeys silently do nothing until this is
   granted; there is no crash, just no effect.
4. Known annoyance with personal-team signing: every rebuild can register as
   a "new" app to macOS, so you may have to re-approve Accessibility after
   each rebuild during development. Not an issue for a normal user just
   running the shipped `.app`.

## Using it

1. ⌃⌘C on your first field (e.g. street) — starts collecting.
2. ⌃⌘C on each next field, in the order you want them pasted. Copying an
   image works the same way — it queues as a thumbnail instead of text.
3. Switch to the destination, ⌃⌘V — pastes the first item.
4. ⌃⌘V again — pastes the next one, and so on until the queue is empty.
   Once the last item is pasted, collecting mode turns itself off
   automatically — no need to remember to hit "Stop collecting."
5. Click the menu bar icon any time to see what's queued, or hit Clear.

The queue holds at most 99 items — anything copied past that is silently
ignored (no alert) until you paste some off or clear the queue. The counter
on the menu bar icon turns red once you hit the cap, as a clear signal
you're full.

## Launch at Login

The menu has a **Launch at Login** item with a checkmark showing current
state — click it to toggle. Uses `SMAppService` (macOS 13+), so it only
works once the app is actually installed in `/Applications` (an `.app`
launched straight out of Xcode's DerivedData can fail to register — that's
expected, not a bug).

## Manual testing checklist

A few things that aren't covered by the automated tests and need a real
run (⌘R or the shipped `.app`):

- **Image copy/paste** — copy a few different sources and confirm each
  queues as a thumbnail and pastes correctly:
  - A screenshot (⌘⇧4, copies to clipboard automatically if you hold Control
    too, or just ⌘C an existing screenshot file's contents in Preview)
  - An image opened in Preview, ⌘C
  - An image copied from a webpage in Safari (right-click → Copy Image)
- **File copy/paste** — copy a few different sources and confirm each
  queues as its own item (icon + original filename) and pastes back the
  actual file, not a broken/generic-icon stand-in:
  - A single file in Finder, ⌘C
  - A multi-selection of several files in Finder, ⌘C — confirm each one
    queues as a separate item, in the order they were selected
  - A photo copied out of Photos.app — this is the case the on-disk copy
    step exists for (Photos only grants a read handle for the instant of
    the copy), so confirm it still pastes correctly, not just that it
    queues
- **Launch at Login** — toggle it on, log out/in (or restart), confirm the
  app actually launches; toggle off, confirm it doesn't launch next time.
- **Queue cap** — copy 99+ items in a row, confirm collecting past 99 is a
  silent no-op and the counter turns red once you hit 99.
- **⌃⌘C / ⌃⌘V hotkeys** — still needs a live keyboard and a granted
  Accessibility permission, same as before.
- **Menu bar icon color follows what's under the menu bar, not the system
  theme** — with the app running, change the *desktop wallpaper* (not the
  system Light/Dark Mode setting) between a light and a dark image and
  confirm the icon silhouette recolors to match what's actually behind the
  menu bar in each case. This is deliberately a wallpaper change, not a
  theme change: system Dark Mode + light wallpaper is exactly the case
  where the two can disagree, and the icon should still track the
  wallpaper. The count label must stay legible in both cases — it's a
  separate view layered on top of the icon, not part of the recolored
  template image, so only its own color (red at the 99 cap) changes, never
  the icon's recoloring behavior.

## Known limitations (v1)

- **Hotkeys are hardcoded.** ⌃⌘C / ⌃⌘V can't be remapped in v1; configurable
  hotkeys are planned for a future version.
- **VoiceOver support is basic.** You can tell what state the app is in and
  perform the core actions, but:
  - Reordering the queue by dragging has no VoiceOver equivalent yet.
  - After deleting an item, VoiceOver focus drops to the scroll-area
    container rather than moving to the next row — you'll need to
    re-enter Interact mode before deleting the next one.
- **Secure input fields.** ⌃⌘V will not paste into secure text fields —
  password fields (`NSSecureTextField`), Keychain prompts, or a `sudo`
  password prompt in Terminal. When a secure field is focused, macOS
  enables "Secure Event Input," which blocks *all* other processes —
  including PasteQueue's global hotkey monitor and its synthetic ⌘V
  keystroke — from observing or injecting keyboard events into that field.
  In practice: the hotkey may not even fire while a secure field has focus,
  and if it does, nothing gets typed. No crash, no error, no partial paste —
  just silently nothing, by macOS design. This is a platform security
  boundary (it's exactly what stops keyloggers and autotype tools from
  reading or injecting into password fields), not a bug in this app.
- **Not notarized.** Signed with a personal Apple Developer account, not a
  paid Developer ID — see "How to open it" above for the one-time
  Gatekeeper bypass.
- **Intel Macs are unsupported and untested** (Apple Silicon only).

## Where to go from here

- Text, images, and files are all supported (`ClipboardItem.text` / `.image`
  / `.file`). Images are detected via `NSPasteboard.readObjects(forClasses:
  [NSImage.self], ...)`, which covers PNG/JPEG/TIFF/GIF/HEIC without listing
  UTIs by hand; files (single or Finder/Photos multi-select) are copied into
  PasteQueue's own storage at capture time so they can still be pasted even
  if the source app's sandbox only grants a read handle for the instant of
  the copy. Rich/styled text (e.g. from Pages or Word) is captured as its
  plain-text fallback — formatting is dropped, since `ClipboardItem` has no
  attributed-string case. Extending further (RTF with formatting, or any
  other pasteboard type) means adding another case to `ClipboardItem` and
  another branch in `PasteStack.checkPasteboard()`.
- No persistence — the queue lives in memory and resets when you quit. That's
  intentional for this use case; add it later if you ever want the queue to
  survive a relaunch.
- Properly notarized/Developer-ID-signed distribution is a separate step
  (paid Apple Developer Program membership required) — not needed for
  personal use or sharing with a few people who don't mind the one-time
  Gatekeeper bypass above.

See `SETUP.md` for building from source.
