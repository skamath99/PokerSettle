import SwiftUI

struct SettlementSummaryView: View {
    let game: Game
    let validationResult: ValidationHelper.ValidationResult

    var body: some View {
        Section {
            LabeledContent("Total Pot", value: game.totalPot.asCurrency())

            LabeledContent("Total Chips In") {
                Text(totalChipsIn.withCommas())
            }

            LabeledContent("Total Chips Out") {
                Text(totalChipsOut.withCommas())
            }

            if let message = validationResult.message {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: validationIcon)
                        .foregroundStyle(validationColor)

                    Text(message)
                        .font(.caption)
                        .foregroundStyle(validationColor)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Chip count balanced")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        } header: {
            Text("Summary")
        }
    }

    private var totalChipsIn: Int {
        game.buyInAmount > 0 ? Int(game.totalPot / game.chipToDollarRatio) : 0
    }

    private var totalChipsOut: Int {
        game.players.reduce(0) { $0 + $1.finalChipCount }
    }

    private var validationIcon: String {
        switch validationResult {
        case .balanced:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    private var validationColor: Color {
        switch validationResult {
        case .balanced:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}
