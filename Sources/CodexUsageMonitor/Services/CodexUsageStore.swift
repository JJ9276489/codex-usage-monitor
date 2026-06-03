import Combine
import Foundation

@MainActor
final class CodexUsageStore: ObservableObject {
    @Published private(set) var snapshot: CodexUsageSnapshot
    @Published private(set) var lastError: String?

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private let sessionReader: CodexSessionTokenUsageReader
    private static let refreshInterval: TimeInterval = 5

    init() {
        let databaseURL = Self.defaultDatabaseURL()
        sessionReader = CodexSessionTokenUsageReader(codexHomeURL: Self.defaultCodexHomeURL())
        snapshot = .unavailable(
            databasePath: databaseURL.path,
            warning: "Usage has not been loaded yet."
        )
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

    var codexHomeURL: URL {
        Self.defaultCodexHomeURL()
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
        guard refreshTask == nil else {
            return
        }

        let now = Date()
        let databaseURL = databaseURL
        let logsDatabaseURL = logsDatabaseURL
        let sessionReader = sessionReader
        let thirtyDaysAgo = Calendar.autoupdatingCurrent.date(byAdding: .day, value: -30, to: now) ?? now

        let worker = Task.detached(priority: .utility) { () -> RefreshResult in
            let usageReader = CodexUsageReader(databaseURL: databaseURL)
            let recentSessionURLs = try? usageReader.recentSessionFileURLs(since: thirtyDaysAgo)
            let sessionUsage = try? await sessionReader.loadSummary(now: now, fileURLs: recentSessionURLs)
            let headerLimitStatus = try? CodexLimitStatusReader(databaseURL: logsDatabaseURL).loadLatest()
            let limitStatus = sessionUsage?.latestLimitStatus ?? headerLimitStatus

            do {
                let snapshot = try usageReader.loadSnapshot(
                    now: now,
                    sessionUsage: sessionUsage,
                    limitStatus: limitStatus
                )
                return .success(snapshot)
            } catch {
                return .failure(
                    databasePath: databaseURL.path,
                    message: error.localizedDescription,
                    limitStatus: limitStatus
                )
            }
        }

        refreshTask = Task { [weak self] in
            let result = await worker.value
            guard let self else {
                return
            }

            switch result {
            case .success(let snapshot):
                self.snapshot = snapshot
                self.lastError = nil
            case .failure(let databasePath, let message, let limitStatus):
                self.snapshot = .unavailable(
                    databasePath: databasePath,
                    warning: message,
                    limitStatus: limitStatus
                )
                self.lastError = message
            }
            self.refreshTask = nil
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

    private static func defaultCodexHomeURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }
}

private enum RefreshResult {
    case success(CodexUsageSnapshot)
    case failure(databasePath: String, message: String, limitStatus: CodexLimitStatus?)
}
