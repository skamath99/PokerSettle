import SwiftUI

struct PlayerRowView: View {
    let player: PlayerSession
    let onIncrementBuyIn: () -> Void
    let onDecrementBuyIn: () -> Void
    let onUpdateChips: (Int) -> Void
    let onEdit: () -> Void

    @State private var chipText: String = ""
    @FocusState private var isChipFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.playerName)
                        .font(.headline)

                    Text("Total invested: \(player.totalBuyIn.asCurrency())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if player.finalChipCount > 0 && player.buyInCount > 0 {
                    Text(player.netAmount.asCurrency())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(player.netAmount >= 0 ? .green : .red)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Buy-ins")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Button {
                            onDecrementBuyIn()
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .disabled(player.buyInCount <= 0)

                        Text("\(player.buyInCount)")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(minWidth: 30)

                        Button {
                            onIncrementBuyIn()
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("Final Chips")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("0", text: $chipText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                        .focused($isChipFieldFocused)
                        .onChange(of: chipText) { _, newValue in
                            // Handle empty string by setting chips to 0
                            if newValue.isEmpty {
                                onUpdateChips(0)
                            } else if let chips = Int(newValue) {
                                onUpdateChips(chips)
                            }
                        }
                }
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            chipText = player.finalChipCount > 0 ? "\(player.finalChipCount)" : ""
        }
        .onChange(of: player.finalChipCount) { _, newValue in
            // Update chipText when finalChipCount changes externally
            if !isChipFieldFocused {
                chipText = newValue > 0 ? "\(newValue)" : ""
            }
        }
    }
}
