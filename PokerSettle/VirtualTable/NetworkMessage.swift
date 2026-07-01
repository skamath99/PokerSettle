import Foundation

// MARK: - Player identity (lobby)
//
// Lightweight identity exchanged while forming a session, before the full
// GameState exists. `joinOrder` is assigned by the host and drives both seat
// assignment and host-election rank (lowest order wins).

struct PlayerInfo: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var joinOrder: Int

    init(id: UUID = UUID(), name: String, joinOrder: Int = 0) {
        self.id = id
        self.name = name
        self.joinOrder = joinOrder
    }
}

// MARK: - Game request
//
// A request to mutate the game. Peers send these to the host; the host (and
// only the host) applies them through the engine and broadcasts the result.
// This is the complete set of operations the engine exposes.

enum GameRequest: Codable, Equatable {
    case startNewHand
    case commit(playerID: UUID, amount: Int)
    case commitAllIn(playerID: UUID)
    case fold(playerID: UUID)
    case cashOut(playerID: UUID)
    case collectPots
    case award(potID: UUID, winnerIDs: [UUID])
}

// MARK: - Wire message
//
// The full envelope sent between devices over the transport. Every message is
// Codable so it round-trips cleanly through MultipeerConnectivity's Data API.

enum NetMessage: Codable, Equatable {
    // Lobby formation
    case hello(PlayerInfo)              // peer → host: "I'm here, here's my identity"
    case lobbyUpdate([PlayerInfo])      // host → all: current roster
    case startGame(GameState)           // host → all: the game has begun
    case joinRejected(reason: String)   // host → newcomer: roster is locked, you can't join

    // In-game
    case request(GameRequest)           // peer → host: please apply this action
    case stateUpdate(GameState)         // host → all: authoritative new state

    // Recovery
    case syncRequest(lastSeq: Int)      // peer → host: I (re)joined, catch me up
    case syncResponse(GameState)        // host → peer: here's the full state
}

// MARK: - Request dispatch
//
// Central mapping from a wire request to an engine mutation. Keeping it here
// means the coordinator never has to know the engine's method shapes.

extension GameEngine {
    static func apply(_ request: GameRequest, to state: inout GameState) throws {
        switch request {
        case .startNewHand:
            startNewHand(state: &state)
        case .commit(let playerID, let amount):
            try commit(playerID: playerID, amount: amount, state: &state)
        case .commitAllIn(let playerID):
            try commitAllIn(playerID: playerID, state: &state)
        case .fold(let playerID):
            try fold(playerID: playerID, state: &state)
        case .cashOut(let playerID):
            try cashOut(playerID: playerID, state: &state)
        case .collectPots:
            try collectPots(state: &state)
        case .award(let potID, let winnerIDs):
            try award(potID: potID, winnerIDs: winnerIDs, state: &state)
        }
    }
}
