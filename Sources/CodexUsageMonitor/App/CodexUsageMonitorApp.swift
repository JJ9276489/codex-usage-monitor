import AppKit
import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        Task { @MainActor in
            model.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                store: model.usageStore,
                widgetController: model.widgetController
            )
        } label: {
            Label(model.usageStore.menuBarTitle, systemImage: "terminal")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(store: model.usageStore)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
