import Foundation

struct HistoryEntry: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
    var visitedAt: Date
}
