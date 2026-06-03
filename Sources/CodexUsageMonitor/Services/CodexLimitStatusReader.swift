import Foundation
import SQLite3

struct CodexLimitStatusReader {
    let databaseURL: URL

    func loadLatest() throws -> CodexLimitStatus? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            return nil
        }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let openResult = sqlite3_open_v2(databaseURL.path, &db, flags, nil)
        guard openResult == SQLITE_OK, let handle = db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open Codex logs."
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
        SELECT ts, feedback_log_body
        FROM logs
        WHERE feedback_log_body LIKE '%X-Codex-Primary-Window-Minutes%'
        ORDER BY ts DESC, ts_nanos DESC, id DESC
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ReaderError.sqlite(String(cString: sqlite3_errmsg(handle)))
        }
        defer {
            sqlite3_finalize(statement)
        }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let observedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(statement, 0)))
        guard let bodyPointer = sqlite3_column_text(statement, 1) else {
            return nil
        }

        let body = String(cString: bodyPointer)
        return CodexLimitStatus(
            observedAt: observedAt,
            activeLimit: header("X-Codex-Active-Limit", in: body) ?? "unknown",
            planType: header("X-Codex-Plan-Type", in: body) ?? "unknown",
            primaryUsedPercent: intHeader("X-Codex-Primary-Used-Percent", in: body),
            secondaryUsedPercent: intHeader("X-Codex-Secondary-Used-Percent", in: body),
            primaryWindowMinutes: intHeader("X-Codex-Primary-Window-Minutes", in: body),
            secondaryWindowMinutes: intHeader("X-Codex-Secondary-Window-Minutes", in: body),
            primaryResetAt: dateHeader("X-Codex-Primary-Reset-At", in: body),
            secondaryResetAt: dateHeader("X-Codex-Secondary-Reset-At", in: body),
            hasCredits: boolHeader("X-Codex-Credits-Has-Credits", in: body),
            creditsBalance: header("X-Codex-Credits-Balance", in: body)
        )
    }

    private func intHeader(_ name: String, in body: String) -> Int? {
        header(name, in: body).flatMap(Int.init)
    }

    private func dateHeader(_ name: String, in body: String) -> Date? {
        guard let raw = header(name, in: body), let epoch = TimeInterval(raw) else {
            return nil
        }
        return Date(timeIntervalSince1970: epoch)
    }

    private func boolHeader(_ name: String, in body: String) -> Bool? {
        guard let raw = header(name, in: body)?.lowercased() else {
            return nil
        }
        if raw == "true" {
            return true
        }
        if raw == "false" {
            return false
        }
        return nil
    }

    private func header(_ name: String, in body: String) -> String? {
        let needle = "\"\(name)\":\""
        guard let start = body.range(of: needle) else {
            return nil
        }
        let valueStart = start.upperBound
        guard let end = body[valueStart...].firstIndex(of: "\"") else {
            return nil
        }
        return String(body[valueStart..<end])
    }
}
