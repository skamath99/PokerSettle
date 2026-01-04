import Foundation
import SwiftData

@Model
class PlayerSession {
    var id: UUID
    var playerName: String
    var buyInCount: Int
    var finalChipCount: Int
    var createdAt: Date
    var order: Int

    @Relationship(inverse: \Game.players) var game: Game?

    init(id: UUID = UUID(), playerName: String, buyInCount: Int = 1, finalChipCount: Int = 0, createdAt: Date = Date(), order: Int = 0) {
        self.id = id
        self.playerName = playerName
        self.buyInCount = buyInCount
        self.finalChipCount = finalChipCount
        self.createdAt = createdAt
        self.order = order
    }

    var totalBuyIn: Double {
        guard let game = game else { return 0 }
        return game.buyInAmount * Double(buyInCount)
    }

    var finalValue: Double {
        guard let game = game else { return 0 }
        return Double(finalChipCount) * game.chipToDollarRatio
    }

    var netAmount: Double {
        finalValue - totalBuyIn
    }
}
