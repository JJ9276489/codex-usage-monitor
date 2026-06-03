import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let usageStore: CodexUsageStore
    let widgetController: DesktopWidgetController
    private var workspaceObserver: NSObjectProtocol?

    init() {
        usageStore = CodexUsageStore()
        widgetController = DesktopWidgetController()
    }

    func start() {
        usageStore.startAutoRefresh()
        observeWorkspaceChanges()
        widgetController.show(store: usageStore)
    }

    private func observeWorkspaceChanges() {
        guard workspaceObserver == nil else {
            return
        }

        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.usageStore.refresh()
            }
        }
    }
}
