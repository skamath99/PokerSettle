import Foundation
import SwiftData
import SwiftUI

@Observable
class SettlementViewModel {
    var game: Game
    var settlements: [Settlement] = []
    var validationResult: ValidationHelper.ValidationResult = .balanced
    var errorMessage: String?
    var showError = false

    init(game: Game) {
        self.game = game
        calculateSettlements()
        validateBalance()
    }

    func calculateSettlements() {
        settlements = SettlementCalculator.calculateOptimalSettlements(players: game.players)
    }

    func validateBalance() {
        validationResult = ValidationHelper.validateChipBalance(game: game)
    }

    func togglePaid(for settlement: Settlement, in modelContext: ModelContext) {
        settlement.isPaid.toggle()
        do {
            try modelContext.save()
        } catch {
            errorMessage = "Failed to save payment status: \(error.localizedDescription)"
            showError = true
        }
    }

    func saveAndComplete(in modelContext: ModelContext) -> Bool {
        // Validate minimum player count
        guard game.players.count >= 2 else {
            errorMessage = "Cannot complete game: At least 2 players are required"
            showError = true
            return false
        }

        do {
            for settlement in settlements {
                settlement.game = game
                game.settlements.append(settlement)
                modelContext.insert(settlement)
            }

            game.isActive = false
            game.completedAt = Date()
            try modelContext.save()
            return true
        } catch {
            errorMessage = "Failed to save game: \(error.localizedDescription)"
            showError = true
            return false
        }
    }

    var totalPaid: Double {
        settlements.filter { $0.isPaid }.reduce(0) { $0 + $1.amount }
    }

    var totalToPay: Double {
        settlements.reduce(0) { $0 + $1.amount }
    }

    var shareText: String {
        var lines: [String] = []
        lines.append("Game: \(game.displayName)")
        lines.append("Total Pot: \(game.totalPot.asCurrency())")
        if settlements.isEmpty {
            lines.append("\nAll players broke even!")
        } else {
            lines.append("\nSettlements:")
            for s in settlements {
                lines.append("\(s.fromPlayerName) pays \(s.toPlayerName) \(s.amount.asCurrency())")
            }
        }
        return lines.joined(separator: "\n")
    }
}
