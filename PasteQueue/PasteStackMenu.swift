import SwiftUI
import ServiceManagement
import os

private let menuLogger = Logger(subsystem: "com.slenbder.pastequeue", category: "PasteStackMenu")

// TEMP DEBUG: os.Logger output isn't visible for processes launched outside Xcode's own
// debugger session, so mirror to a plain file for external inspection. Remove once the
// manual drag gesture is verified working.
private func debugLog(_ message: String) {
    let line = "\(Date()) \(message)\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/pq_debug.log"
        if FileManager.default.fileExists(atPath: path) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

struct PasteStackMenu: View {
    @ObservedObject var stack: PasteStack
    @State private var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled

    // Manual drag-to-reorder state. AppKit's List backing draws its own insertion-line +
    // lifted-ghost visuals during onMove drags with no public SwiftUI hook to suppress
    // them, so reordering is hand-rolled here via DragGesture instead of List(onMove:).
    @State private var draggingID: UUID?
    @State private var rawTranslation: CGFloat = 0
    @State private var swapCompensation: CGFloat = 0
    @State private var rowHeights: [UUID: CGFloat] = [:]

    private static let rowSpacing: CGFloat = 8
    private static let fallbackRowHeight: CGFloat = 32
    private static let dragCoordinateSpace = "queueRows"

    // The dragged row's live vertical offset: raw finger/cursor translation minus however
    // much has already been "spent" on live array swaps, so the row keeps tracking the
    // cursor smoothly across swaps instead of jumping by a row height each time.
    private var dragOffset: CGFloat {
        rawTranslation - swapCompensation
    }

    var body: some View {
        // TEMP DIAGNOSTIC (Bug 2B): confirms whether body is re-evaluated after
        // PasteStack.isCollecting changes (e.g. via the ⌃⌘C hotkey while the popover is open).
        menuLogger.debug("body evaluated isCollecting=\(stack.isCollecting, privacy: .public) queue.count=\(stack.queue.count, privacy: .public)")
        return VStack(alignment: .leading, spacing: 8) {
            if !stack.isAccessibilityTrusted {
                Button("⚠️ Accessibility required") {
                    let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    NSWorkspace.shared.open(url)
                }
                .foregroundColor(.orange)
                Text("Hotkeys won't fire until this app is approved in System Settings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Divider()
            }

            Text(stack.isCollecting ? "Collecting… (\(stack.queue.count))" : "Idle")
                .font(.headline)

            if !stack.queue.isEmpty {
                Divider()
                // A ScrollView asked for its *ideal* height (no incoming height proposal,
                // which is exactly what MenuBarExtra's .window style does when it measures
                // this content to size its popover) reports zero — `.frame(maxHeight:)`
                // alone can't rescue that because it only clamps an already-zero ideal
                // height. Giving the ScrollView an explicit, content-derived `height`
                // sidesteps the ideal-size measurement entirely: rows still show, and the
                // view shrinks for short queues while capping at 230 for long ones.
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.rowSpacing) {
                        ForEach(Array(stack.queue.enumerated()), id: \.element.id) { index, entry in
                            queueRow(index: index, entry: entry)
                        }
                    }
                    .coordinateSpace(name: Self.dragCoordinateSpace)
                }
                .frame(height: listHeight)
            }

            Divider()

            // Bottom two rows, styled as plain text links rather than buttons —
            // row 1 is the frequently-used actions, row 2 is app-level utilities.
            HStack(spacing: 10) {
                Button(stack.isCollecting ? "Stop" : "Start") {
                    stack.toggleCollecting()
                }

                Button("Paste") {
                    stack.pasteNext()
                }
                .foregroundColor(stack.queue.isEmpty ? .secondary : .primary)
                .disabled(stack.queue.isEmpty)

                Button("Clear") {
                    stack.clear()
                }
                .foregroundColor(stack.queue.isEmpty ? .secondary : .primary)
                .disabled(stack.queue.isEmpty)
            }
            .buttonStyle(.plain)
            .font(.callout)

            Divider()

            HStack {
                Button {
                    toggleLaunchAtLogin()
                } label: {
                    HStack(spacing: 4) {
                        Text("Launch at Login")
                        if launchAtLoginEnabled {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                Spacer()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
        }
        .padding()
        .frame(width: 220)
        .onAppear {
            stack.refreshAccessibilityStatus()
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        }
    }

    @ViewBuilder
    private func queueRow(index: Int, entry: QueuedClipboardItem) -> some View {
        QueueRowView(index: index, entry: entry) {
            stack.remove(id: entry.id)
        }
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { rowHeights[entry.id] = geo.size.height }
            }
        )
        .offset(y: draggingID == entry.id ? dragOffset : 0)
        .zIndex(draggingID == entry.id ? 1 : 0)
        // Dragging the row body itself reorders it — no separate drag handle.
        // minimumDistance keeps a plain click on the delete "x" from being
        // swallowed as a drag start: the gesture only takes over once the
        // cursor has actually moved, so a stationary tap reaches the Button.
        .gesture(
            // Named coordinate space anchored on the VStack (not this row) is deliberate:
            // this row also carries .offset(y: dragOffset), derived from this same
            // gesture's translation. The default .local space measures translation
            // relative to the row's OWN frame, which is itself moving because of that
            // offset — a feedback loop that made translation drift once a live swap
            // animated the row. .global avoids the loop but isn't reliably recognized
            // for gestures nested inside a ScrollView; a named space on a stable ancestor
            // gets the same stability without that problem.
            DragGesture(minimumDistance: 10, coordinateSpace: .named(Self.dragCoordinateSpace))
                .onChanged { value in
                    debugLog("onChanged entry=\(entry.id) translation=\(value.translation.height)")
                    if draggingID != entry.id {
                        draggingID = entry.id
                        swapCompensation = 0
                    }
                    rawTranslation = value.translation.height
                    attemptSwap(entry: entry)
                }
                .onEnded { _ in
                    // The array is already in its final order by this point
                    // (swaps happen live in attemptSwap) — releasing just
                    // animates away whatever sub-row-height offset is left.
                    withAnimation(.default) {
                        rawTranslation = 0
                        swapCompensation = 0
                        draggingID = nil
                    }
                }
        )
    }

    // ~8 rows' worth of height: text rows run ~20pt (`.callout`) + row padding + 8pt
    // inter-row spacing ≈ 32pt/row, image/file rows are taller (28pt frame ≈ 38pt/row).
    // Capped at 230pt so a long queue scrolls instead of pushing the buttons below off
    // the bottom of the popover.
    private var listHeight: CGFloat {
        let contentHeight = stack.queue.reduce(CGFloat(0)) { total, entry in
            switch entry.content {
            case .text:
                return total + 32
            case .image, .file:
                return total + 38
            }
        }
        return min(contentHeight, 230)
    }

    // Swaps the dragged row past a neighbor once its (live, offset-adjusted) position has
    // crossed that neighbor's midpoint — matching Finder/Notes/Reminders' reorder feel.
    // Runs in a loop so a single fast drag can cross more than one row in one callback.
    private func attemptSwap(entry: QueuedClipboardItem) {
        while true {
            guard let currentIndex = stack.queue.firstIndex(where: { $0.id == entry.id }) else { return }
            let myHeight = rowHeights[entry.id] ?? Self.fallbackRowHeight
            let offset = dragOffset

            if offset > 0, currentIndex < stack.queue.count - 1 {
                let nextEntry = stack.queue[currentIndex + 1]
                let nextHeight = rowHeights[nextEntry.id] ?? Self.fallbackRowHeight
                let threshold = myHeight / 2 + Self.rowSpacing + nextHeight / 2
                if offset > threshold {
                    withAnimation(.default) {
                        stack.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: currentIndex + 2)
                    }
                    swapCompensation += nextHeight + Self.rowSpacing
                    continue
                }
            }

            if offset < 0, currentIndex > 0 {
                let prevEntry = stack.queue[currentIndex - 1]
                let prevHeight = rowHeights[prevEntry.id] ?? Self.fallbackRowHeight
                let threshold = myHeight / 2 + Self.rowSpacing + prevHeight / 2
                if -offset > threshold {
                    withAnimation(.default) {
                        stack.move(fromOffsets: IndexSet(integer: currentIndex), toOffset: currentIndex - 1)
                    }
                    swapCompensation -= prevHeight + Self.rowSpacing
                    continue
                }
            }

            break
        }
    }

    private func toggleLaunchAtLogin() {
        do {
            if launchAtLoginEnabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Best-effort: SMAppService can throw (e.g. app not running from /Applications yet).
        }
        launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
}

/// A single row in the queue list: the position number, the item's content preview,
/// and a delete button that only shows up while the row is hovered.
private struct QueueRowView: View {
    let index: Int
    let entry: QueuedClipboardItem
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack {
            Text("\(index + 1).")
                .font(.callout)
            switch entry.content {
            case .text(let str):
                Text(str.prefix(40))
                    .font(.callout)
                    .lineLimit(1)
            case .image(let nsImage):
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 28, height: 28)
            case .file(let url, let originalFilename):
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 28, height: 28)
                Text(originalFilename)
                    .font(.callout)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Always present (never conditionally inserted) so the row's height stays
            // constant whether or not the button is visible — toggling it in and out of
            // the view tree instead made hovered rows grow taller than their neighbors,
            // which shoved every row below it down.
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(isHovering ? 1 : 0)
            .disabled(!isHovering)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .padding(.trailing, 8)
        .background(
            Capsule()
                .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
        )
        .onHover { hovering in
            debugLog("onHover entry=\(entry.id) hovering=\(hovering)")
            isHovering = hovering
        }
    }
}

#Preview("Short queue") {
    let stack = PasteStack()
    stack.queue = [
        QueuedClipboardItem(content: .text("first clipboard item")),
        QueuedClipboardItem(content: .text("second")),
        QueuedClipboardItem(content: .text("third")),
    ]
    stack.isCollecting = true
    return PasteStackMenu(stack: stack)
}

#Preview("Long queue") {
    let stack = PasteStack()
    stack.queue = (1...25).map { QueuedClipboardItem(content: .text("clipboard item number \($0)")) }
    stack.isCollecting = true
    return PasteStackMenu(stack: stack)
}
