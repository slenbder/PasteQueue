# PasteQueue

A minimal menu-bar utility: ⌃⌘C collects copies (text or images) in order,
⌃⌘V pastes them back one at a time, FIFO (first copied, first pasted).

## Installing

1. Open `PasteQueue.dmg`.
2. Drag `PasteQueue.app` into the `Applications` shortcut in the same window.

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

The queue holds at most 50 items — anything copied past that is silently
ignored (no alert) until you paste some off or clear the queue. A small
orange dot appears on the menu bar icon once the queue reaches 20 items, as
an early heads-up before you hit the cap.

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
- **Launch at Login** — toggle it on, log out/in (or restart), confirm the
  app actually launches; toggle off, confirm it doesn't launch next time.
- **Queue cap** — copy 50+ items in a row, confirm collecting past 50 is a
  silent no-op and the orange dot shows up once you cross 20.
- **⌃⌘C / ⌃⌘V hotkeys** — still needs a live keyboard and a granted
  Accessibility permission, same as before.
- **Menu bar icon color follows what's under the menu bar, not the system
  theme** — with the app running, change the *desktop wallpaper* (not the
  system Light/Dark Mode setting) between a light and a dark image and
  confirm the icon silhouette recolors to match what's actually behind the
  menu bar in each case. This is deliberately a wallpaper change, not a
  theme change: system Dark Mode + light wallpaper is exactly the case
  where the two can disagree, and the icon should still track the
  wallpaper. The orange badge (when the queue is at 20+ items) must stay
  orange in both cases — it's a separate view layered on top of the icon,
  not part of the recolored template image.

## Known limitation: secure input fields

⌃⌘V will not paste into **secure text fields** — password fields
(`NSSecureTextField`), Keychain prompts, or a `sudo` password prompt in
Terminal. When a secure field is focused, macOS enables "Secure Event Input,"
which blocks *all* other processes — including PasteQueue's global hotkey
monitor and its synthetic ⌘V keystroke — from observing or injecting
keyboard events into that field. In practice: the hotkey may not even fire
while a secure field has focus, and if it does, nothing gets typed. No crash,
no error, no partial paste — just silently nothing, by macOS design. This is
a platform security boundary (it's exactly what stops keyloggers and
autotype tools from reading or injecting into password fields), not a bug in
this app.

## Where to go from here

- Text and images are supported (`ClipboardItem.text` / `.image`, detected
  via `NSPasteboard.readObjects(forClasses: [NSImage.self], ...)`, which
  covers PNG/JPEG/TIFF/GIF/HEIC without listing UTIs by hand). Other
  pasteboard types (file URLs, RTF, etc.) still fall outside scope — extending
  further means adding another case to `ClipboardItem` and another branch in
  `PasteStack.checkPasteboard()`.
- No persistence — the queue lives in memory and resets when you quit. That's
  intentional for this use case; add it later if you ever want the queue to
  survive a relaunch.
- Properly notarized/Developer-ID-signed distribution is a separate step
  (paid Apple Developer Program membership required) — not needed for
  personal use or sharing with a few people who don't mind the one-time
  Gatekeeper bypass above.
- **Icon placeholders**: the menu bar currently shows `Image(systemName:
  "list.clipboard")` (see the `TODO` in `PasteQueueApp.swift`), and
  `Assets.xcassets/AppIcon.appiconset` has an empty 1024×1024 slot. Once the
  custom icon is ready:
  1. Drag the 1024×1024 export into the `AppIcon` slot in the asset catalog
     editor — no other changes needed there.
  2. For the menu bar icon, add the template asset to `Assets.xcassets`,
     then in `PasteQueueApp.swift` swap the `Image(systemName: "list.clipboard")`
     line for `Image("MenuBarIcon")` and mark it template-rendered
     (`.renderingMode(.template)` if it isn't already flagged as a template
     image in the asset catalog) so it follows the menu bar's light/dark/
     highlight state like the SF Symbol does now.

See `SETUP.md` for building from source.
