import Foundation

class SettlementCalculator {

    // Minimum amount threshold to avoid floating point precision issues
    private static let settlementThreshold = 0.01

    static func calculateOptimalSettlements(players: [PlayerSession]) -> [Settlement] {
        var balances: [String: Double] = [:]

        for player in players {
            balances[player.playerName] = player.netAmount
        }

        return optimizeTransactions(balances: balances)
    }

    private static func optimizeTransactions(balances: [String: Double]) -> [Settlement] {
        var settlements: [Settlement] = []
        var mutableBalances = balances

        while true {
            guard let maxCreditor = mutableBalances.max(by: { $0.value < $1.value }),
                  maxCreditor.value > settlementThreshold else { break }

            guard let maxDebtor = mutableBalances.min(by: { $0.value < $1.value }),
                  maxDebtor.value < -settlementThreshold else { break }

            let amount = min(maxCreditor.value, -maxDebtor.value)

            let settlement = Settlement(
                fromPlayerName: maxDebtor.key,
                toPlayerName: maxCreditor.key,
                amount: amount
            )
            settlements.append(settlement)

            // Safe unwrapping: these keys are guaranteed to exist from the guards above
            guard let creditorBalance = mutableBalances[maxCreditor.key],
                  let debtorBalance = mutableBalances[maxDebtor.key] else {
                continue
            }

            mutableBalances[maxCreditor.key] = creditorBalance - amount
            mutableBalances[maxDebtor.key] = debtorBalance + amount
        }

        return settlements
    }
}
