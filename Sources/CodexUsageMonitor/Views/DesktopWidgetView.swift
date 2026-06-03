import SwiftUI

struct DesktopWidgetView: View {
    @ObservedObject var store: CodexUsageStore

    let onRefresh: () -> Void
    let onClose: () -> Void

    private var snapshot: CodexUsageSnapshot {
        store.snapshot
    }

    private var loadRatio: Double {
        guard snapshot.tokensLast7Days > 0 else {
            return 0
        }
        return min(Double(snapshot.tokensToday) / Double(snapshot.tokensLast7Days), 1)
    }

    private var fiveHourLocalRatio: Double {
        guard snapshot.tokensToday > 0 else {
            return 0
        }
        return min(Double(snapshot.tokensLast5Hours) / Double(snapshot.tokensToday), 1)
    }

    private var hasCurrentLimitStatus: Bool {
        snapshot.limitStatus?.primaryWindowIsCurrent(now: snapshot.generatedAt) ?? false
    }

    private var shellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    var body: some View {
        ZStack {
            shellShape
                .fill(.thinMaterial)
                .overlay {
                    shellShape
                        .fill(Color.black.opacity(0.22))
                }

            VStack(alignment: .leading, spacing: 9) {
                topRail
                mainReadout
                limitBar
                loadBar
                lowerGrid
                footer
            }
            .padding(14)
        }
        .frame(width: 300, height: 280)
        .clipShape(shellShape)
        .contentShape(shellShape)
        .compositingGroup()
        .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 8)
        .overlay {
            shellShape
                .strokeBorder(Color.white.opacity(0.13), lineWidth: 0.8)
        }
    }

    private var topRail: some View {
        HStack(spacing: 8) {
            Text("Codex")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(snapshot.databaseAvailable ? "LOCAL" : "NO DB")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .foregroundStyle(.black)
                .background(snapshot.databaseAvailable ? Color.green.opacity(0.78) : Color.yellow.opacity(0.84))
                .clipShape(Capsule())

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.88))
                    .frame(width: 24, height: 24)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("Refresh usage")
            .accessibilityLabel("Refresh usage")
        }
    }

    private var mainReadout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOKENS TODAY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.56))

            Text(UsageFormat.compactTokens(snapshot.tokensToday))
                .font(.system(size: 38, weight: .heavy, design: .monospaced))
                .foregroundStyle(.green.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var loadBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("TODAY / 7D LOAD")
                Spacer()
                Text("\(Int(loadRatio * 100))%")
            }
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white.opacity(0.88))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.green.opacity(0.82))
                        .frame(width: proxy.size.width * loadRatio)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
            .frame(height: 8)
        }
    }

    private var limitBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(limitWindowLabel)
                Spacer()
                Text(limitPercentLabel)
            }
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white.opacity(0.88))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.14))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(limitColor)
                        .frame(width: proxy.size.width * limitRatio)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
            .frame(height: 8)

            HStack {
                Text(limitResetLabel)
                Spacer()
                Text(limitObservedLabel)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.48))
        }
    }

    private var lowerGrid: some View {
        HStack(spacing: 8) {
            BrutalistMetric(label: "7D", value: UsageFormat.compactTokens(snapshot.tokensLast7Days))
            BrutalistMetric(label: "30D", value: UsageFormat.compactTokens(snapshot.tokensLast30Days))
            BrutalistMetric(label: "ALL", value: UsageFormat.compactTokens(snapshot.tokensAllTime))
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("SOURCE")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.yellow.opacity(0.76))
                .clipShape(Capsule())

            Text(sourceLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.84))

            Spacer()

            Text(UsageFormat.timestamp(snapshot.generatedAt))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var limitWindowLabel: String {
        guard hasCurrentLimitStatus else {
            return "5H LOCAL TOKENS"
        }
        return "\(snapshot.limitStatus?.primaryWindowLabel ?? "5H") LIMIT"
    }

    private var limitPercentLabel: String {
        guard let status = snapshot.limitStatus else {
            return UsageFormat.compactTokens(snapshot.tokensLast5Hours)
        }
        guard hasCurrentLimitStatus else {
            return UsageFormat.compactTokens(snapshot.tokensLast5Hours)
        }
        return status.primaryUsedLabel
    }

    private var limitResetLabel: String {
        guard hasCurrentLimitStatus else {
            return "LIMIT % NOT LOCAL"
        }
        return snapshot.limitStatus?.resetLabel(now: snapshot.generatedAt) ?? "RESET UNKNOWN"
    }

    private var limitObservedLabel: String {
        guard let observedAt = snapshot.limitStatus?.observedAt else {
            return "NO LIMIT HEADER"
        }
        guard hasCurrentLimitStatus else {
            return "OLD \(UsageFormat.timestamp(observedAt))"
        }
        return "SEEN \(UsageFormat.timestamp(observedAt))"
    }

    private var sourceLabel: String {
        guard let status = snapshot.limitStatus else {
            return "LOCAL TOKENS"
        }
        if !hasCurrentLimitStatus {
            return "LOCAL TOKENS"
        }
        return "\(status.planType.uppercased()) / \(status.activeLimit.uppercased())"
    }

    private var limitRatio: Double {
        guard hasCurrentLimitStatus else {
            return fiveHourLocalRatio
        }

        guard
            let status = snapshot.limitStatus,
            let value = status.primaryUsedPercent
        else {
            return 0
        }
        return min(max(Double(value) / 100, 0), 1)
    }

    private var limitColor: Color {
        guard hasCurrentLimitStatus else {
            return .green.opacity(0.82)
        }

        guard
            let status = snapshot.limitStatus,
            let value = status.primaryUsedPercent
        else {
            return Color.white.opacity(0.22)
        }
        if value >= 95 {
            return .red.opacity(0.88)
        }
        if value >= 75 {
            return .yellow.opacity(0.88)
        }
        return .green.opacity(0.82)
    }
}

private struct BrutalistMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
    }
}
