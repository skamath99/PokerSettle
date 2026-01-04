import Foundation
import SwiftData
import SwiftUI

@Observable
class ActiveGameViewModel {
    var game: Game
    var showingSettlement = false
    var editingPlayer: PlayerSession?
    var errorMessage: String?
    var showError = false

    init(game: Game) {
        self.game = game
    }

    func addPlayer(name: String, buyInCount: Int = 1, to modelContext: ModelContext) {
        let nextOrder = (game.players.map { $0.order }.max() ?? -1) + 1
        let player = PlayerSession(playerName: name, buyInCount: buyInCount, order: nextOrder)
        player.game = game
        game.players.append(player)
        modelContext.insert(player)
        saveContext(modelContext)
    }

    func removePlayer(_ player: PlayerSession, from modelContext: ModelContext) {
        if let index = game.players.firstIndex(where: { $0.id == player.id }) {
            game.players.remove(at: index)
        }
        modelContext.delete(player)
        saveContext(modelContext)
    }

    func incrementBuyIn(for player: PlayerSession, in modelContext: ModelContext) {
        player.buyInCount += 1
        saveContext(modelContext)
    }

    func decrementBuyIn(for player: PlayerSession, in modelContext: ModelContext) {
        if player.buyInCount > 1 {
            player.buyInCount -= 1
            saveContext(modelContext)
        }
    }

    func updateFinalChips(for player: PlayerSession, chips: Int, in modelContext: ModelContext) {
        player.finalChipCount = chips
        saveContext(modelContext)
    }

    func completeGame(in modelContext: ModelContext) {
        game.isActive = false
        game.completedAt = Date()
        saveContext(modelContext)
    }

    private func saveContext(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showError = true
        }
    }
}
