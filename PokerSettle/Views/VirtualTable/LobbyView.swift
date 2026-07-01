import SwiftUI

// MARK: - Lobby
//
// Shown before the game starts. A host configures the stakes and taps Start
// once at least two players are present. A joiner first picks which nearby
// table to join, then waits in that table's roster for the host to start.

struct LobbyView: View {
    @ObservedObject var transport: MultipeerTransport
    @ObservedObject var coordinator: GameCoordinator

    @State private var startingStack = 1000
    @State private var buyInText = "20"
    @State private var joiningHostName: String?

    private var buyInDollars: Double { Double(buyInText) ?? 0 }

    var body: some View {
        List {
            if coordinator.isHost {
                rosterSection(footer: coordinator.lobby.count < 2
                              ? "Waiting for players to join…" : nil)
                hostSettingsSection
                startGameSection
            } else if coordinator.lobby.isEmpty {
                joinSection
            } else {
                rosterSection(footer: "You're in. Waiting for the host to start…")
            }
        }
    }

    // MARK: Roster (host + joined joiner)

    private func rosterSection(footer: String?) -> some View {
        Section {
            ForEach(coordinator.lobby.sorted { $0.joinOrder < $1.joinOrder }) { player in
                HStack {
                    Image(systemName: player.joinOrder == 0 ? "crown.fill" : "person.fill")
                        .foregroundStyle(player.joinOrder == 0 ? .yellow : .secondary)
                    Text(player.name)
                    if player.id == coordinator.localPlayer.id {
                        Text("(You)").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Players (\(coordinator.lobby.count))")
        } footer: {
            if let footer { Text(footer) }
        }
    }

    // MARK: Host controls

    private var hostSettingsSection: some View {
        Section {
            Stepper(value: $startingStack, in: 100...100_000, step: 100) {
                HStack {
                    Image(systemName: "circle.circle.fill").foregroundStyle(.secondary)
                    Text("Starting stack")
                    Spacer()
                    Text("\(startingStack)").foregroundStyle(.secondary)
                }
            }

            HStack {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.secondary)
                Text("Buy-in")
                Spacer()
                Text("$").foregroundStyle(.secondary)
                TextField("20", text: $buyInText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }
        } header: {
            Text("Game Settings")
        } footer: {
            Text("Every player starts with \(startingStack) chips for a $\(buyInText) buy-in. Used to split the cash when you cash out.")
        }
    }

    private var startGameSection: some View {
        Section {
            Button {
                transport.startGame(startingStack: startingStack, buyInDollars: buyInDollars)
            } label: {
                Label("Start Game", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.lobby.count < 2)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
    }

    // MARK: Joiner — pick a table

    @ViewBuilder
    private var joinSection: some View {
        if let joiningHostName {
            Section {
                HStack {
                    ProgressView()
                    Text("Joining \(joiningHostName)…").foregroundStyle(.secondary)
                }
            }
        } else {
            Section {
                if transport.discoveredHosts.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Searching for nearby tables…").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(transport.discoveredHosts) { host in
                        Button {
                            transport.join(host)
                            joiningHostName = host.name
                        } label: {
                            HStack {
                                Image(systemName: "person.2.fill").foregroundStyle(.blue)
                                Text("\(host.name)'s table")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tint(.primary)
                    }
                }
            } header: {
                Text("Nearby Tables")
            } footer: {
                Text("Pick the table to join — make sure everyone joins the same one.")
            }
        }
    }
}
