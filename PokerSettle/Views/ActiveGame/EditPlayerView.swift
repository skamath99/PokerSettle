import SwiftUI
import SwiftData

struct EditPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let player: PlayerSession

    @State private var playerName: String = ""
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Player Name", text: $playerName)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Edit Player")
                }
            }
            .navigationTitle("Edit Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(playerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                playerName = player.playerName
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func saveChanges() {
        let trimmedName = playerName.trimmingCharacters(in: .whitespaces)

        // Check for duplicate names (excluding current player)
        if let game = player.game,
           game.players.contains(where: { $0.id != player.id && $0.playerName.lowercased() == trimmedName.lowercased() }) {
            errorMessage = "A player with this name already exists in the game."
            showError = true
            return
        }

        player.playerName = trimmedName
        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to save changes: \(error.localizedDescription)"
            showError = true
        }
    }
}
