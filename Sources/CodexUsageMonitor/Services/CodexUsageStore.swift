import Combine
import Foundation

@MainActor
final class CodexUsageStore: ObservableObject {
    @Published private(set) var snapshot: CodexUsageSnapshot
    @Published private(set) var lastError: String?

    private var refreshTimer: Timer?

    init() {
        let databaseURL = Self.defaultDatabaseURL()
        snapshot = .unavailable(
            databasePath: databaseURL.path,
            warning: "Usage has not been loaded yet."
        )
        refresh()
    }

    var menuBarTitle: String {
        guard snapshot.databaseAvailable else {
            return "Codex"
        }
        return "Codex \(UsageFormat.compactTokens(snapshot.tokensToday))"
    }

    var databaseURL: URL {
        Self.defaultDatabaseURL()
    }

    func startAutoRefresh() {
        guard refreshTimer == nil else {
            return
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        do {
            snapshot = try CodexUsageReader(databaseURL: databaseURL).loadSnapshot()
            lastError = nil
        } catch {
            snapshot = .unavailable(
                databasePath: databaseURL.path,
                warning: error.localizedDescription
            )
            lastError = error.localizedDescription
        }
    }

    private static func defaultDatabaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_USAGE_DB"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/state_5.sqlite")
    }
}
