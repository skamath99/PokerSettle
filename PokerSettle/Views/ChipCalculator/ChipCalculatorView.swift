import SwiftUI

struct ChipCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var players = 4
    @State private var targetStack = 1000
    @State private var denominations: [ChipCalculator.Denomination] = [
        .init(value: 100, count: 100),
        .init(value: 50, count: 200),
        .init(value: 25, count: 300)
    ]
    @FocusState private var focusedField: UUID?

    private var result: ChipCalculator.Result? {
        ChipCalculator.calculate(denominations: denominations, players: players, targetStack: targetStack)
    }

    var body: some View {
        NavigationStack {
            Form {
                setupSection
                chipSetSection
                resultSection
            }
            .navigationTitle("Chip Calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .keyboard) {
                    HStack {
                        Spacer()
                        Button("Done") { focusedField = nil }
                    }
                }
            }
        }
    }

    private var setupSection: some View {
        Section {
            Stepper("Players: \(players)", value: $players, in: 2...20)
            LabeledContent("Buy-in ($)") {
                TextField("1000", value: $targetStack, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
            }
        } header: {
            Text("Setup")
        } footer: {
            Text("The dollar amount each player buys in for.")
        }
    }

    private var chipSetSection: some View {
        Section {
            ForEach($denominations) { $denom in
                HStack(spacing: 8) {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("25", value: $denom.value, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: denom.id)
                        .frame(width: 55)
                    Spacer()
                    Text("×")
                        .foregroundStyle(.secondary)
                    TextField("100", value: $denom.count, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 55)
                    Text("chips")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { denominations.remove(atOffsets: $0) }

            Button {
                denominations.append(.init(value: 0, count: 0))
            } label: {
                Label("Add Denomination", systemImage: "plus.circle")
            }
        } header: {
            Text("Chip Set")
        } footer: {
            Text("Enter each denomination's face value and how many you have in total. Swipe to delete.")
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result {
            Section {
                resultRows(result: result)
            } header: {
                Text("Each player receives")
            }
        }
    }

    @ViewBuilder
    private func resultRows(result: ChipCalculator.Result) -> some View {
        if result.allocations.isEmpty {
            Text("Not enough chips to distribute.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(result.allocations) { row in
                HStack {
                    Text("\(row.chipsPerPlayer)× $\(row.denomination)")
                    Spacer()
                    Text("= \(row.subtotal)")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("Total per player")
                Spacer()
                Text("\(result.actualStack)")
                    .fontWeight(.semibold)
                    .foregroundStyle(result.isExact ? Color.primary : Color.orange)
            }
            if !result.isExact {
                Label(
                    "Can't hit \(result.targetStack) exactly — \(result.shortfall) short.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }
}

#Preview {
    ChipCalculatorView()
}
