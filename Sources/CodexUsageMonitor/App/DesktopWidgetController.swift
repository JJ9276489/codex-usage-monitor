import AppKit
import SwiftUI

@MainActor
final class DesktopWidgetController: ObservableObject {
    @Published private(set) var isVisible = false

    private var panel: NSPanel?

    func show(store: CodexUsageStore) {
        if let panel {
            position(panel)
            panel.orderFrontRegardless()
            isVisible = true
            return
        }

        let panelSize = NSSize(width: 372, height: 246)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        panel.contentViewController = NSHostingController(
            rootView: DesktopWidgetView(
                store: store,
                onRefresh: {
                    Task { @MainActor in
                        store.refresh()
                    }
                },
                onClose: { [weak self] in
                    Task { @MainActor in
                        self?.hide()
                    }
                }
            )
        )

        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    func toggle(store: CodexUsageStore) {
        if isVisible {
            hide()
        } else {
            show(store: store)
        }
    }

    private func position(_ panel: NSPanel) {
        guard let frame = NSScreen.main?.visibleFrame else {
            return
        }

        let margin: CGFloat = 24
        let x = frame.maxX - panel.frame.width - margin
        let y = frame.maxY - panel.frame.height - margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
