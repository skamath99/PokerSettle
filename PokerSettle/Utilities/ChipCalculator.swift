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

    /// Distributes chips evenly across all denominations, ensuring players have
    /// a healthy mix rather than a stack dominated by one chip value.
    /// Phase 1: give each denomination the same base count N (where N × Σvalues ≤ target).
    /// Phase 2: fill any remainder with smaller denominations, smallest first.
    static func calculate(denominations: [Denomination], players: Int, targetStack: Int) -> Result? {
        guard players > 0, targetStack > 0 else { return nil }
        let valid = denominations
            .filter { $0.value > 0 && $0.count > 0 }
            .sorted { $0.value < $1.value }  // smallest first
        guard !valid.isEmpty else { return nil }

        let sumValues = valid.reduce(0) { $0 + $1.value }
        let maxByAvailability = valid.reduce(Int.max) { min($0, $1.count / players) }
        let baseCount = min(maxByAvailability, sumValues > 0 ? targetStack / sumValues : 0)

        var chipCounts = [Int: Int]()
        var remaining = targetStack

        for denom in valid where baseCount > 0 {
            chipCounts[denom.value] = baseCount
            remaining -= baseCount * denom.value
        }

        // Fill remainder greedily from smallest denomination upward
        for denom in valid where remaining > 0 {
            let used = chipCounts[denom.value] ?? 0
            let extra = min(denom.count / players - used, remaining / denom.value)
            if extra > 0 {
                chipCounts[denom.value] = used + extra
                remaining -= extra * denom.value
            }
        }

        let allocations = valid
            .compactMap { denom -> AllocationRow? in
                guard let count = chipCounts[denom.value], count > 0 else { return nil }
                return AllocationRow(denomination: denom.value, chipsPerPlayer: count)
            }
            .sorted { $0.denomination > $1.denomination }

        let actualStack = allocations.reduce(0) { $0 + $1.subtotal }

        return Result(
            allocations: allocations,
            actualStack: actualStack,
            targetStack: targetStack
        )
    }
}
