import AppKit
import SwiftUI

@main
struct CodexUsageMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: AppModel

    init() {
        _model = StateObject(wrappedValue: AppModel.shared)
        DispatchQueue.main.async {
            AppModel.shared.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            AppModel.shared.start()
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
                .onAppear {
                    model.start()
                }
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
        Task { @MainActor in
            AppModel.shared.start()
        }
    }
}
