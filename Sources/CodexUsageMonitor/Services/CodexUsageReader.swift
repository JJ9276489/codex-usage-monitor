import Foundation
import SQLite3

struct CodexUsageReader {
    let databaseURL: URL

    func loadSnapshot(
        now: Date = Date(),
        sessionUsage: CodexSessionUsageSummary? = nil,
        limitStatus: CodexLimitStatus? = nil
    ) throws -> CodexUsageSnapshot {
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

        let totals = try readTotals(handle: handle)
        let recentThreads = try readRecentThreads(handle: handle)

        return CodexUsageSnapshot(
            generatedAt: now,
            databasePath: databaseURL.path,
            databaseAvailable: true,
            threadCount: totals.threadCount,
            tokensLast5Hours: sessionUsage?.tokensLast5Hours ?? 0,
            tokensToday: sessionUsage?.tokensToday ?? 0,
            tokensLast7Days: sessionUsage?.tokensLast7Days ?? 0,
            tokensLast30Days: sessionUsage?.tokensLast30Days ?? 0,
            tokensAllTime: totals.tokensAllTime,
            limitStatus: limitStatus,
            recentThreads: recentThreads,
            warning: sessionUsage == nil ? "No session token_count events were available for rolling totals." : nil
        )
    }

    func recentSessionFileURLs(since minimumUpdatedAt: Date) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return []
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

        let sql = """
        SELECT rollout_path
        FROM threads
        WHERE updated_at >= ?
          AND rollout_path != ''
        GROUP BY rollout_path
        ORDER BY MAX(updated_at) DESC;
        """

        var statement: OpaquePointer?
        try prepare(sql: sql, handle: handle, statement: &statement)
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_int64(statement, 1, Int64(minimumUpdatedAt.timeIntervalSince1970))

        var fileURLs: [URL] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let path = columnString(statement, index: 0)
            guard !path.isEmpty, FileManager.default.fileExists(atPath: path) else {
                continue
            }
            fileURLs.append(URL(fileURLWithPath: path))
        }

        return fileURLs
    }

    private func readTotals(handle: OpaquePointer) throws -> UsageTotals {
        let sql = """
        SELECT
            COUNT(*),
            COALESCE(SUM(tokens_used), 0)
        FROM threads;
        """

        var statement: OpaquePointer?
        try prepare(sql: sql, handle: handle, statement: &statement)
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw ReaderError.sqlite("Unable to read Codex usage totals.")
        }

        return UsageTotals(
            threadCount: Int(sqlite3_column_int64(statement, 0)),
            tokensAllTime: sqlite3_column_int64(statement, 1)
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
