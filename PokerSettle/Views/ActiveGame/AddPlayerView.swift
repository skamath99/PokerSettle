import SwiftUI
import SwiftData

struct AddPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let game: Game

    @State private var playerName: String = ""
    @State private var buyInCount: Int = 1
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Player Name", text: $playerName)
                        .textInputAutocapitalization(.words)

                    Stepper("Buy-ins: \(buyInCount)", value: $buyInCount, in: 1...10)
                } header: {
                    Text("Player Details")
                } footer: {
                    Text("Enter the player's name and how many times they're buying in initially.")
                }
            }
            .navigationTitle("Add Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addPlayer()
                    }
                    .fontWeight(.semibold)
                    .disabled(playerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func addPlayer() {
        let trimmedName = playerName.trimmingCharacters(in: .whitespaces)

        if game.players.contains(where: { $0.playerName.lowercased() == trimmedName.lowercased() }) {
            errorMessage = "A player with this name already exists in the game."
            showError = true
            return
        }

        let player = PlayerSession(playerName: trimmedName, buyInCount: buyInCount)
        player.game = game
        game.players.append(player)
        modelContext.insert(player)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to add player: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Game.self, configurations: config)
    let game = Game(buyInAmount: 20, chipCount: 1000)
    container.mainContext.insert(game)

    return AddPlayerView(game: game)
        .modelContainer(container)
}
