import SwiftUI
import SwiftData

struct ActiveGameView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let game: Game
    @State private var viewModel: ActiveGameViewModel
    @State private var newPlayerName: String = ""
    @State private var showDuplicateAlert = false
    @FocusState private var isAddingPlayer: Bool

    init(game: Game) {
        self.game = game
        _viewModel = State(initialValue: ActiveGameViewModel(game: game))
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Buy-in", value: game.buyInAmount.asCurrency())
                LabeledContent("Chips per buy-in", value: game.chipCount.withCommas())
                LabeledContent("Total pot", value: game.totalPot.asCurrency())
            } header: {
                Text("Game Settings")
            }

            Section {
                if game.players.isEmpty {
                    ContentUnavailableView(
                        "No Players Yet",
                        systemImage: "person.3.fill",
                        description: Text("Add players to start tracking buy-ins")
                    )
                    .frame(minHeight: 100)
                } else {
                    ForEach(game.players.sorted(by: { $0.order < $1.order })) { player in
                        PlayerRowView(
                            player: player,
                            onIncrementBuyIn: {
                                viewModel.incrementBuyIn(for: player, in: modelContext)
                            },
                            onDecrementBuyIn: {
                                viewModel.decrementBuyIn(for: player, in: modelContext)
                            },
                            onUpdateChips: { chips in
                                viewModel.updateFinalChips(for: player, chips: chips, in: modelContext)
                            },
                            onEdit: {
                                viewModel.editingPlayer = player
                            }
                        )
                    }
                    .onDelete { indexSet in
                        let sortedPlayers = game.players.sorted(by: { $0.order < $1.order })
                        for index in indexSet {
                            viewModel.removePlayer(sortedPlayers[index], from: modelContext)
                        }
                    }
                }

                HStack {
                    TextField("Add player name...", text: $newPlayerName)
                        .textInputAutocapitalization(.words)
                        .focused($isAddingPlayer)
                        .onSubmit {
                            addPlayerQuick()
                        }

                    Button {
                        addPlayerQuick()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                    .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Players (\(game.players.count))")
            }
        }
        .navigationTitle(game.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Calculate Payouts") {
                    viewModel.showingSettlement = true
                }
                .disabled(game.players.isEmpty)
            }

            ToolbarItem(placement: .keyboard) {
                HStack {
                    Spacer()
                    Button("Done") {
                        isAddingPlayer = false
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
        }
        .sheet(isPresented: $viewModel.showingSettlement) {
            SettlementView(game: game, onComplete: {
                dismiss()
            })
        }
        .sheet(item: $viewModel.editingPlayer) { player in
            EditPlayerView(player: player)
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK") { }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .alert("Duplicate Player", isPresented: $showDuplicateAlert) {
            Button("OK") { }
        } message: {
            Text("A player with this name already exists in the game.")
        }
    }

    private func addPlayerQuick() {
        let trimmedName = newPlayerName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Check for duplicate names
        if game.players.contains(where: { $0.playerName.lowercased() == trimmedName.lowercased() }) {
            showDuplicateAlert = true
            return
        }

        viewModel.addPlayer(name: trimmedName, buyInCount: 1, to: modelContext)
        newPlayerName = ""
        isAddingPlayer = true // Keep keyboard open for next player
    }
}
