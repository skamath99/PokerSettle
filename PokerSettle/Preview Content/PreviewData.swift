import Foundation
import SwiftData

extension Game {
    static var preview: Game {
        let game = Game(buyInAmount: 20, chipCount: 1000)

        let josh = PlayerSession(playerName: "Josh", buyInCount: 2, finalChipCount: 500, order: 0)
        josh.game = game

        let claire = PlayerSession(playerName: "Claire", buyInCount: 1, finalChipCount: 1500, order: 1)
        claire.game = game

        let sanketh = PlayerSession(playerName: "Sanketh", buyInCount: 1, finalChipCount: 1000, order: 2)
        sanketh.game = game

        game.players = [josh, claire, sanketh]

        return game
    }

    static var completedPreview: Game {
        let game = Game(buyInAmount: 50, chipCount: 2500, isActive: false, completedAt: Date())

        let alice = PlayerSession(playerName: "Alice", buyInCount: 1, finalChipCount: 3000, order: 0)
        alice.game = game

        let bob = PlayerSession(playerName: "Bob", buyInCount: 2, finalChipCount: 2000, order: 1)
        bob.game = game

        game.players = [alice, bob]

        let settlement = Settlement(fromPlayerName: "Bob", toPlayerName: "Alice", amount: 10, isPaid: true)
        settlement.game = game
        game.settlements = [settlement]

        return game
    }
}
