import SwiftUI

struct GameRowView: View {
    let game: Game
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(game.displayName)
                    .font(.headline)

                if isActive {
                    Spacer()
                    Text("ACTIVE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.green)
                        .cornerRadius(4)
                }
            }

            if game.name != nil {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label("\(game.players.count) players", systemImage: "person.2.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Total: \(game.totalPot.asCurrency())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Buy-in: \(game.buyInAmount.asCurrency()) • \(game.chipCount.withCommas()) chips")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: game.createdAt)
    }
}
