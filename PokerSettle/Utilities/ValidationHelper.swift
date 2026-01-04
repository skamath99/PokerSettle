import Foundation

struct ValidationHelper {

    // Maximum acceptable chip difference to account for rounding and tips
    private static let chipDifferenceWarningThreshold = 10

    static func validateChipBalance(game: Game) -> ValidationResult {
        let totalChipsIn = game.buyInAmount > 0 ? Int(game.totalPot / game.chipToDollarRatio) : 0
        let totalChipsOut = game.players.reduce(0) { $0 + $1.finalChipCount }

        let difference = abs(totalChipsIn - totalChipsOut)

        if difference == 0 {
            return .balanced
        } else if difference <= chipDifferenceWarningThreshold {
            return .warning("Chip count off by \(difference). This might be due to rounding or tips.")
        } else {
            return .error("Chip count mismatch: Expected \(totalChipsIn.withCommas()), got \(totalChipsOut.withCommas())")
        }
    }

    enum ValidationResult {
        case balanced
        case warning(String)
        case error(String)

        var isValid: Bool {
            switch self {
            case .balanced, .warning:
                return true
            case .error:
                return false
            }
        }

        var message: String? {
            switch self {
            case .balanced:
                return nil
            case .warning(let msg), .error(let msg):
                return msg
            }
        }
    }
}
