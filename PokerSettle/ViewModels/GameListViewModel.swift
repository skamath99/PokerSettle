import Foundation
import SwiftData
import SwiftUI

@Observable
class GameListViewModel {
    var games: [Game] = []
    var activeGame: Game?
    var errorMessage: String?
    var showError = false

    func loadGames(from modelContext: ModelContext) {
        let descriptor = FetchDescriptor<Game>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        games = (try? modelContext.fetch(descriptor)) ?? []
        activeGame = games.first { $0.isActive }
    }

    func deleteGame(_ game: Game, from modelContext: ModelContext) {
        modelContext.delete(game)
        do {
            try modelContext.save()
            loadGames(from: modelContext)
        } catch {
            errorMessage = "Failed to delete game: \(error.localizedDescription)"
            showError = true
        }
    }
}
