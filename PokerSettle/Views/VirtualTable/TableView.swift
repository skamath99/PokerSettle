import SwiftUI
import SwiftData

// MARK: - Table
//
// The live game. Reads everything from the replicated GameState and routes
// every tap through the coordinator/transport. The engine doesn't track turns,
// so any player may add chips or fold at any time during betting — we trust the
// people at the table to run the actual poker.

struct TableView: View {
    @ObservedObject var transport: MultipeerTransport
    @ObservedObject var coordinator: GameCoordinator

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var betText = ""
    @State private var winnerSelection: [UUID: Set<UUID>] = [:]
    @State private var showCashOutConfirm = false
    @State private var showCreateConfirm = false

    private var state: GameState? { coordinator.state }
    private var me: Player? { state?.player(id: coordinator.localPlayer.id) }

    var body: some View {
        List {
            if let state {
                if state.isPaused { pauseBanner(state) }
                potSection(state)
                playersSection(state)
                if state.phase == .showdown { showdownSection(state) }
                if let me, !me.hasCashedOut {
                    actionSection(state, me: me)
                    cashOutSection(me: me)
                } else if let me, me.hasCashedOut {
                    cashedOutBanner(me: me, state: state)
                }
                tableControlsSection(state)
                settleSection(state)
            }
        }
        .animation(.default, value: state?.sequenceNumber)
        .confirmationDialog("Cash out and leave the table?",
                            isPresented: $showCashOutConfirm, titleVisibility: .visible) {
            Button("Cash Out", role: .destructive) {
                if let me { transport.submit(.cashOut(playerID: me.id)) }
            }
        } message: {
            Text("Your chips are locked in and you stop playing. The others keep going.")
        }
        .confirmationDialog("Create a settlement game?",
                            isPresented: $showCreateConfirm, titleVisibility: .visible) {
            Button("Create Game") { createSettlementGame() }
        } message: {
            Text("Turns everyone's final chip counts into a dollar settlement and leaves the table.")
        }
    }

    // MARK: Pause

    @ViewBuilder
    private func pauseBanner(_ state: GameState) -> some View {
        Section {
            HStack {
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
                Text(pauseText(state.pauseReason))
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    private func pauseText(_ reason: PauseReason?) -> String {
        switch reason {
        case .playerDisconnected(let name): return "\(name) disconnected — waiting for everyone to reconnect"
        case .hostTransfer:                 return "Host changed — waiting for everyone to reconnect"
        case .none:                         return "Game paused"
        }
    }

    // MARK: Pot

    @ViewBuilder
    private func potSection(_ state: GameState) -> some View {
        Section {
            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.green)
                Text("Pot")
                Spacer()
                Text("\(state.totalInPots + state.uncollectedCommitted)")
                    .font(.title3.weight(.bold).monospacedDigit())
            }
            if state.pots.count > 1 {
                ForEach(Array(state.pots.enumerated()), id: \.element.id) { idx, pot in
                    HStack {
                        Text(idx == 0 ? "Main pot" : "Side pot \(idx)")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(pot.amount)").font(.caption.monospacedDigit())
                    }
                }
            }
            if state.phase == .betting, state.currentBet > 0 {
                HStack {
                    Text("Bet to match").foregroundStyle(.secondary)
                    Spacer()
                    Text("\(state.currentBet)").monospacedDigit()
                }
                .font(.subheadline)
            }
            if let action = state.lastAction {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(lastActionText(action)).foregroundStyle(.secondary)
                    Spacer()
                }
                .font(.subheadline)
            }
        } header: {
            Text("Hand \(state.handNumber) · \(phaseLabel(state.phase))")
        }
    }

    private func lastActionText(_ action: TableAction) -> String {
        switch action {
        case .added(let player, let amount): return "\(player) added \(amount)"
        case .folded(let player):            return "\(player) folded"
        case .cashedOut(let player):         return "\(player) cashed out"
        case .potsCollected:                 return "Pots collected"
        case .awarded(let player, let amount): return "\(player) won \(amount)"
        }
    }

    private func phaseLabel(_ phase: HandPhase) -> String {
        switch phase {
        case .waiting:  return "Between hands"
        case .betting:  return "Betting"
        case .showdown: return "Showdown"
        }
    }

    // MARK: Players

    @ViewBuilder
    private func playersSection(_ state: GameState) -> some View {
        Section("Players") {
            ForEach(state.players) { player in
                HStack(spacing: 10) {
                    Image(systemName: player.id == state.hostPlayerID ? "crown.fill" : "person.fill")
                        .foregroundStyle(player.id == state.hostPlayerID ? .yellow : .secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(player.name)
                                .fontWeight(player.id == coordinator.localPlayer.id ? .semibold : .regular)
                            if player.hasCashedOut {
                                Text("cashed out").font(.caption2).foregroundStyle(.blue)
                            } else if player.hasFolded {
                                Text("folded").font(.caption2).foregroundStyle(.secondary)
                            }
                            if !player.isConnected && !player.hasCashedOut {
                                Image(systemName: "wifi.slash").font(.caption2).foregroundStyle(.red)
                            }
                        }
                        if let dollars = dollarValue(player.chipStack, state) {
                            Text(dollars).font(.caption2).foregroundStyle(.secondary)
                        } else if player.committed > 0 {
                            Text("in pot: \(player.committed)").font(.caption2).foregroundStyle(.secondary)
                        }
                    }

                    Spacer()
                    Text("\(player.chipStack)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(player.hasFolded && !player.hasCashedOut ? .secondary : .primary)
                }
                .opacity(player.hasFolded && !player.hasCashedOut ? 0.5 : 1)
            }
        }
    }

    private func dollarValue(_ chips: Int, _ state: GameState) -> String? {
        let ratio = state.chipToDollarRatio
        guard ratio > 0 else { return nil }
        return (Double(chips) * ratio).asCurrency()
    }

    // MARK: My actions

    @ViewBuilder
    private func actionSection(_ state: GameState, me: Player) -> some View {
        if state.phase == .betting, !me.hasFolded {
            let toCall = state.toCall(for: me.id)
            Section("Your move") {
                VStack(spacing: 12) {
                    HStack {
                        if toCall > 0 {
                            Text("To call")
                            Spacer()
                            Text("\(toCall)").fontWeight(.semibold).monospacedDigit()
                        } else {
                            Text("You're all square — check, or bet to raise")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                    .font(.subheadline)

                    TextField(toCall > 0 ? "Amount (call \(toCall))" : "Amount to bet", text: $betText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)

                    HStack(spacing: 10) {
                        moveButton("Fold", icon: "xmark", tint: .red, disabled: state.isPaused) {
                            transport.submit(.fold(playerID: me.id))
                        }
                        moveButton("Add", icon: "plus", tint: .blue,
                                   disabled: state.isPaused || (Int(betText) ?? 0) <= 0 || (Int(betText) ?? 0) > me.chipStack) {
                            if let amount = Int(betText), amount > 0 {
                                transport.submit(.commit(playerID: me.id, amount: amount))
                                betText = ""
                            }
                        }
                        moveButton("All-In", icon: "flame.fill", tint: .orange,
                                   disabled: state.isPaused || me.chipStack <= 0) {
                            transport.submit(.commitAllIn(playerID: me.id))
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
            }
        }
    }

    // Uniform, equal-width action button so the row stays balanced.
    private func moveButton(_ title: String, icon: String, tint: Color,
                            disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(disabled)
    }

    // MARK: Cash out

    @ViewBuilder
    private func cashOutSection(me: Player) -> some View {
        Section {
            Button(role: .destructive) {
                showCashOutConfirm = true
            } label: {
                Label("Cash Out", systemImage: "arrow.up.forward.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } footer: {
            Text("Leave with your \(me.chipStack) chips whenever you like — the rest of the table keeps playing.")
        }
    }

    @ViewBuilder
    private func cashedOutBanner(me: Player, state: GameState) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Label("You've cashed out", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                Text("Final: \(me.chipStack) chips"
                     + (dollarValue(me.chipStack, state).map { " · \($0)" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Table / dealer controls

    @ViewBuilder
    private func tableControlsSection(_ state: GameState) -> some View {
        Section {
            switch state.phase {
            case .betting:
                Button {
                    transport.submit(.collectPots)
                } label: {
                    Label("Collect Pots / Show Down", systemImage: "tray.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(state.isPaused || state.uncollectedCommitted == 0)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            case .waiting:
                Button {
                    transport.submit(.startNewHand)
                } label: {
                    Label("Deal Next Hand", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(state.isPaused || state.seatedPlayers.count < 2)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            case .showdown:
                EmptyView()
            }
        } header: {
            Text("Table")
        } footer: {
            Text("Anyone can manage the table. The host keeps everyone in sync.")
        }
    }

    // MARK: Settle up — create a dollar Game

    @ViewBuilder
    private func settleSection(_ state: GameState) -> some View {
        Section {
            Button {
                showCreateConfirm = true
            } label: {
                Label("Create Settlement Game", systemImage: "dollarsign.arrow.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.phase != .waiting)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        } header: {
            Text("Settle Up")
        } footer: {
            Text(state.phase == .waiting
                 ? "Convert every player's chips into a dollar settlement you can track and pay out. This ends the table."
                 : "Finish the current hand before settling up.")
        }
    }

    private func createSettlementGame() {
        guard let state else { return }
        let game = Game(name: "Virtual Table",
                        buyInAmount: state.buyInDollars,
                        chipCount: state.startingStack,
                        isActive: true)
        modelContext.insert(game)
        for player in state.players.sorted(by: { $0.seatIndex < $1.seatIndex }) {
            let session = PlayerSession(playerName: player.name,
                                        buyInCount: 1,
                                        finalChipCount: player.chipStack,
                                        order: player.seatIndex)
            session.game = game
            game.players.append(session)
        }
        try? modelContext.save()
        transport.stop()
        dismiss()
    }

    // MARK: Showdown — award pots

    @ViewBuilder
    private func showdownSection(_ state: GameState) -> some View {
        ForEach(Array(state.pots.enumerated()), id: \.element.id) { idx, pot in
            Section {
                ForEach(eligiblePlayers(pot, state)) { player in
                    Button {
                        toggleWinner(player.id, in: pot.id)
                    } label: {
                        HStack {
                            Image(systemName: isSelected(player.id, pot.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected(player.id, pot.id) ? .green : .secondary)
                            Text(player.name)
                            Spacer()
                        }
                    }
                    .tint(.primary)
                }

                Button {
                    let winners = Array(winnerSelection[pot.id] ?? [])
                    transport.submit(.award(potID: pot.id, winnerIDs: winners))
                    winnerSelection[pot.id] = nil
                } label: {
                    Label("Award \(pot.amount) chips", systemImage: "trophy.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled((winnerSelection[pot.id] ?? []).isEmpty)
            } header: {
                Text(idx == 0 && state.pots.count > 1 ? "Main pot — pick winner(s)"
                     : state.pots.count > 1 ? "Side pot \(idx) — pick winner(s)"
                     : "Pick winner(s)")
            } footer: {
                Text("Select multiple players to split the pot evenly.")
            }
        }
    }

    private func eligiblePlayers(_ pot: Pot, _ state: GameState) -> [Player] {
        pot.eligiblePlayerIDs.compactMap { id in state.player(id: id) }
    }

    private func isSelected(_ playerID: UUID, _ potID: UUID) -> Bool {
        winnerSelection[potID]?.contains(playerID) ?? false
    }

    private func toggleWinner(_ playerID: UUID, in potID: UUID) {
        var set = winnerSelection[potID] ?? []
        if set.contains(playerID) { set.remove(playerID) } else { set.insert(playerID) }
        winnerSelection[potID] = set
    }
}
