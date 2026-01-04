import SwiftUI
import SwiftData

struct GameDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let game: Game

    var body: some View {
        List {
            Section("Game Info") {
                if let name = game.name {
                    LabeledContent("Name", value: name)
                }
                LabeledContent("Date", value: formattedDate)
                LabeledContent("Buy-in", value: game.buyInAmount.asCurrency())
                LabeledContent("Chips per buy-in", value: game.chipCount.withCommas())
                LabeledContent("Total pot", value: game.totalPot.asCurrency())
            }

            Section("Players (\(game.players.count))") {
                ForEach(game.players.sorted(by: { $0.netAmount > $1.netAmount })) { player in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(player.playerName)
                            .font(.headline)

                        HStack {
                            Text("Buy-ins: \(player.buyInCount)")
                            Text("•")
                            Text("Final chips: \(player.finalChipCount.withCommas())")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Text("Net: \(player.netAmount.asCurrency())")
                            .font(.subheadline)
                            .foregroundStyle(player.netAmount >= 0 ? .green : .red)
                    }
                    .padding(.vertical, 4)
                }
            }

            if !game.settlements.isEmpty {
                Section("Settlements") {
                    ForEach(game.settlements) { settlement in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(settlement.fromPlayerName) → \(settlement.toPlayerName)")
                                    .font(.subheadline)

                                Text(settlement.amount.asCurrency())
                                    .font(.headline)
                            }

                            Spacer()

                            if settlement.isPaid {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                }
            }

            if !game.isActive {
                Section {
                    Button {
                        reactivateGame()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reactivate Game")
                        }
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Continue playing this game. Settlements will be cleared.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle(game.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func reactivateGame() {
        game.isActive = true
        game.completedAt = nil

        // Clear settlements since the game is being reopened
        for settlement in game.settlements {
            modelContext.delete(settlement)
        }
        game.settlements.removeAll()

        try? modelContext.save()
        dismiss()
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: game.createdAt)
    }
}
