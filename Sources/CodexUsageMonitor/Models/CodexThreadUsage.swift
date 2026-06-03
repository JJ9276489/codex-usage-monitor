import Foundation

struct CodexThreadUsage: Identifiable, Equatable {
    let id: String
    let title: String
    let source: String
    let model: String
    let tokensUsed: Int64
    let updatedAt: Date

    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled thread" : trimmed
    }
}
