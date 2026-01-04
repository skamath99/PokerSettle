import Foundation
import SwiftData

@Model
class Settlement {
    var id: UUID
    var fromPlayerName: String
    var toPlayerName: String
    var amount: Double
    var isPaid: Bool
    var createdAt: Date

    @Relationship(inverse: \Game.settlements) var game: Game?

    init(id: UUID = UUID(), fromPlayerName: String, toPlayerName: String, amount: Double, isPaid: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.fromPlayerName = fromPlayerName
        self.toPlayerName = toPlayerName
        self.amount = amount
        self.isPaid = isPaid
        self.createdAt = createdAt
    }
}
