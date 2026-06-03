import SwiftUI

struct DesktopWidgetView: View {
    @ObservedObject var store: CodexUsageStore

    let onRefresh: () -> Void
    let onClose: () -> Void

    private var snapshot: CodexUsageSnapshot {
        store.snapshot
    }

    private var hasCurrentLimitStatus: Bool {
        snapshot.limitStatus?.primaryWindowIsCurrent(now: snapshot.generatedAt) ?? false
    }

    private var hasCurrentSecondaryLimitStatus: Bool {
        snapshot.limitStatus?.secondaryWindowIsCurrent(now: snapshot.generatedAt) ?? false
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

            VStack(alignment: .leading, spacing: 7) {
                topRail
                mainReadout
                limitBar
                secondaryLimitBar
                lowerGrid
                footer
            }
            .padding(12)
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
                    .background(store.isRefreshing ? Color.green.opacity(0.22) : Color.white.opacity(0.08), in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(store.isRefreshing ? Color.green.opacity(0.46) : Color.white.opacity(0.16), lineWidth: 1)
                    }
                    .rotationEffect(.degrees(store.isRefreshing ? 180 : 0))
                    .animation(.linear(duration: 0.35), value: store.isRefreshing)
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
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .foregroundStyle(.green.opacity(0.92))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
    }

    private var secondaryLimitBar: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(secondaryWindowLabel)
                Spacer()
                Text(secondaryPercentLabel)
            }
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundStyle(.white.opacity(0.88))

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(secondaryColor)
                        .frame(width: proxy.size.width * secondaryRatio)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                }
            }
            .frame(height: 8)

            HStack {
                Text(secondaryResetLabel)
                Spacer()
                Text(secondaryObservedLabel)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.white.opacity(0.48))
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
        return "\(snapshot.limitStatus?.primaryWindowLabel ?? "5H") LIMIT"
    }

    private var limitPercentLabel: String {
        guard let status = snapshot.limitStatus else {
            return "NO DATA"
        }
        guard hasCurrentLimitStatus else {
            return "STALE"
        }
        return status.primaryUsedLabel
    }

    private var limitResetLabel: String {
        guard let status = snapshot.limitStatus else {
            return "WAITING FOR EVENT"
        }
        return status.resetLabel(now: snapshot.generatedAt)
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

    private var secondaryWindowLabel: String {
        return "\(snapshot.limitStatus?.secondaryWindowLabel ?? "7D") LIMIT"
    }

    private var secondaryPercentLabel: String {
        guard let status = snapshot.limitStatus else {
            return "NO DATA"
        }
        guard hasCurrentSecondaryLimitStatus else {
            return "STALE"
        }
        return status.secondaryUsedLabel
    }

    private var secondaryResetLabel: String {
        guard let status = snapshot.limitStatus else {
            return "WAITING FOR EVENT"
        }
        return status.secondaryResetLabel(now: snapshot.generatedAt)
    }

    private var secondaryObservedLabel: String {
        guard let observedAt = snapshot.limitStatus?.observedAt else {
            return "NO LIMIT HEADER"
        }
        guard hasCurrentSecondaryLimitStatus else {
            return "OLD \(UsageFormat.timestamp(observedAt))"
        }
        return "SEEN \(UsageFormat.timestamp(observedAt))"
    }

    private var sourceLabel: String {
        if snapshot.warning != nil {
            return "PARTIAL LOCAL"
        }
        guard let status = snapshot.limitStatus else {
            return "LOCAL TOKENS"
        }
        if !hasCurrentLimitStatus && !hasCurrentSecondaryLimitStatus {
            return "LIMITS STALE"
        }
        return "\(status.planType.uppercased()) / \(status.activeLimit.uppercased())"
    }

    private var limitRatio: Double {
        guard
            hasCurrentLimitStatus,
            let status = snapshot.limitStatus,
            let value = status.primaryUsedPercent
        else {
            return 0
        }
        return min(max(Double(value) / 100, 0), 1)
    }

    private var secondaryRatio: Double {
        guard
            hasCurrentSecondaryLimitStatus,
            let status = snapshot.limitStatus,
            let value = status.secondaryUsedPercent
        else {
            return 0
        }
        return min(max(Double(value) / 100, 0), 1)
    }

    private var limitColor: Color {
        guard hasCurrentLimitStatus else {
            return Color.white.opacity(0.22)
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

    private var secondaryColor: Color {
        guard hasCurrentSecondaryLimitStatus else {
            return Color.white.opacity(0.22)
        }

        guard
            let status = snapshot.limitStatus,
            let value = status.secondaryUsedPercent
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
        .padding(7)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
    }
}
