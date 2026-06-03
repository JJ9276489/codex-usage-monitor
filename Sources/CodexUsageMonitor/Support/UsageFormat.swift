import Foundation

enum UsageFormat {
    static func compactTokens(_ value: Int64) -> String {
        let absValue = abs(Double(value))
        let sign = value < 0 ? "-" : ""

        switch absValue {
        case 1_000_000_000...:
            return "\(sign)\(format(absValue / 1_000_000_000))B"
        case 1_000_000...:
            return "\(sign)\(format(absValue / 1_000_000))M"
        case 1_000...:
            return "\(sign)\(format(absValue / 1_000))K"
        default:
            return "\(value)"
        }
    }

    static func decimal(_ value: Int64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func format(_ value: Double) -> String {
        if value >= 10 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }
}
