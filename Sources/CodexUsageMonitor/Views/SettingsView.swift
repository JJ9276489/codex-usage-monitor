import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: CodexUsageStore

    var body: some View {
        Form {
            Section("Data Source") {
                Text(store.snapshot.databasePath)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Text("Set CODEX_USAGE_DB before launch to point at a different Codex state database.")
                    .foregroundStyle(.secondary)
            }

            Section("Limit Status") {
                Text("This app reads local Codex thread token totals. It does not read credentials and does not call OpenAI APIs. Live remaining quota currently requires Codex /status.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520)
    }
}
