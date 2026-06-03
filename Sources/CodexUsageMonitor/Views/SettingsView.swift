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
                Text("This app reads local Codex token_count events and rate_limits payloads. It does not read credentials and does not call OpenAI APIs. Limit percentages can be stale until Codex writes the next token_count event.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 520)
    }
}
