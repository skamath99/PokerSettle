import SwiftUI

// MARK: - Entry point
//
// Presented full-screen from the game list. Walks the user through setup
// (name + host/join), then hands off to the live session. Full-screen (not a
// sheet) so an accidental swipe can't tear down an in-progress game.

struct VirtualTableView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var transport: MultipeerTransport?

    // A stable identity that survives leaving and relaunching, so a player who
    // steps away can rejoin their existing seat instead of looking like a brand
    // new device (which would be turned away from an in-progress game).
    private static func persistentPlayerID() -> UUID {
        let key = "VirtualTablePlayerID"
        if let stored = UserDefaults.standard.string(forKey: key),
           let id = UUID(uuidString: stored) {
            return id
        }
        let id = UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        return id
    }

    var body: some View {
        NavigationStack {
            Group {
                if let transport {
                    SessionView(transport: transport)
                } else {
                    VirtualTableSetupView { name, isHost in
                        let t = MultipeerTransport(
                            localPlayer: PlayerInfo(id: Self.persistentPlayerID(), name: name),
                            isInitialHost: isHost
                        )
                        if isHost { t.startHosting() } else { t.startBrowsing() }
                        transport = t
                    }
                }
            }
            .navigationTitle("Virtual Table")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Leave") {
                        transport?.stop()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Setup

private struct VirtualTableSetupView: View {
    let onStart: (_ name: String, _ isHost: Bool) -> Void

    @State private var name: String = ""
    @FocusState private var nameFocused: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
            } header: {
                Text("Who are you?")
            } footer: {
                Text("This is how other players at the table will see you.")
            }

            Section {
                Button {
                    onStart(trimmedName, true)
                } label: {
                    Label("Host a Table", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(trimmedName.isEmpty)

                Button {
                    onStart(trimmedName, false)
                } label: {
                    Label("Join a Nearby Table", systemImage: "person.2.wave.2")
                }
                .disabled(trimmedName.isEmpty)
            } footer: {
                Text("Hosting and joining work over Bluetooth and local Wi-Fi — no internet needed. Everyone must keep the app open and in the foreground.")
            }
        }
        .onAppear { nameFocused = true }
    }
}

// MARK: - Session container
//
// Observes both the transport (banners, foreground state) and its coordinator
// (lobby + game state) and shows the lobby until the game starts.

struct SessionView: View {
    @ObservedObject var transport: MultipeerTransport
    @ObservedObject var coordinator: GameCoordinator

    init(transport: MultipeerTransport) {
        self.transport = transport
        self.coordinator = transport.coordinator
    }

    var body: some View {
        VStack(spacing: 0) {
            if !transport.isForeground {
                ForegroundReminderBanner()
            }
            if let rejection = coordinator.rejectionMessage {
                RejectionView(message: rejection)
            } else if coordinator.state == nil {
                LobbyView(transport: transport, coordinator: coordinator)
            } else {
                TableView(transport: transport, coordinator: coordinator)
            }
        }
    }
}

// MARK: - Shared banner

struct ForegroundReminderBanner: View {
    var body: some View {
        Label("Keep PokerSettle open to stay connected", systemImage: "exclamationmark.triangle.fill")
            .font(.footnote.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.yellow.opacity(0.25))
            .foregroundStyle(.primary)
    }
}

// MARK: - Rejection

struct RejectionView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.orange)
            Text("Can't Join")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Text("Tap Leave to go back.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
