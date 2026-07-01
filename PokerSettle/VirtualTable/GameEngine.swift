import Foundation

// MARK: - Errors

enum GameEngineError: Error, Equatable {
    case playerNotFound
    case playerHasFolded
    case playerCashedOut
    case insufficientChips
    case invalidAmount
    case gamePaused
    case wrongPhase
    case potNotFound
    case noEligibleWinners
    case winnerNotEligible
}

// MARK: - Engine
//
// A minimal chip ledger. It does NOT enforce turns, blinds, raise sizes, or
// betting rounds — the players run the actual poker game. The engine only:
//   1. tracks each player's chip stack,
//   2. moves chips into the pot (commit) and marks folds,
//   3. splits committed chips into main + side pots correctly, and
//   4. awards pots to declared winners.
//
// Every mutating operation bumps `sequenceNumber` so the networking layer can
// broadcast a monotonically increasing stream and peers can detect gaps.

struct GameEngine {

    // MARK: Session setup

    static func startSession(players: [Player],
                             startingStack: Int = 0,
                             buyInDollars: Double = 0,
                             hostPlayerID: UUID? = nil) -> GameState {
        let ordered = players.sorted { $0.seatIndex < $1.seatIndex }
        let host = hostPlayerID
            ?? ordered.min(by: { $0.joinOrder < $1.joinOrder })?.id
            ?? ordered.first!.id
        return GameState(
            sessionID: UUID(),
            sequenceNumber: 0,
            players: ordered,
            pots: [],
            phase: .waiting,
            handNumber: 0,
            isPaused: false,
            pauseReason: nil,
            hostPlayerID: host,
            lastAction: nil,
            startingStack: startingStack,
            buyInDollars: buyInDollars
        )
    }

    // MARK: Hand lifecycle

    /// Begin a new hand: clear pots, reset per-hand state, enter betting.
    static func startNewHand(state: inout GameState) {
        state.handNumber += 1
        state.phase = .betting
        state.pots = []
        state.isPaused = false
        state.pauseReason = nil
        state.lastAction = nil
        for i in state.players.indices {
            state.players[i].committed = 0
            // Cashed-out players sit out every hand; everyone else is dealt in.
            state.players[i].hasFolded = state.players[i].hasCashedOut
        }
        state.sequenceNumber += 1
    }

    // MARK: Betting

    /// Move `amount` chips from a player's stack into their hand commitment.
    /// Use this for blinds, bets, calls, and raises alike — the engine doesn't
    /// distinguish. To go all-in, commit the player's full `chipStack`.
    static func commit(playerID: UUID, amount: Int, state: inout GameState) throws {
        guard !state.isPaused else { throw GameEngineError.gamePaused }
        guard state.phase == .betting else { throw GameEngineError.wrongPhase }
        guard amount > 0 else { throw GameEngineError.invalidAmount }
        guard let idx = state.players.firstIndex(where: { $0.id == playerID }) else {
            throw GameEngineError.playerNotFound
        }
        guard !state.players[idx].hasCashedOut else { throw GameEngineError.playerCashedOut }
        guard !state.players[idx].hasFolded else { throw GameEngineError.playerHasFolded }
        guard amount <= state.players[idx].chipStack else { throw GameEngineError.insufficientChips }

        state.players[idx].chipStack -= amount
        state.players[idx].committed += amount
        state.lastAction = .added(player: state.players[idx].name, amount: amount)
        state.sequenceNumber += 1
    }

    /// Convenience: commit a player's entire remaining stack.
    static func commitAllIn(playerID: UUID, state: inout GameState) throws {
        guard let p = state.player(id: playerID) else { throw GameEngineError.playerNotFound }
        guard p.chipStack > 0 else { throw GameEngineError.insufficientChips }
        try commit(playerID: playerID, amount: p.chipStack, state: &state)
    }

    /// Mark a player as folded. Their committed chips stay in the pot.
    static func fold(playerID: UUID, state: inout GameState) throws {
        guard !state.isPaused else { throw GameEngineError.gamePaused }
        guard state.phase == .betting else { throw GameEngineError.wrongPhase }
        guard let idx = state.players.firstIndex(where: { $0.id == playerID }) else {
            throw GameEngineError.playerNotFound
        }
        guard !state.players[idx].hasCashedOut else { throw GameEngineError.playerCashedOut }
        state.players[idx].hasFolded = true
        state.lastAction = .folded(player: state.players[idx].name)
        state.sequenceNumber += 1
    }

    // MARK: Cash out

    /// A player leaves the table with their current chips. Their stack is frozen
    /// and they sit out the rest of the session. Allowed at any time, and each
    /// player cashes out independently — others keep playing. This is also the
    /// clean way to leave for good without stranding everyone on a paused game.
    static func cashOut(playerID: UUID, state: inout GameState) throws {
        guard let idx = state.players.firstIndex(where: { $0.id == playerID }) else {
            throw GameEngineError.playerNotFound
        }
        guard !state.players[idx].hasCashedOut else { return }   // idempotent
        state.players[idx].hasCashedOut = true
        state.players[idx].hasFolded = true                      // out of any live hand
        state.lastAction = .cashedOut(player: state.players[idx].name)
        state.sequenceNumber += 1
    }

    // MARK: Showdown

    /// Collapse all committed chips into main + side pots and enter showdown.
    /// Pots with a single eligible player (e.g. an uncalled bet) are returned to
    /// that player automatically. If every pot resolves this way the hand ends.
    static func collectPots(state: inout GameState) throws {
        guard state.phase == .betting else { throw GameEngineError.wrongPhase }

        // Chips committed above the highest *live* (non-folded) commitment can
        // never be won by anyone — return that uncalled excess to whoever put it
        // in. This covers a folded player's over-bet and the everyone-folds case,
        // and guarantees every resulting pot has at least one eligible winner.
        let liveMax = state.players.filter { !$0.hasFolded }.map(\.committed).max() ?? 0
        for i in state.players.indices where state.players[i].committed > liveMax {
            let excess = state.players[i].committed - liveMax
            state.players[i].chipStack += excess
            state.players[i].committed -= excess
        }

        state.pots = buildPots(players: state.players)
        for i in state.players.indices { state.players[i].committed = 0 }

        // Auto-return any pot only one player is eligible for.
        state.pots.removeAll { pot in
            guard pot.eligiblePlayerIDs.count == 1 else { return false }
            if let pi = state.players.firstIndex(where: { $0.id == pot.eligiblePlayerIDs[0] }) {
                state.players[pi].chipStack += pot.amount
            }
            return true
        }

        state.phase = state.pots.isEmpty ? .waiting : .showdown
        state.lastAction = .potsCollected
        state.sequenceNumber += 1
    }

    /// Award a single pot to one or more declared winners (a tie splits evenly;
    /// the odd remainder chip goes to the winner in the lowest seat). When the
    /// last pot is awarded the hand returns to `waiting`.
    static func award(potID: UUID, winnerIDs: [UUID], state: inout GameState) throws {
        guard state.phase == .showdown else { throw GameEngineError.wrongPhase }
        guard !winnerIDs.isEmpty else { throw GameEngineError.noEligibleWinners }
        guard let potIdx = state.pots.firstIndex(where: { $0.id == potID }) else {
            throw GameEngineError.potNotFound
        }

        let pot = state.pots[potIdx]
        for w in winnerIDs where !pot.eligiblePlayerIDs.contains(w) {
            throw GameEngineError.winnerNotEligible
        }

        // Split evenly; remainder to the lowest-seat winner for determinism.
        let share = pot.amount / winnerIDs.count
        let remainder = pot.amount % winnerIDs.count
        let remainderWinner = state.players
            .filter { winnerIDs.contains($0.id) }
            .min(by: { $0.seatIndex < $1.seatIndex })?.id

        for w in winnerIDs {
            if let pi = state.players.firstIndex(where: { $0.id == w }) {
                state.players[pi].chipStack += share + (w == remainderWinner ? remainder : 0)
            }
        }

        let winnerNames = winnerIDs
            .compactMap { id in state.player(id: id)?.name }
            .joined(separator: " & ")
        state.lastAction = .awarded(player: winnerNames, amount: pot.amount)

        state.pots.remove(at: potIdx)
        if state.pots.isEmpty { state.phase = .waiting }
        state.sequenceNumber += 1
    }

    // MARK: Pot construction (pure; exposed for testing)

    /// Build main + side pots from each player's total committed chips.
    ///
    /// For each distinct commitment level, every player contributes the slice of
    /// their commitment that falls in that band. A pot's eligible winners are the
    /// non-folded players who reached that level. Adjacent levels with an
    /// identical eligible set are merged so we don't emit redundant pots.
    static func buildPots(players: [Player]) -> [Pot] {
        let levels = Array(Set(players.map { $0.committed }))
            .filter { $0 > 0 }
            .sorted()

        var pots: [Pot] = []
        var prev = 0

        for level in levels {
            let amount = players.reduce(0) { sum, p in
                sum + min(p.committed, level) - min(p.committed, prev)
            }
            let eligible = players
                .filter { !$0.hasFolded && $0.committed >= level }
                .map { $0.id }

            if amount > 0 {
                if !pots.isEmpty, Set(pots[pots.count - 1].eligiblePlayerIDs) == Set(eligible) {
                    pots[pots.count - 1].amount += amount
                } else {
                    pots.append(Pot(amount: amount, eligiblePlayerIDs: eligible))
                }
            }
            prev = level
        }
        return pots
    }

    // MARK: Connectivity

    /// A player dropped. Pause the game until everyone is back — unless the one
    /// who left had already cashed out, in which case the table plays on.
    static func playerDisconnected(playerID: UUID, state: inout GameState) {
        guard let idx = state.players.firstIndex(where: { $0.id == playerID }) else { return }
        state.players[idx].isConnected = false
        if !state.players[idx].hasCashedOut {
            state.isPaused = true
            state.pauseReason = .playerDisconnected(playerName: state.players[idx].name)
        }
        state.sequenceNumber += 1
    }

    /// A player came back. Resume once everyone who still needs to be present is
    /// connected — cashed-out players are gone for good and don't block resuming.
    static func playerReconnected(playerID: UUID, state: inout GameState) {
        guard let idx = state.players.firstIndex(where: { $0.id == playerID }) else { return }
        state.players[idx].isConnected = true
        if state.players.allSatisfy({ $0.isConnected || $0.hasCashedOut }) {
            state.isPaused = false
            state.pauseReason = nil
        }
        state.sequenceNumber += 1
    }

    /// Promote a new host (leader election after the old host dropped).
    static func promoteHost(newHostID: UUID, state: inout GameState) {
        state.hostPlayerID = newHostID
        state.pauseReason = .hostTransfer
        state.sequenceNumber += 1
    }

    /// Deterministic next host: lowest join order among connected players who
    /// are still seated (a cashed-out player never becomes host).
    static func electHost(state: GameState) -> UUID? {
        state.players
            .filter { $0.isConnected && !$0.hasCashedOut }
            .min(by: { $0.joinOrder < $1.joinOrder })?
            .id
    }
}
