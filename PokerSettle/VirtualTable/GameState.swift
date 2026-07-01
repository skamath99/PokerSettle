import Foundation

// MARK: - Player
//
// A single struct is the source of truth for a player's chips. There is no
// separate "hand stack" vs "session stack" — `chipStack` is the bank, and
// `committed` / `hasFolded` are the only per-hand state. They reset each hand.

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var chipStack: Int    // chips this player currently owns (the bank)
    var seatIndex: Int    // fixed seat position; determines display order
    var joinOrder: Int    // 0 = first joiner / initial host; lower rank wins host election
    var isConnected: Bool

    // Per-hand state (reset by startNewHand)
    var committed: Int    // chips this player has pushed into the pot this hand
    var hasFolded: Bool   // folded players' chips stay in the pot but can't win

    // Session state: a cashed-out player has left the table with their chips.
    // Their stack is frozen, they sit out all further hands, and their leaving
    // no longer pauses the game. Players may cash out independently, at any time.
    var hasCashedOut: Bool

    init(id: UUID = UUID(),
         name: String,
         chipStack: Int,
         seatIndex: Int,
         joinOrder: Int,
         isConnected: Bool = true,
         committed: Int = 0,
         hasFolded: Bool = false,
         hasCashedOut: Bool = false) {
        self.id = id
        self.name = name
        self.chipStack = chipStack
        self.seatIndex = seatIndex
        self.joinOrder = joinOrder
        self.isConnected = isConnected
        self.committed = committed
        self.hasFolded = hasFolded
        self.hasCashedOut = hasCashedOut
    }
}

// MARK: - Pot
//
// The multi-pot data structure. Each pot is a chip amount plus the set of
// players eligible to win it. Side pots fall out naturally from buildPots:
// when players are all-in for different totals, each distinct level produces
// a pot whose eligible set is everyone who reached that level and hasn't folded.

struct Pot: Identifiable, Codable, Equatable {
    let id: UUID
    var amount: Int
    var eligiblePlayerIDs: [UUID]

    init(id: UUID = UUID(), amount: Int, eligiblePlayerIDs: [UUID]) {
        self.id = id
        self.amount = amount
        self.eligiblePlayerIDs = eligiblePlayerIDs
    }
}

// MARK: - Hand phase
//
// Deliberately minimal. We don't model preflop/flop/turn/river — the users run
// the actual game. We only need to know whether chips can be committed, whether
// pots are being awarded, or whether we're idle between hands.

enum HandPhase: String, Codable, Equatable {
    case waiting    // between hands
    case betting    // chips can be committed / players can fold
    case showdown   // pots have been collected and are being awarded
}

// MARK: - Last action
//
// A record of the most recent thing that happened at the table, so everyone can
// see "John added 50" and work out what they need to match. Display-only; the
// engine derives the actual to-call amount from cumulative commitments.

enum TableAction: Codable, Equatable {
    case added(player: String, amount: Int)
    case folded(player: String)
    case cashedOut(player: String)
    case potsCollected
    case awarded(player: String, amount: Int)
}

// MARK: - Pause reason

enum PauseReason: Codable, Equatable {
    case playerDisconnected(playerName: String)
    case hostTransfer
}

// MARK: - Full replicated game state
//
// Every device holds an identical copy of this. The host mutates it and
// broadcasts; peers apply. `sequenceNumber` increments on every mutation so
// peers can detect a gap and request a full resync.

struct GameState: Codable, Equatable {
    var sessionID: UUID
    var sequenceNumber: Int

    var players: [Player]   // ordered by seatIndex
    var pots: [Pot]
    var phase: HandPhase
    var handNumber: Int

    var isPaused: Bool
    var pauseReason: PauseReason?

    var hostPlayerID: UUID

    // The most recent action, for everyone's situational awareness. Cleared at
    // the start of each hand.
    var lastAction: TableAction?

    // Buy-in economics, fixed at game start. Used to convert final chip counts
    // into dollars when creating a settlement Game. A buyInDollars of 0 means
    // the table is tracking chips only (no dollar settlement configured).
    var startingStack: Int
    var buyInDollars: Double
}

// MARK: - Convenience accessors

extension GameState {
    func player(id: UUID) -> Player? {
        players.first { $0.id == id }
    }

    /// Players still eligible to win (not folded).
    var livePlayers: [Player] {
        players.filter { !$0.hasFolded }
    }

    /// Total chips sitting in all collected pots.
    var totalInPots: Int {
        pots.reduce(0) { $0 + $1.amount }
    }

    /// Chips committed this hand but not yet collected into pots.
    var uncollectedCommitted: Int {
        players.reduce(0) { $0 + $1.committed }
    }

    /// Players still seated and playing (haven't cashed out).
    var seatedPlayers: [Player] {
        players.filter { !$0.hasCashedOut }
    }

    /// The largest amount any still-in player has committed this hand — i.e. the
    /// bet others must match. Works across streets because `committed` is
    /// cumulative, so the shortfall to the leader is always correct.
    var currentBet: Int {
        players.filter { !$0.hasFolded }.map(\.committed).max() ?? 0
    }

    /// How much this player must add to match the current bet (0 = they can check).
    func toCall(for id: UUID) -> Int {
        max(0, currentBet - (player(id: id)?.committed ?? 0))
    }

    /// Dollars per chip, or 0 when no dollar buy-in was configured.
    var chipToDollarRatio: Double {
        guard startingStack > 0, buyInDollars > 0 else { return 0 }
        return buyInDollars / Double(startingStack)
    }
}
