import AppKit
import SwiftUI

@MainActor
final class DesktopWidgetController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private let positionXKey = "desktopWidgetOriginX"
    private let positionYKey = "desktopWidgetOriginY"

    func show(store: CodexUsageStore) {
        if let panel {
            position(panel)
            panel.orderFrontRegardless()
            isVisible = true
            return
        }

        let panelSize = NSSize(width: 300, height: 236)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false
        panel.level = Self.desktopWidgetLevel
        panel.delegate = self

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
        let defaults = UserDefaults.standard
        if defaults.object(forKey: positionXKey) != nil, defaults.object(forKey: positionYKey) != nil {
            panel.setFrameOrigin(
                NSPoint(
                    x: defaults.double(forKey: positionXKey),
                    y: defaults.double(forKey: positionYKey)
                )
            )
            return
        }

        guard let frame = NSScreen.main?.visibleFrame else {
            return
        }

        let margin: CGFloat = 24
        let nativeWidgetClearance: CGFloat = 130
        panel.setFrameOrigin(
            NSPoint(
                x: frame.minX + margin,
                y: frame.maxY - panel.frame.height - nativeWidgetClearance
            )
        )
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard let panel = notification.object as? NSPanel, panel === self.panel else {
                return
            }
            let defaults = UserDefaults.standard
            defaults.set(panel.frame.origin.x, forKey: positionXKey)
            defaults.set(panel.frame.origin.y, forKey: positionYKey)
        }
    }

    private static var desktopWidgetLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
}
