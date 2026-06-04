import Combine
import Foundation
import OSLog

@MainActor
final class CodexUsageStore: ObservableObject {
    @Published private(set) var snapshot: CodexUsageSnapshot
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    private var refreshTimer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var pendingManualRefresh = false
    private let sessionReader: CodexSessionTokenUsageReader
    private let logger = Logger(subsystem: "io.github.jj9276489.CodexUsageMonitor", category: "refresh")
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
                self?.refreshIfIdle()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func refresh() {
        refresh(queueIfBusy: true, source: "manual")
    }

    private func refreshIfIdle() {
        refresh(queueIfBusy: false, source: "auto")
    }

    private func refresh(queueIfBusy: Bool, source: String) {
        guard refreshTask == nil else {
            if queueIfBusy {
                pendingManualRefresh = true
                logger.info("Refresh queued while current refresh is running: \(source, privacy: .public)")
            }
            return
        }

        isRefreshing = true
        logger.info("Refresh started: \(source, privacy: .public)")
        let now = Date()
        let databaseURL = databaseURL
        let logsDatabaseURL = logsDatabaseURL
        let sessionReader = sessionReader

        let worker = Task.detached(priority: .utility) { () -> RefreshResult in
            let usageReader = CodexUsageReader(databaseURL: databaseURL)
            let sessionFileIndex = try? usageReader.sessionFileIndex()
            let sessionUsage = try? await sessionReader.loadSummary(
                now: now,
                fileCandidates: sessionFileIndex?.fileCandidates ?? [],
                databaseTokensWithoutSessionFile: sessionFileIndex?.tokensWithoutSessionFile ?? 0
            )
            let headerLimitStatus = try? CodexLimitStatusReader(databaseURL: logsDatabaseURL).loadLatest()
            let limitStatus = latestLimitStatus(sessionUsage?.latestLimitStatus, headerLimitStatus)

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
                self.logger.info("Refresh succeeded")
            case .failure(let databasePath, let message, let limitStatus):
                self.snapshot = .unavailable(
                    databasePath: databasePath,
                    warning: message,
                    limitStatus: limitStatus
                )
                self.lastError = message
                self.logger.error("Refresh failed: \(message, privacy: .public)")
            }
            self.refreshTask = nil
            self.isRefreshing = false

            if self.pendingManualRefresh {
                self.pendingManualRefresh = false
                self.refresh()
            }
        }
    }

    private static func defaultDatabaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_USAGE_DB"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        return defaultCodexHomeURL()
            .appendingPathComponent("state_5.sqlite")
    }

    private static func defaultLogsDatabaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["CODEX_LOGS_DB"], !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }

        return defaultCodexHomeURL()
            .appendingPathComponent("logs_2.sqlite")
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

private func latestLimitStatus(_ lhs: CodexLimitStatus?, _ rhs: CodexLimitStatus?) -> CodexLimitStatus? {
    guard let lhs else {
        return rhs
    }
    guard let rhs else {
        return lhs
    }
    return lhs.observedAt >= rhs.observedAt ? lhs : rhs
}
