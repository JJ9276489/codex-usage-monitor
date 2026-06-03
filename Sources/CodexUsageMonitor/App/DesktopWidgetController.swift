import AppKit
import SwiftUI

@MainActor
final class DesktopWidgetController: NSObject, ObservableObject, NSWindowDelegate {
    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private var moveSnapTask: Task<Void, Never>?
    private var isApplyingSnap = false
    private let positionXKey = "desktopWidgetOriginX"
    private let positionYKey = "desktopWidgetOriginY"
    private let placementVersionKey = "desktopWidgetPlacementVersion"

    private static let cornerRadius: CGFloat = 28
    private static let gridStep: CGFloat = 16
    private static let margin: CGFloat = 24
    private static let placementVersion = 4

    func show(store: CodexUsageStore) {
        store.refresh()

        if let panel {
            position(panel)
            panel.orderFrontRegardless()
            isVisible = true
            return
        }

        let panelSize = NSSize(width: 300, height: 280)
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
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = Self.cornerRadius
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true

        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        isVisible = true
    }

    func hide() {
        moveSnapTask?.cancel()
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
        if
            defaults.integer(forKey: placementVersionKey) >= Self.placementVersion,
            defaults.object(forKey: positionXKey) != nil,
            defaults.object(forKey: positionYKey) != nil
        {
            let savedOrigin = NSPoint(
                x: defaults.double(forKey: positionXKey),
                y: defaults.double(forKey: positionYKey)
            )
            let snappedOrigin = snappedOrigin(savedOrigin, for: panel)
            panel.setFrameOrigin(snappedOrigin)
            saveOrigin(snappedOrigin)
            return
        }

        guard let frame = NSScreen.main?.visibleFrame else {
            return
        }

        let desktopWidgetRowFromBottom: CGFloat = 224
        let defaultOrigin = snappedOrigin(
            NSPoint(
                x: frame.minX + Self.margin,
                y: frame.minY + desktopWidgetRowFromBottom
            ),
            for: panel
        )
        panel.setFrameOrigin(defaultOrigin)
        saveOrigin(defaultOrigin)
    }

    nonisolated func windowDidMove(_ notification: Notification) {
        Task { @MainActor in
            guard let panel = notification.object as? NSPanel, panel === self.panel else {
                return
            }
            self.scheduleSnapAndSave(panel)
        }
    }

    private func scheduleSnapAndSave(_ panel: NSPanel) {
        guard !isApplyingSnap else {
            return
        }

        moveSnapTask?.cancel()
        moveSnapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else {
                return
            }
            snapAndSave(panel)
        }
    }

    private func snapAndSave(_ panel: NSPanel) {
        let origin = snappedOrigin(panel.frame.origin, for: panel)
        if abs(origin.x - panel.frame.origin.x) > 0.5 || abs(origin.y - panel.frame.origin.y) > 0.5 {
            isApplyingSnap = true
            panel.setFrameOrigin(origin)
            isApplyingSnap = false
        }
        saveOrigin(origin)
    }

    private func snappedOrigin(_ origin: NSPoint, for panel: NSPanel) -> NSPoint {
        guard let frame = (panel.screen ?? NSScreen.main)?.visibleFrame else {
            return origin
        }

        let minX = frame.minX + Self.margin
        let maxX = frame.maxX - panel.frame.width - Self.margin
        let minY = frame.minY + Self.margin
        let maxY = frame.maxY - panel.frame.height - Self.margin
        let x = clamp(round(origin.x / Self.gridStep) * Self.gridStep, minX, maxX)
        let y = clamp(round(origin.y / Self.gridStep) * Self.gridStep, minY, maxY)
        return NSPoint(x: x, y: y)
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    private func saveOrigin(_ origin: NSPoint) {
        let defaults = UserDefaults.standard
        defaults.set(origin.x, forKey: positionXKey)
        defaults.set(origin.y, forKey: positionYKey)
        defaults.set(Self.placementVersion, forKey: placementVersionKey)
    }

    private static var desktopWidgetLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }
}
