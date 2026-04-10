import SwiftUI
import SwiftData

struct SettlementView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let game: Game
    let onComplete: () -> Void

    @State private var viewModel: SettlementViewModel

    init(game: Game, onComplete: @escaping () -> Void) {
        self.game = game
        self.onComplete = onComplete
        _viewModel = State(initialValue: SettlementViewModel(game: game))
    }

    var body: some View {
        NavigationStack {
            List {
                SettlementSummaryView(
                    game: game,
                    validationResult: viewModel.validationResult
                )

                // Only show settlements if validation passes or is just a warning
                if !viewModel.validationResult.isValid {
                    Section {
                        ContentUnavailableView(
                            "Cannot Calculate Settlements",
                            systemImage: "exclamationmark.triangle.fill",
                            description: Text("Please fix the chip count mismatch before completing the game.")
                        )
                    }
                } else if viewModel.settlements.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No Settlements Needed",
                            systemImage: "checkmark.circle.fill",
                            description: Text("All players broke even!")
                        )
                    }
                } else {
                    Section {
                        ForEach(viewModel.settlements) { settlement in
                            SettlementRowView(settlement: settlement)
                        }
                    } header: {
                        Text("Optimized Payments (\(viewModel.settlements.count))")
                    } footer: {
                        if case .warning = viewModel.validationResult {
                            Text("⚠️ Minor chip count discrepancy detected. Settlements may have rounding differences.")
                        } else {
                            Text("These are the minimum transactions needed to settle all debts.")
                        }
                    }
                }

                Section {
                    Button {
                        if viewModel.saveAndComplete(in: modelContext) {
                            onComplete()
                        }
                    } label: {
                        HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Save & Complete Game")
                            }
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                    .disabled(!viewModel.validationResult.isValid)
                }
            }
            .navigationTitle("Settle Up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: viewModel.shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!viewModel.validationResult.isValid)
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") { }
            } message: {
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
}
