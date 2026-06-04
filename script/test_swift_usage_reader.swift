import Foundation

@main
struct TestSwiftUsageReader {
    static func main() async throws {
        let now = localDate(2026, 6, 3, 12)
        let today7 = localDate(2026, 6, 3, 7)
        let today9 = localDate(2026, 6, 3, 9)
        let today10 = localDate(2026, 6, 3, 10)
        let sixDaysAgo = localDate(2026, 5, 28, 12)
        let twoDaysAgo = localDate(2026, 6, 1, 12)
        let thirtyOneDaysAgo = localDate(2026, 5, 3, 12)
        let eightDaysAgo = localDate(2026, 5, 26, 12)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-swift-reader-\(UUID().uuidString)", isDirectory: true)
        let codexHome = root.appendingPathComponent(".codex", isDirectory: true)
        let sessions = codexHome.appendingPathComponent("sessions/2026/06/03", isDirectory: true)
        let archived = codexHome.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archived, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let active = sessions.appendingPathComponent("rollout-active.jsonl")
        let archivedSession = archived.appendingPathComponent("rollout-archived.jsonl")
        let filesystemOnly = sessions.appendingPathComponent("rollout-filesystem-only.jsonl")
        let missing = sessions.appendingPathComponent("missing.jsonl")

        try writeLines(
            [
                tokenCountLine(today7, totalTokens: 50_100, lastTokens: 100),
                tokenCountLine(today9, totalTokens: 50_180, lastTokens: 80),
                tokenCountLine(today9.addingTimeInterval(1_800), totalTokens: 50_180, includeLastUsage: false),
                tokenCountLine(
                    today10,
                    totalTokens: 50_250,
                    lastTokens: 70,
                    primary: ["used_percent": 33.0, "window_minutes": 300, "resets_at": now.timeIntervalSince1970 + 1_000],
                    secondary: ["used_percent": 44.0, "window_minutes": 10_080, "resets_at": now.timeIntervalSince1970 + 2_000],
                    fractional: false
                ),
                emptyLimitLine(today10.addingTimeInterval(60), totalTokens: 50_250),
            ],
            to: active
        )
        try writeLines(
            [
                tokenCountLine(sixDaysAgo, totalTokens: 200_000, lastTokens: 1_000),
                tokenCountLine(twoDaysAgo, totalTokens: 200_300, lastTokens: 300),
            ],
            to: archivedSession
        )
        try writeLines(
            [
                tokenCountLine(thirtyOneDaysAgo, totalTokens: 1_005_000, lastTokens: 5_000),
                tokenCountLine(eightDaysAgo, totalTokens: 1_005_600, lastTokens: 600),
                tokenCountLine(sixDaysAgo, totalTokens: 1_005_900, lastTokens: 300),
            ],
            to: filesystemOnly
        )

        let reader = CodexSessionTokenUsageReader(codexHomeURL: codexHome)
        let summary = try await reader.loadSummary(
            now: now,
            fileCandidates: [
                CodexSessionFileCandidate(url: active, databaseTokens: 250),
                CodexSessionFileCandidate(url: archivedSession, databaseTokens: 1_300),
                CodexSessionFileCandidate(url: missing, databaseTokens: 999_999),
            ],
            databaseTokensWithoutSessionFile: 42
        )

        try assertEqual(summary.sessionFileCount, 4, "sessionFileCount")
        try assertEqual(summary.failedSessionFileCount, 1, "failedSessionFileCount")
        try assertEqual(summary.tokenCountEventCount, 10, "tokenCountEventCount")
        try assertEqual(summary.missingLastUsageEventCount, 1, "missingLastUsageEventCount")
        try assertEqual(summary.tokensLast5Hours, 250, "tokensLast5Hours")
        try assertEqual(summary.tokensToday, 250, "tokensToday")
        try assertEqual(summary.tokensLast7Days, 1_850, "tokensLast7Days")
        try assertEqual(summary.tokensLast30Days, 2_450, "tokensLast30Days")
        try assertEqual(summary.tokensAllTime, 2_256_491, "tokensAllTime")
        try assertEqual(summary.latestTokenEventAt, today10.addingTimeInterval(60), "latestTokenEventAt")
        try assertEqual(summary.latestLimitStatus?.primaryUsedPercent, 33, "primaryUsedPercent")
        try assertEqual(summary.latestLimitStatus?.secondaryUsedPercent, 44, "secondaryUsedPercent")
        try assertEqual(summary.latestLimitStatus?.activeLimit, "codex", "activeLimit")

        print("swift usage reader fixture tests passed")
    }

    private static func localDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar.autoupdatingCurrent
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        return components.date!
    }

    private static func tokenCountLine(
        _ timestamp: Date,
        totalTokens: Int,
        lastTokens: Int? = nil,
        primary: [String: Double]? = nil,
        secondary: [String: Double]? = nil,
        fractional: Bool = true,
        includeLastUsage: Bool = true
    ) -> String {
        let lastTokens = lastTokens ?? totalTokens
        var info: [String: Any] = [
            "total_token_usage": [
                "total_tokens": totalTokens,
            ],
        ]
        if includeLastUsage {
            info["last_token_usage"] = [
                "total_tokens": lastTokens,
            ]
        }

        var payload: [String: Any] = [
            "type": "event_msg",
            "timestamp": iso(timestamp, fractional: fractional),
            "payload": [
                "type": "token_count",
                "info": info,
            ],
        ]

        if primary != nil || secondary != nil {
            var inner = payload["payload"] as! [String: Any]
            inner["rate_limits"] = [
                "limit_id": "codex",
                "plan_type": "plus",
                "primary": primary ?? [:],
                "secondary": secondary ?? [:],
                "credits": [
                    "has_credits": false,
                    "unlimited": false,
                    "balance": "0",
                ],
                "rate_limit_reached_type": NSNull(),
            ]
            payload["payload"] = inner
        }

        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func emptyLimitLine(_ timestamp: Date, totalTokens: Int) -> String {
        var payload = try! JSONSerialization.jsonObject(
            with: tokenCountLine(timestamp, totalTokens: totalTokens, lastTokens: 0).data(using: .utf8)!
        ) as! [String: Any]
        var inner = payload["payload"] as! [String: Any]
        inner["rate_limits"] = [
            "limit_id": "premium",
            "plan_type": "plus",
            "primary": NSNull(),
            "secondary": NSNull(),
            "credits": [
                "has_credits": false,
                "unlimited": false,
                "balance": "0",
            ],
            "rate_limit_reached_type": NSNull(),
        ]
        payload["payload"] = inner

        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    private static func iso(_ date: Date, fractional: Bool) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        return formatter.string(from: date)
    }

    private static func writeLines(_ lines: [String], to url: URL) throws {
        try lines.joined(separator: "\n").appending("\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ label: String) throws {
        if actual != expected {
            throw TestError.assertionFailed("\(label): expected \(expected), got \(actual)")
        }
    }
}

enum TestError: Error, CustomStringConvertible {
    case assertionFailed(String)

    var description: String {
        switch self {
        case .assertionFailed(let message):
            return message
        }
    }
}
