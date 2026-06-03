import Combine
import Foundation

@MainActor
final class CodexUsageStore: ObservableObject {
    @Published private(set) var snapshot: CodexUsageSnapshot
    @Published private(set) var lastError: String?

    private var refreshTimer: Timer?
    private static let refreshInterval: TimeInterval = 15

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

    var logsDatabaseURL: URL {
        Self.defaultLogsDatabaseURL()
    }

    func startAutoRefresh() {
        guard refreshTimer == nil else {
            return
        }

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        let limitStatus = try? CodexLimitStatusReader(databaseURL: logsDatabaseURL).loadLatest()

        do {
            snapshot = try CodexUsageReader(databaseURL: databaseURL).loadSnapshot(limitStatus: limitStatus)
            lastError = nil
        } catch {
            snapshot = .unavailable(
                databasePath: databaseURL.path,
                warning: error.localizedDescription,
                limitStatus: limitStatus
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

    private static func defaultLogsDatabaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_LOGS_DB"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/logs_2.sqlite")
    }
}
