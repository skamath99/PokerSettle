import Foundation

enum ChipCalculator {
    struct Denomination: Identifiable {
        let id: UUID
        var value: Int  // face value (e.g. 25, 50, 100)
        var count: Int  // total chips of this denomination in the set

        init(value: Int, count: Int) {
            self.id = UUID()
            self.value = value
            self.count = count
        }
    }

    struct AllocationRow: Identifiable {
        let denomination: Int
        let chipsPerPlayer: Int
        var id: Int { denomination }
        var subtotal: Int { denomination * chipsPerPlayer }
    }

    struct Result {
        let allocations: [AllocationRow]
        let actualStack: Int
        let targetStack: Int
        var isExact: Bool { actualStack == targetStack }
        var shortfall: Int { targetStack - actualStack }
    }

    /// Greedily assigns chips from highest denomination down to hit `targetStack` per player.
    static func calculate(denominations: [Denomination], players: Int, targetStack: Int) -> Result? {
        guard players > 0, targetStack > 0 else { return nil }
        let valid = denominations.filter { $0.value > 0 && $0.count > 0 }
        guard !valid.isEmpty else { return nil }

        var remaining = targetStack
        var allocations: [AllocationRow] = []

        for denom in valid.sorted(by: { $0.value > $1.value }) {
            guard remaining > 0 else { break }
            let maxPerPlayer = denom.count / players
            guard maxPerPlayer > 0 else { continue }
            let chips = min(maxPerPlayer, remaining / denom.value)
            guard chips > 0 else { continue }
            allocations.append(AllocationRow(denomination: denom.value, chipsPerPlayer: chips))
            remaining -= chips * denom.value
        }

        return Result(
            allocations: allocations,
            actualStack: targetStack - remaining,
            targetStack: targetStack
        )
    }
}
