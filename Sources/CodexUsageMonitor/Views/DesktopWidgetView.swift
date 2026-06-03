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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.black.opacity(0.30))
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
        .frame(width: 300, height: 236)
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
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
                .background(snapshot.databaseAvailable ? Color.green.opacity(0.88) : Color.yellow)
                .clipShape(Capsule())

            Spacer()
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
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                    Rectangle()
                        .fill(Color.green.opacity(0.82))
                        .frame(width: proxy.size.width * loadRatio)
                    Rectangle()
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
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
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                    Rectangle()
                        .fill(limitColor)
                        .frame(width: proxy.size.width * limitRatio)
                    Rectangle()
                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
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
                .background(Color.yellow.opacity(0.88))
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
        "\(snapshot.limitStatus?.primaryWindowLabel ?? "5H") LIMIT"
    }

    private var limitPercentLabel: String {
        snapshot.limitStatus?.primaryUsedLabel(now: snapshot.generatedAt) ?? "NO LIMIT EVENT"
    }

    private var limitResetLabel: String {
        snapshot.limitStatus?.resetLabel(now: snapshot.generatedAt) ?? "RESET UNKNOWN"
    }

    private var limitObservedLabel: String {
        guard let observedAt = snapshot.limitStatus?.observedAt else {
            return "NO HEADER"
        }
        return "SEEN \(UsageFormat.timestamp(observedAt))"
    }

    private var sourceLabel: String {
        guard let status = snapshot.limitStatus else {
            return "LOCAL TOKENS"
        }
        if !status.primaryWindowIsCurrent(now: snapshot.generatedAt) {
            return "LAST EVENT"
        }
        return "\(status.planType.uppercased()) / \(status.activeLimit.uppercased())"
    }

    private var limitRatio: Double {
        guard
            let status = snapshot.limitStatus,
            status.primaryWindowIsCurrent(now: snapshot.generatedAt),
            let value = status.primaryUsedPercent
        else {
            return 0
        }
        return min(max(Double(value) / 100, 0), 1)
    }

    private var limitColor: Color {
        guard
            let status = snapshot.limitStatus,
            status.primaryWindowIsCurrent(now: snapshot.generatedAt),
            let value = status.primaryUsedPercent
        else {
            return Color.white.opacity(0.28)
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
