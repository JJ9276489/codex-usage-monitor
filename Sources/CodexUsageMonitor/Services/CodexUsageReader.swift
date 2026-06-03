import Foundation
import SQLite3

struct CodexUsageReader {
    let databaseURL: URL

    func loadSnapshot(now: Date = Date(), limitStatus: CodexLimitStatus? = nil) throws -> CodexUsageSnapshot {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return .unavailable(
                databasePath: databaseURL.path,
                warning: "No Codex state database found at the configured path.",
                limitStatus: limitStatus
            )
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard openResult == SQLITE_OK, let handle = db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open database."
            if let db {
                sqlite3_close(db)
            }
            throw ReaderError.sqlite(message)
        }
        defer {
            sqlite3_close(handle)
        }

        sqlite3_busy_timeout(handle, 500)

        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now

        let totals = try readTotals(
            handle: handle,
            todayStart: Int64(todayStart.timeIntervalSince1970),
            sevenDaysAgo: Int64(sevenDaysAgo.timeIntervalSince1970),
            thirtyDaysAgo: Int64(thirtyDaysAgo.timeIntervalSince1970)
        )
        let recentThreads = try readRecentThreads(handle: handle)

        return CodexUsageSnapshot(
            generatedAt: now,
            databasePath: databaseURL.path,
            databaseAvailable: true,
            threadCount: totals.threadCount,
            tokensToday: totals.tokensToday,
            tokensLast7Days: totals.tokensLast7Days,
            tokensLast30Days: totals.tokensLast30Days,
            tokensAllTime: totals.tokensAllTime,
            limitStatus: limitStatus,
            recentThreads: recentThreads,
            warning: nil
        )
    }

    private func readTotals(
        handle: OpaquePointer,
        todayStart: Int64,
        sevenDaysAgo: Int64,
        thirtyDaysAgo: Int64
    ) throws -> UsageTotals {
        let sql = """
        SELECT
            COUNT(*),
            COALESCE(SUM(CASE WHEN updated_at >= ? THEN tokens_used ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN updated_at >= ? THEN tokens_used ELSE 0 END), 0),
            COALESCE(SUM(CASE WHEN updated_at >= ? THEN tokens_used ELSE 0 END), 0),
            COALESCE(SUM(tokens_used), 0)
        FROM threads;
        """

        var statement: OpaquePointer?
        try prepare(sql: sql, handle: handle, statement: &statement)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, todayStart)
        sqlite3_bind_int64(statement, 2, sevenDaysAgo)
        sqlite3_bind_int64(statement, 3, thirtyDaysAgo)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ReaderError.sqlite("Unable to read Codex usage totals.")
        }

        return UsageTotals(
            threadCount: Int(sqlite3_column_int64(statement, 0)),
            tokensToday: sqlite3_column_int64(statement, 1),
            tokensLast7Days: sqlite3_column_int64(statement, 2),
            tokensLast30Days: sqlite3_column_int64(statement, 3),
            tokensAllTime: sqlite3_column_int64(statement, 4)
        )
    }

    private func readRecentThreads(handle: OpaquePointer) throws -> [CodexThreadUsage] {
        let sql = """
        SELECT id, title, source, COALESCE(model, ''), tokens_used, updated_at
        FROM threads
        ORDER BY updated_at DESC
        LIMIT 8;
        """

        var statement: OpaquePointer?
        try prepare(sql: sql, handle: handle, statement: &statement)
        defer {
            sqlite3_finalize(statement)
        }

        var threads: [CodexThreadUsage] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = columnString(statement, index: 0)
            let title = columnString(statement, index: 1)
            let source = columnString(statement, index: 2)
            let model = columnString(statement, index: 3)
            let tokensUsed = sqlite3_column_int64(statement, 4)
            let updatedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 5)))

            threads.append(
                CodexThreadUsage(
                    id: id,
                    title: title,
                    source: source,
                    model: model,
                    tokensUsed: tokensUsed,
                    updatedAt: updatedAt
                )
            )
        }

        return threads
    }

    private func prepare(sql: String, handle: OpaquePointer, statement: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ReaderError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func columnString(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }
}

private struct UsageTotals {
    let threadCount: Int
    let tokensToday: Int64
    let tokensLast7Days: Int64
    let tokensLast30Days: Int64
    let tokensAllTime: Int64
}

enum ReaderError: Error, LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            return message
        }
    }
}
