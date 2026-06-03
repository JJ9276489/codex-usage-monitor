import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let usageStore: CodexUsageStore
    let widgetController: DesktopWidgetController

    init() {
        usageStore = CodexUsageStore()
        widgetController = DesktopWidgetController()
    }

    func start() {
        usageStore.startAutoRefresh()
        widgetController.show(store: usageStore)
    }
}
