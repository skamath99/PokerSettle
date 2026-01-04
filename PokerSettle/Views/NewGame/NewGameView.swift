import SwiftUI
import SwiftData

struct NewGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var gameName: String = ""
    @State private var buyInAmount: String = "5"
    @State private var chipCount: String = "30"
    @State private var showError = false
    @State private var errorMessage = ""
    @FocusState private var focusedField: Field?

    enum Field {
        case gameName, buyInAmount, chipCount
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Game Name (optional)", text: $gameName)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .gameName)
                } header: {
                    Text("Game Details")
                } footer: {
                    Text("Give this game a custom name, or leave blank to use the date/time.")
                }

                Section {
                    HStack {
                        Text("$")
                            .foregroundStyle(.secondary)
                        TextField("5", text: $buyInAmount)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .buyInAmount)
                    }

                    HStack {
                        Image(systemName: "circle.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("30", text: $chipCount)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .chipCount)
                    }
                } header: {
                    Text("Game Settings")
                } footer: {
                    Text("Set the buy-in amount and how many chips each player receives per buy-in.")
                }
            }
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createGame()
                    }
                    .fontWeight(.semibold)
                }

                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") {
                            focusedField = nil
                        }
                    }
                }
            }
            .alert("Invalid Input", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func createGame() {
        guard let buyIn = Double(buyInAmount), buyIn > 0 else {
            errorMessage = "Please enter a valid buy-in amount greater than 0"
            showError = true
            return
        }

        guard let chips = Int(chipCount), chips > 0 else {
            errorMessage = "Please enter a valid chip count greater than 0"
            showError = true
            return
        }

        let trimmedName = gameName.trimmingCharacters(in: .whitespaces)
        let finalName = trimmedName.isEmpty ? nil : trimmedName

        let game = Game(name: finalName, buyInAmount: buyIn, chipCount: chips)
        modelContext.insert(game)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed to create game: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    NewGameView()
        .modelContainer(for: [Game.self], inMemory: true)
}
