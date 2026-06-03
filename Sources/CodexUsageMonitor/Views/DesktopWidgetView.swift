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
            Color.black.opacity(0.92)

            VStack(alignment: .leading, spacing: 12) {
                topRail
                mainReadout
                limitBar
                loadBar
                lowerGrid
                footer
            }
            .padding(14)
        }
        .frame(width: 372, height: 282)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white)
                .frame(height: 2)
        }
        .overlay {
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
        }
    }

    private var topRail: some View {
        HStack(spacing: 8) {
            Text("CODEX//USAGE")
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundStyle(.white)

            Text(snapshot.databaseAvailable ? "LOCAL" : "NO DB")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .foregroundStyle(.black)
                .background(snapshot.databaseAvailable ? Color.green : Color.yellow)

            Spacer()

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Refresh")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Hide widget")
        }
    }

    private var mainReadout: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("TOKENS TODAY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.gray)

            Text(UsageFormat.compactTokens(snapshot.tokensToday))
                .font(.system(size: 52, weight: .black, design: .monospaced))
                .foregroundStyle(.green)
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
            .foregroundStyle(.white)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.16))
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: proxy.size.width * loadRatio)
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
            }
            .frame(height: 14)
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
            .foregroundStyle(.white)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                    Rectangle()
                        .fill(limitColor)
                        .frame(width: proxy.size.width * limitRatio)
                    Rectangle()
                        .stroke(Color.white, lineWidth: 1)
                }
            }
            .frame(height: 14)

            HStack {
                Text(limitResetLabel)
                Spacer()
                Text(limitObservedLabel)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(.gray)
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
                .background(Color.yellow)

            Text(sourceLabel)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Spacer()

            Text(UsageFormat.timestamp(snapshot.generatedAt))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.gray)
        }
    }

    private var limitWindowLabel: String {
        "\(snapshot.limitStatus?.primaryWindowLabel ?? "5H") LIMIT"
    }

    private var limitPercentLabel: String {
        snapshot.limitStatus?.primaryUsedLabel ?? "NO LIMIT EVENT"
    }

    private var limitResetLabel: String {
        snapshot.limitStatus?.resetLabel ?? "RESET UNKNOWN"
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
        return "\(status.planType.uppercased()) / \(status.activeLimit.uppercased())"
    }

    private var limitRatio: Double {
        guard let value = snapshot.limitStatus?.primaryUsedPercent else {
            return 0
        }
        return min(max(Double(value) / 100, 0), 1)
    }

    private var limitColor: Color {
        guard let value = snapshot.limitStatus?.primaryUsedPercent else {
            return .gray
        }
        if value >= 95 {
            return .red
        }
        if value >= 75 {
            return .yellow
        }
        return .green
    }
}

private struct BrutalistMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .foregroundStyle(.gray)
            Text(value)
                .font(.system(size: 17, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .overlay {
            Rectangle()
                .stroke(Color.white.opacity(0.75), lineWidth: 1)
        }
    }
}
