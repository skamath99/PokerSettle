import Foundation
import SwiftData

@Model
class Game {
    var id: UUID
    var name: String?
    var createdAt: Date
    var buyInAmount: Double
    var chipCount: Int
    var isActive: Bool
    var completedAt: Date?

    @Relationship(deleteRule: .cascade) var players: [PlayerSession]
    @Relationship(deleteRule: .cascade) var settlements: [Settlement]

    init(id: UUID = UUID(), name: String? = nil, createdAt: Date = Date(), buyInAmount: Double, chipCount: Int, isActive: Bool = true, completedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.buyInAmount = buyInAmount
        self.chipCount = chipCount
        self.isActive = isActive
        self.completedAt = completedAt
        self.players = []
        self.settlements = []
    }

    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var chipToDollarRatio: Double {
        guard chipCount > 0 else { return 0 }
        return buyInAmount / Double(chipCount)
    }

    var totalPot: Double {
        players.reduce(0) { $0 + $1.totalBuyIn }
    }

    var totalChips: Int {
        guard buyInAmount > 0, chipToDollarRatio > 0 else { return 0 }
        return Int(totalPot / chipToDollarRatio)
    }
}
