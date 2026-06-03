import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var store: CodexUsageStore
    @ObservedObject var widgetController: DesktopWidgetController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            quotaNotice
            metrics
            recentThreads
            footerActions
        }
        .frame(width: 380)
        .padding(16)
        .onAppear {
            store.startAutoRefresh()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Usage")
                    .font(.headline)
                Text("Updated \(UsageFormat.timestamp(store.snapshot.generatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh usage")
        }
    }

    private var quotaNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text("Remaining quota is not exposed through a stable local source yet. Use Codex /status for live limits.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var metrics: some View {
        VStack(spacing: 8) {
            MetricRow(label: "Today", value: UsageFormat.decimal(store.snapshot.tokensToday))
            MetricRow(label: "Last 7 days", value: UsageFormat.decimal(store.snapshot.tokensLast7Days))
            MetricRow(label: "Last 30 days", value: UsageFormat.decimal(store.snapshot.tokensLast30Days))
            MetricRow(label: "All time", value: UsageFormat.decimal(store.snapshot.tokensAllTime))
            MetricRow(label: "Threads", value: "\(store.snapshot.threadCount)")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var recentThreads: some View {
        if !store.snapshot.recentThreads.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Threads")
                    .font(.subheadline.weight(.semibold))

                ForEach(store.snapshot.recentThreads) { thread in
                    RecentThreadRow(thread: thread)
                }
            }
        } else if let warning = store.snapshot.warning {
            Text(warning)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footerActions: some View {
        HStack {
            Button(widgetController.isVisible ? "Hide Widget" : "Show Widget") {
                widgetController.toggle(store: store)
            }

            Button("Open .codex") {
                NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex"))
            }

            Spacer()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

private struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct RecentThreadRow: View {
    let thread: CodexThreadUsage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(thread.displayTitle)
                    .lineLimit(1)
                Text(rowSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Text(UsageFormat.compactTokens(thread.tokensUsed))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var rowSubtitle: String {
        let model = thread.model.isEmpty ? "unknown model" : thread.model
        return "\(model) · \(UsageFormat.relative(thread.updatedAt))"
    }
}
