import SwiftUI
import SwiftData

struct GameListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Game.createdAt, order: .reverse) private var games: [Game]
    @State private var showingNewGame = false
    @State private var showingChipCalculator = false

    var activeGames: [Game] {
        games.filter { $0.isActive }
    }

    var inactiveGames: [Game] {
        games.filter { !$0.isActive }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if games.isEmpty {
                    emptyState
                } else {
                    gamesList
                }
            }
            .navigationTitle("Poker Settle")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewGame = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingChipCalculator = true
                    } label: {
                        Image(systemName: "function")
                    }
                }
            }
            .sheet(isPresented: $showingNewGame) {
                NewGameView()
            }
            .sheet(isPresented: $showingChipCalculator) {
                ChipCalculatorView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "suit.spade.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No Poker Games Yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Create a new game to start tracking buy-ins and payouts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                showingNewGame = true
            } label: {
                Label("New Game", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
    }

    private var gamesList: some View {
        List {
            if !activeGames.isEmpty {
                Section("Active Games") {
                    ForEach(activeGames) { game in
                        NavigationLink {
                            ActiveGameView(game: game)
                        } label: {
                            GameRowView(game: game, isActive: true)
                        }
                    }
                    .onDelete(perform: deleteActiveGames)
                }
            }

            if !inactiveGames.isEmpty {
                Section("Game History") {
                    ForEach(inactiveGames) { game in
                        NavigationLink {
                            GameDetailView(game: game)
                        } label: {
                            GameRowView(game: game, isActive: false)
                        }
                    }
                    .onDelete(perform: deleteInactiveGames)
                }
            }
        }
    }

    private func deleteActiveGames(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(activeGames[index])
        }
        try? modelContext.save()
    }

    private func deleteInactiveGames(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(inactiveGames[index])
        }
        try? modelContext.save()
    }
}

#Preview {
    GameListView()
        .modelContainer(for: [Game.self, PlayerSession.self, Settlement.self], inMemory: true)
}
