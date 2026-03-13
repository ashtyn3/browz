import Foundation
import SwiftUI

struct Workspace: Identifiable, Codable {
    let id: UUID
    var name: String
    var emoji: String

    init(id: UUID = UUID(), name: String, emoji: String = "🌐") {
        self.id = id
        self.name = name
        self.emoji = emoji
    }
}
