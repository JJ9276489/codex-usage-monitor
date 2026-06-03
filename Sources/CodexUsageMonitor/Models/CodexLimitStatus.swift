import Foundation

struct CodexLimitStatus: Equatable {
    let observedAt: Date
    let activeLimit: String
    let planType: String
    let primaryUsedPercent: Int?
    let secondaryUsedPercent: Int?
    let primaryWindowMinutes: Int?
    let secondaryWindowMinutes: Int?
    let primaryResetAt: Date?
    let secondaryResetAt: Date?
    let hasCredits: Bool?
    let creditsBalance: String?

    var primaryWindowLabel: String {
        guard let primaryWindowMinutes else {
            return "5H"
        }

        if primaryWindowMinutes == 300 {
            return "5H"
        }

        if primaryWindowMinutes % 60 == 0 {
            return "\(primaryWindowMinutes / 60)H"
        }

        return "\(primaryWindowMinutes)M"
    }

    var primaryUsedLabel: String {
        guard let primaryUsedPercent else {
            return "UNKNOWN"
        }
        return "\(primaryUsedPercent)% USED"
    }

    var resetLabel: String {
        guard let primaryResetAt else {
            return "RESET UNKNOWN"
        }
        return "RESET \(UsageFormat.timestamp(primaryResetAt))"
    }

    func primaryWindowIsCurrent(now: Date = Date()) -> Bool {
        guard let primaryResetAt else {
            return false
        }
        return primaryResetAt > now
    }

    func primaryUsedLabel(now: Date = Date()) -> String {
        guard primaryWindowIsCurrent(now: now) else {
            return "RESET PASSED"
        }
        return primaryUsedLabel
    }

    func resetLabel(now: Date = Date()) -> String {
        guard let primaryResetAt else {
            return "RESET UNKNOWN"
        }
        if primaryResetAt <= now {
            return "LAST RESET \(UsageFormat.timestamp(primaryResetAt))"
        }
        return "RESET \(UsageFormat.timestamp(primaryResetAt))"
    }
}
