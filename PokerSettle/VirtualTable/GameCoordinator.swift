import Foundation

// MARK: - Effects
//
// The coordinator is pure with respect to the network: it never touches a
// socket. Instead it returns a list of effects describing what should be sent
// and what the user should be told. A transport (MultipeerConnectivity, or the
// in-memory test harness) executes them. This keeps all distributed logic
// unit-testable without real radios.

enum Recipient: Equatable {
    case all                // every connected peer
    case host               // whoever currently holds hostPlayerID
    case player(UUID)       // one specific player
}

enum NetEffect: Equatable {
    case send(NetMessage, to: Recipient)
    case notify(String)     // user-facing message (disconnect, host change, etc.)
}

// MARK: - Coordinator
//
// One per device. Holds this device's view of the world and decides, for every
// inbound event, how to mutate state and what to emit. The host is the single
// authoritative mutator of GameState; peers send requests and adopt whatever
// the host broadcasts. On host loss, peers run a deterministic election and
// exactly one promotes itself — no voting round needed.

final class GameCoordinator: ObservableObject {

    let localPlayer: PlayerInfo
    private let isInitialHost: Bool

    @Published private(set) var lobby: [PlayerInfo] = []
    @Published private(set) var state: GameState?
    /// Set when the host refuses our join because the game is already underway.
    @Published private(set) var rejectionMessage: String?

    init(localPlayer: PlayerInfo, isInitialHost: Bool) {
        self.localPlayer = localPlayer
        self.isInitialHost = isInitialHost
        if isInitialHost {
            var me = localPlayer
            me.joinOrder = 0
            lobby = [me]
        }
    }

    /// Whether this device is currently the authoritative host.
    var isHost: Bool {
        if let s = state { return s.hostPlayerID == localPlayer.id }
        return isInitialHost
    }

    // MARK: Inbound dispatch

    /// Route any received wire message to its handler and return resulting effects.
    func receive(_ message: NetMessage, from sender: UUID) -> [NetEffect] {
        switch message {
        case .hello(let info):           return handleHello(info)
        case .lobbyUpdate(let players):  handleLobbyUpdate(players);  return []
        case .startGame(let s):          handleStartGame(s);          return []
        case .joinRejected(let reason):  rejectionMessage = reason;   return []
        case .request(let req):          return handleRequest(req, from: sender)
        case .stateUpdate(let s):        return handleStateUpdate(s)
        case .syncRequest:               return handleSyncRequest(from: sender)
        case .syncResponse(let s):       handleSyncResponse(s);       return []
        }
    }

    // MARK: Lobby

    /// Called on a peer once it has connected to the host, to announce identity.
    func announceSelf() -> [NetEffect] {
        guard !isInitialHost, state == nil, rejectionMessage == nil else { return [] }
        return [.send(.hello(localPlayer), to: .host)]
    }

    private func handleHello(_ info: PlayerInfo) -> [NetEffect] {
        guard isHost else { return [] }

        // Game already started: the roster is locked. A known member saying
        // hello again is someone returning (they left or relaunched and lost
        // their state) — treat it as a reconnect and catch them back up. Anyone
        // else is a late joiner and is turned away rather than shown the table.
        if state != nil {
            if state?.player(id: info.id) != nil {
                return peerReconnected(playerID: info.id)
            }
            return [.send(.joinRejected(reason: "This game is already in progress."),
                          to: .player(info.id))]
        }

        // Lobby: add to the roster.
        if !lobby.contains(where: { $0.id == info.id }) {
            var added = info
            added.joinOrder = lobby.count   // deterministic, in arrival order
            lobby.append(added)
        }
        return [.send(.lobbyUpdate(lobby), to: .all)]
    }

    private func handleLobbyUpdate(_ players: [PlayerInfo]) {
        guard state == nil else { return }
        lobby = players
    }

    /// Host begins the game from the assembled lobby. `buyInDollars` is the
    /// dollar value of one starting stack, used later for dollar settlement.
    func startGame(startingStack: Int, buyInDollars: Double = 0) -> [NetEffect] {
        guard isHost, state == nil, lobby.count >= 2 else { return [] }
        let players = lobby
            .sorted { $0.joinOrder < $1.joinOrder }
            .enumerated()
            .map { idx, info in
                Player(id: info.id,
                       name: info.name,
                       chipStack: startingStack,
                       seatIndex: idx,
                       joinOrder: info.joinOrder)
            }
        var s = GameEngine.startSession(players: players,
                                        startingStack: startingStack,
                                        buyInDollars: buyInDollars,
                                        hostPlayerID: localPlayer.id)
        GameEngine.startNewHand(state: &s)
        state = s
        return [.send(.startGame(s), to: .all)]
    }

    private func handleStartGame(_ s: GameState) {
        // A host runs its own game and never joins someone else's.
        guard !isInitialHost else { return }
        state = s
    }

    // MARK: In-game requests

    /// Called by the local UI to request an action. The host applies it
    /// immediately and broadcasts; a peer forwards it to the host.
    func submit(_ request: GameRequest) -> [NetEffect] {
        guard state != nil else { return [] }
        return isHost ? applyAndBroadcast(request) : [.send(.request(request), to: .host)]
    }

    private func handleRequest(_ request: GameRequest, from sender: UUID) -> [NetEffect] {
        guard isHost else { return [] }   // only the host applies requests
        return applyAndBroadcast(request)
    }

    private func applyAndBroadcast(_ request: GameRequest) -> [NetEffect] {
        guard var s = state else { return [] }
        do {
            try GameEngine.apply(request, to: &s)
            state = s
            return [.send(.stateUpdate(s), to: .all)]
        } catch {
            // Invalid request (e.g. acting while paused, over-committing).
            // The host is authoritative, so we simply drop it. The requester's
            // UI will stay consistent with the last broadcast state.
            return []
        }
    }

    private func handleStateUpdate(_ incoming: GameState) -> [NetEffect] {
        guard rejectionMessage == nil else { return [] }  // turned away: never adopt state
        // A host waiting in its own lobby must not be pulled into another game.
        guard !(isInitialHost && state == nil) else { return [] }
        guard let current = state else {
            state = incoming
            return []
        }
        // Full-state broadcasts mean we can always jump to a newer sequence
        // without replay. If we somehow see an older one, ignore it.
        if incoming.sequenceNumber > current.sequenceNumber {
            state = incoming
        }
        return []
    }

    // MARK: Recovery / sync

    /// Called when this device (re)connects and needs to be caught up.
    func requestSync() -> [NetEffect] {
        guard !isHost else { return [] }
        return [.send(.syncRequest(lastSeq: state?.sequenceNumber ?? -1), to: .host)]
    }

    private func handleSyncRequest(from sender: UUID) -> [NetEffect] {
        guard isHost, let s = state else { return [] }
        return [.send(.syncResponse(s), to: .player(sender))]
    }

    private func handleSyncResponse(_ s: GameState) {
        if s.sequenceNumber >= (state?.sequenceNumber ?? -1) {
            state = s
        }
    }

    // MARK: Connectivity

    /// A peer dropped off the mesh. Pause the game; if the host dropped, the
    /// lowest-join-order surviving player promotes itself. Only the (new) host
    /// mutates authoritative state to keep the sequence number consistent.
    func peerDisconnected(playerID: UUID) -> [NetEffect] {
        guard let current = state else { return [] }
        let name = current.player(id: playerID)?.name ?? "A player"
        var effects: [NetEffect] = [.notify("\(name) disconnected — game paused")]

        if playerID == current.hostPlayerID {
            // Host is gone. Run the deterministic election locally.
            var probe = current
            GameEngine.playerDisconnected(playerID: playerID, state: &probe)
            if GameEngine.electHost(state: probe) == localPlayer.id {
                GameEngine.promoteHost(newHostID: localPlayer.id, state: &probe)
                state = probe
                effects.append(.notify("You are now the host"))
                effects.append(.send(.stateUpdate(probe), to: .all))
            }
            // Non-elected peers wait for the new host's broadcast.
        } else if isHost {
            var s = current
            GameEngine.playerDisconnected(playerID: playerID, state: &s)
            state = s
            effects.append(.send(.stateUpdate(s), to: .all))
        }
        return effects
    }

    /// A peer (re)joined the mesh. The host marks it connected and broadcasts;
    /// the game resumes once everyone is back. (The rejoining device separately
    /// calls `requestSync()` to catch itself up.)
    func peerReconnected(playerID: UUID) -> [NetEffect] {
        guard isHost, let current = state else { return [] }
        guard current.player(id: playerID) != nil else { return [] }  // ignore unknown devices
        var s = current
        let wasPaused = s.isPaused
        GameEngine.playerReconnected(playerID: playerID, state: &s)
        state = s
        var effects: [NetEffect] = [.send(.stateUpdate(s), to: .all)]
        if wasPaused && !s.isPaused {
            effects.append(.notify("All players reconnected — game resumed"))
        }
        return effects
    }
}
