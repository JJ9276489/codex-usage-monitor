import Foundation

struct CodexSessionUsageSummary: Equatable {
    let tokensLast5Hours: Int64
    let tokensToday: Int64
    let tokensLast7Days: Int64
    let tokensLast30Days: Int64
    let tokensAllTime: Int64
    let latestLimitStatus: CodexLimitStatus?
}

actor CodexSessionTokenUsageReader {
    let codexHomeURL: URL
    private var cache: [String: CachedFileUsage] = [:]

    init(codexHomeURL: URL) {
        self.codexHomeURL = codexHomeURL
    }

    func loadSummary(now: Date = Date(), fileURLs: [URL]? = nil) throws -> CodexSessionUsageSummary {
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: now)
        let fiveHoursAgo = calendar.date(byAdding: .hour, value: -5, to: now) ?? now
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
        let candidateFileURLs = ((fileURLs ?? []) + sessionFileURLs(modifiedSince: thirtyDaysAgo))
            .deduplicatedAndSortedByPath()

        var tokensLast5Hours: Int64 = 0
        var tokensToday: Int64 = 0
        var tokensLast7Days: Int64 = 0
        var tokensLast30Days: Int64 = 0
        var tokensAllTime: Int64 = 0
        var latestLimitStatus: CodexLimitStatus?

        let activePaths = Set(candidateFileURLs.map(\.path))
        cache = cache.filter { activePaths.contains($0.key) }

        for fileURL in candidateFileURLs {
            guard let usage = try? usage(for: fileURL) else {
                continue
            }

            for event in usage.events {
                tokensAllTime += event.increment
                if event.timestamp >= fiveHoursAgo {
                    tokensLast5Hours += event.increment
                }
                if event.timestamp >= todayStart {
                    tokensToday += event.increment
                }
                if event.timestamp >= sevenDaysAgo {
                    tokensLast7Days += event.increment
                }
                if event.timestamp >= thirtyDaysAgo {
                    tokensLast30Days += event.increment
                }
            }

            if let limitStatus = usage.latestLimitStatus,
               latestLimitStatus == nil || limitStatus.observedAt > latestLimitStatus!.observedAt {
                latestLimitStatus = limitStatus
            }
        }

        return CodexSessionUsageSummary(
            tokensLast5Hours: tokensLast5Hours,
            tokensToday: tokensToday,
            tokensLast7Days: tokensLast7Days,
            tokensLast30Days: tokensLast30Days,
            tokensAllTime: tokensAllTime,
            latestLimitStatus: latestLimitStatus
        )
    }

    private func sessionFileURLs(modifiedSince minimumModifiedAt: Date) -> [URL] {
        let roots = [
            codexHomeURL.appendingPathComponent("sessions", isDirectory: true),
            codexHomeURL.appendingPathComponent("archived_sessions", isDirectory: true)
        ]
        let resourceKeys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        var fileURLs: [URL] = []

        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
                guard let values = try? fileURL.resourceValues(forKeys: Set(resourceKeys)),
                      values.isRegularFile == true
                else {
                    continue
                }
                if let modifiedAt = values.contentModificationDate, modifiedAt < minimumModifiedAt {
                    continue
                }
                fileURLs.append(fileURL)
            }
        }

        return fileURLs.sorted { $0.path < $1.path }
    }

    private func usage(for fileURL: URL) throws -> ParsedFileUsage {
        let values = try fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let signature = FileSignature(
            byteCount: Int64(values.fileSize ?? -1),
            modifiedAt: values.contentModificationDate ?? .distantPast
        )

        let cacheKey = fileURL.path
        if let cached = cache[cacheKey], cached.signature == signature {
            return cached.usage
        }

        let usage = try parseFileUsage(fileURL)
        cache[cacheKey] = CachedFileUsage(signature: signature, usage: usage)
        return usage
    }

    private func parseFileUsage(_ fileURL: URL) throws -> ParsedFileUsage {
        let data = try Data(contentsOf: fileURL, options: [.mappedIfSafe])
        guard let text = String(data: data, encoding: .utf8) else {
            return ParsedFileUsage(events: [], latestLimitStatus: nil)
        }

        var events: [TokenIncrement] = []
        var previousTotal: Int64?
        var latestLimitStatus: CodexLimitStatus?

        text.enumerateLines { [self] line, _ in
            guard let record = self.tokenCountRecord(from: line) else {
                return
            }

            let increment: Int64
            if let previousTotal {
                increment = max(record.totalTokens - previousTotal, 0)
            } else {
                increment = record.totalTokens
            }
            previousTotal = record.totalTokens

            if increment > 0 {
                events.append(TokenIncrement(timestamp: record.timestamp, increment: increment))
            }

            if let limitStatus = record.limitStatus,
               latestLimitStatus == nil || limitStatus.observedAt > latestLimitStatus!.observedAt {
                latestLimitStatus = limitStatus
            }
        }

        return ParsedFileUsage(events: events, latestLimitStatus: latestLimitStatus)
    }

    private func tokenCountRecord(from line: String) -> TokenCountRecord? {
        guard line.contains("\"token_count\""), line.contains("\"total_token_usage\"") else {
            return nil
        }

        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              dictionary["type"] as? String == "event_msg",
              let payload = dictionary["payload"] as? [String: Any],
              payload["type"] as? String == "token_count",
              let timestampRaw = dictionary["timestamp"] as? String,
              let timestamp = Self.timestamp(from: timestampRaw),
              let info = payload["info"] as? [String: Any],
              let totalUsage = info["total_token_usage"] as? [String: Any],
              let totalTokens = int64Value(totalUsage["total_tokens"])
        else {
            return nil
        }

        return TokenCountRecord(
            timestamp: timestamp,
            totalTokens: totalTokens,
            limitStatus: limitStatus(from: payload["rate_limits"], observedAt: timestamp)
        )
    }

    private func limitStatus(from value: Any?, observedAt: Date) -> CodexLimitStatus? {
        guard let dictionary = value as? [String: Any] else {
            return nil
        }

        let primary = dictionary["primary"] as? [String: Any]
        let secondary = dictionary["secondary"] as? [String: Any]
        let credits = dictionary["credits"] as? [String: Any]

        return CodexLimitStatus(
            observedAt: observedAt,
            activeLimit: stringValue(dictionary["limit_id"]) ?? "codex",
            planType: stringValue(dictionary["plan_type"]) ?? "unknown",
            primaryUsedPercent: percentValue(primary?["used_percent"]),
            secondaryUsedPercent: percentValue(secondary?["used_percent"]),
            primaryWindowMinutes: intValue(primary?["window_minutes"]),
            secondaryWindowMinutes: intValue(secondary?["window_minutes"]),
            primaryResetAt: dateValue(primary?["resets_at"]),
            secondaryResetAt: dateValue(secondary?["resets_at"]),
            hasCredits: boolValue(credits?["has_credits"]),
            creditsBalance: stringValue(credits?["balance"])
        )
    }

    private func int64Value(_ value: Any?) -> Int64? {
        if let value = value as? Int64 {
            return value
        }
        if let value = value as? Int {
            return Int64(value)
        }
        if let value = value as? NSNumber {
            return value.int64Value
        }
        if let value = value as? String {
            return Int64(value)
        }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        int64Value(value).map(Int.init)
    }

    private func percentValue(_ value: Any?) -> Int? {
        if let value = doubleValue(value) {
            return Int(value.rounded())
        }
        return intValue(value)
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? NSNumber {
            return value.doubleValue
        }
        if let value = value as? String {
            return Double(value)
        }
        return nil
    }

    private func dateValue(_ value: Any?) -> Date? {
        doubleValue(value).map { Date(timeIntervalSince1970: $0) }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool {
            return value
        }
        if let value = value as? NSNumber {
            return value.boolValue
        }
        if let value = value as? String {
            if value.lowercased() == "true" {
                return true
            }
            if value.lowercased() == "false" {
                return false
            }
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            return value
        }
        if let value = value as? NSNumber {
            return value.stringValue
        }
        return nil
    }

    private static func timestamp(from value: String) -> Date? {
        timestampFormatterWithFractionalSeconds.date(from: value) ?? timestampFormatter.date(from: value)
    }

    private static let timestampFormatterWithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct TokenCountRecord {
    let timestamp: Date
    let totalTokens: Int64
    let limitStatus: CodexLimitStatus?
}

private struct TokenIncrement {
    let timestamp: Date
    let increment: Int64
}

private struct ParsedFileUsage {
    let events: [TokenIncrement]
    let latestLimitStatus: CodexLimitStatus?
}

private struct FileSignature: Equatable {
    let byteCount: Int64
    let modifiedAt: Date
}

private struct CachedFileUsage {
    let signature: FileSignature
    let usage: ParsedFileUsage
}

private extension Array where Element == URL {
    func deduplicatedAndSortedByPath() -> [URL] {
        var seen: Set<String> = []
        var urls: [URL] = []

        for url in self where seen.insert(url.path).inserted {
            urls.append(url)
        }

        return urls.sorted { $0.path < $1.path }
    }
}
