import Foundation

struct CodexUsageSnapshot: Equatable {
    let generatedAt: Date
    let databasePath: String
    let databaseAvailable: Bool
    let threadCount: Int
    let tokensToday: Int64
    let tokensLast7Days: Int64
    let tokensLast30Days: Int64
    let tokensAllTime: Int64
    let recentThreads: [CodexThreadUsage]
    let warning: String?

    static func unavailable(databasePath: String, warning: String) -> CodexUsageSnapshot {
        CodexUsageSnapshot(
            generatedAt: Date(),
            databasePath: databasePath,
            databaseAvailable: false,
            threadCount: 0,
            tokensToday: 0,
            tokensLast7Days: 0,
            tokensLast30Days: 0,
            tokensAllTime: 0,
            recentThreads: [],
            warning: warning
        )
    }
}
