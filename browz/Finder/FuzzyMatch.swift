import Foundation

struct FuzzyMatch {
    static func score(query: String, candidate: String) -> Int {
        let normalizedQuery = query.lowercased()
        if normalizedQuery.isEmpty { return 1 }

        let normalizedCandidate = candidate.lowercased()
        if normalizedCandidate == normalizedQuery { return 1500 }
        if normalizedCandidate.hasPrefix(normalizedQuery) { return 1200 - normalizedCandidate.count }
        if normalizedCandidate.contains(normalizedQuery) { return 900 - normalizedCandidate.count }

        var queryIndex = normalizedQuery.startIndex
        var score = 0
        var streak = 0

        for char in normalizedCandidate where queryIndex < normalizedQuery.endIndex {
            if char == normalizedQuery[queryIndex] {
                streak += 1
                score += 25 + (streak * 10)
                queryIndex = normalizedQuery.index(after: queryIndex)
            } else {
                streak = 0
            }
        }

        return queryIndex == normalizedQuery.endIndex ? score : 0
    }
}
