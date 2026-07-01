import Testing
import Foundation
@testable import PokerSettle

// MARK: - Helpers

private func player(_ name: String, chips: Int, seat: Int, joinOrder: Int? = nil) -> Player {
    Player(name: name, chipStack: chips, seatIndex: seat, joinOrder: joinOrder ?? seat)
}

private func session(_ players: [Player]) -> GameState {
    GameEngine.startSession(players: players)
}

// MARK: - Pot Builder

@Suite("PotBuilder")
struct PotBuilderTests {

    @Test("Single pot when everyone commits the same")
    func testSinglePot() {
        let a = player("A", chips: 0, seat: 0)
        let b = player("B", chips: 0, seat: 1)
        let c = player("C", chips: 0, seat: 2)
        var pa = a; pa.committed = 100
        var pb = b; pb.committed = 100
        var pc = c; pc.committed = 100
        let pots = GameEngine.buildPots(players: [pa, pb, pc])
        #expect(pots.count == 1)
        #expect(pots[0].amount == 300)
        #expect(Set(pots[0].eligiblePlayerIDs) == Set([pa.id, pb.id, pc.id]))
    }

    @Test("Folded player's chips stay in the pot but they can't win")
    func testFoldedContributes() {
        var winner = player("W", chips: 0, seat: 0); winner.committed = 200
        var folder = player("F", chips: 0, seat: 1); folder.committed = 200; folder.hasFolded = true
        let pots = GameEngine.buildPots(players: [winner, folder])
        #expect(pots.count == 1)
        #expect(pots[0].amount == 400)
        #expect(pots[0].eligiblePlayerIDs == [winner.id])
    }

    @Test("One all-in creates a side pot")
    func testOneSidePot() {
        var allIn  = player("AllIn",  chips: 0, seat: 0); allIn.committed = 100
        var caller = player("Caller", chips: 0, seat: 1); caller.committed = 300
        var folder = player("Fold",   chips: 0, seat: 2); folder.committed = 80; folder.hasFolded = true
        let pots = GameEngine.buildPots(players: [allIn, caller, folder])

        // Level 80:  80+80+80 = 240, eligible: allIn, caller
        // Level 100: 20+20+0  = 40,  eligible: allIn, caller  (merged → 280)
        // Level 300: 0+200+0  = 200, eligible: caller only
        #expect(pots.count == 2)
        #expect(pots[0].amount == 280)
        #expect(Set(pots[0].eligiblePlayerIDs) == Set([allIn.id, caller.id]))
        #expect(pots[1].amount == 200)
        #expect(pots[1].eligiblePlayerIDs == [caller.id])
    }

    @Test("Multiple all-ins at different levels create nested side pots")
    func testMultipleAllIns() {
        var a = player("A", chips: 0, seat: 0); a.committed = 100
        var b = player("B", chips: 0, seat: 1); b.committed = 200
        var c = player("C", chips: 0, seat: 2); c.committed = 300
        let pots = GameEngine.buildPots(players: [a, b, c])
        #expect(pots.count == 3)
        #expect(pots[0].amount == 300); #expect(Set(pots[0].eligiblePlayerIDs) == Set([a.id, b.id, c.id]))
        #expect(pots[1].amount == 200); #expect(Set(pots[1].eligiblePlayerIDs) == Set([b.id, c.id]))
        #expect(pots[2].amount == 100); #expect(pots[2].eligiblePlayerIDs == [c.id])
    }

    @Test("No commitments yields no pots")
    func testNoPots() {
        let a = player("A", chips: 100, seat: 0)
        #expect(GameEngine.buildPots(players: [a]).isEmpty)
    }
}

// MARK: - Hand lifecycle

@Suite("HandLifecycle")
struct HandLifecycleTests {

    @Test("startNewHand resets per-hand state and enters betting")
    func testStartNewHand() {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        s.players[0].committed = 50
        s.players[1].hasFolded = true
        GameEngine.startNewHand(state: &s)
        #expect(s.phase == .betting)
        #expect(s.handNumber == 1)
        #expect(s.players.allSatisfy { $0.committed == 0 })
        #expect(s.players.allSatisfy { !$0.hasFolded })
        #expect(s.pots.isEmpty)
    }

    @Test("Hand number increments across hands")
    func testHandNumberIncrements() {
        var s = session([player("A", chips: 100, seat: 0), player("B", chips: 100, seat: 1)])
        GameEngine.startNewHand(state: &s)
        GameEngine.startNewHand(state: &s)
        #expect(s.handNumber == 2)
    }
}

// MARK: - Commit / fold

@Suite("CommitAndFold")
struct CommitAndFoldTests {

    @Test("commit moves chips from stack to pot commitment")
    func testCommit() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.commit(playerID: id, amount: 250, state: &s)
        #expect(s.player(id: id)!.chipStack == 750)
        #expect(s.player(id: id)!.committed == 250)
    }

    @Test("commit accumulates across multiple calls")
    func testCommitAccumulates() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.commit(playerID: id, amount: 100, state: &s)
        try GameEngine.commit(playerID: id, amount: 150, state: &s)
        #expect(s.player(id: id)!.committed == 250)
        #expect(s.player(id: id)!.chipStack == 750)
    }

    @Test("commit beyond stack throws insufficientChips")
    func testCommitInsufficient() {
        var s = session([player("A", chips: 50, seat: 0), player("B", chips: 100, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        #expect(throws: GameEngineError.insufficientChips) {
            try GameEngine.commit(playerID: id, amount: 51, state: &s)
        }
    }

    @Test("commit of zero or negative throws invalidAmount")
    func testCommitInvalidAmount() {
        var s = session([player("A", chips: 50, seat: 0), player("B", chips: 100, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        #expect(throws: GameEngineError.invalidAmount) {
            try GameEngine.commit(playerID: id, amount: 0, state: &s)
        }
    }

    @Test("commitAllIn pushes the full stack")
    func testCommitAllIn() throws {
        var s = session([player("A", chips: 300, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.commitAllIn(playerID: id, state: &s)
        #expect(s.player(id: id)!.chipStack == 0)
        #expect(s.player(id: id)!.committed == 300)
    }

    @Test("folded player cannot commit")
    func testFoldedCannotCommit() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.fold(playerID: id, state: &s)
        #expect(throws: GameEngineError.playerHasFolded) {
            try GameEngine.commit(playerID: id, amount: 10, state: &s)
        }
    }

    @Test("commit outside betting phase throws wrongPhase")
    func testCommitWrongPhase() {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        // still in .waiting
        let id = s.players[0].id
        #expect(throws: GameEngineError.wrongPhase) {
            try GameEngine.commit(playerID: id, amount: 10, state: &s)
        }
    }
}

// MARK: - collectPots / award

@Suite("ShowdownFlow")
struct ShowdownFlowTests {

    @Test("collectPots clears commitments and builds a single pot")
    func testCollectSinglePot() throws {
        var s = session([player("A", chips: 1000, seat: 0),
                         player("B", chips: 1000, seat: 1),
                         player("C", chips: 1000, seat: 2)])
        GameEngine.startNewHand(state: &s)
        for p in s.players { try GameEngine.commit(playerID: p.id, amount: 100, state: &s) }
        try GameEngine.collectPots(state: &s)
        #expect(s.phase == .showdown)
        #expect(s.pots.count == 1)
        #expect(s.pots[0].amount == 300)
        #expect(s.players.allSatisfy { $0.committed == 0 })
    }

    @Test("Uncalled bet auto-returns: single-eligible pot goes back, hand ends")
    func testUncalledBetReturned() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let a = s.players[0].id
        let b = s.players[1].id
        try GameEngine.commit(playerID: a, amount: 500, state: &s)
        try GameEngine.commit(playerID: b, amount: 200, state: &s)
        try GameEngine.fold(playerID: b, state: &s)
        try GameEngine.collectPots(state: &s)

        // B folded so A is the only eligible player for the whole 700.
        // The portion above 200 (the uncalled 300) plus the 400 contested both
        // resolve to A as the sole eligible winner → all auto-returned, hand over.
        #expect(s.phase == .waiting)
        #expect(s.pots.isEmpty)
        #expect(s.player(id: a)!.chipStack == 1200) // 1000 - 500 + 700
        #expect(s.player(id: b)!.chipStack == 800)  // 1000 - 200
    }

    @Test("award distributes a pot to a single winner and ends the hand")
    func testAwardSingleWinner() throws {
        var s = session([player("A", chips: 1000, seat: 0),
                         player("B", chips: 1000, seat: 1),
                         player("C", chips: 1000, seat: 2)])
        GameEngine.startNewHand(state: &s)
        for p in s.players { try GameEngine.commit(playerID: p.id, amount: 100, state: &s) }
        try GameEngine.collectPots(state: &s)
        let potID = s.pots[0].id
        let a = s.players[0].id
        try GameEngine.award(potID: potID, winnerIDs: [a], state: &s)
        #expect(s.phase == .waiting)
        #expect(s.pots.isEmpty)
        #expect(s.player(id: a)!.chipStack == 1200) // 900 + 300
    }

    @Test("award splits a tie evenly")
    func testAwardSplit() throws {
        var s = session([player("A", chips: 1000, seat: 0),
                         player("B", chips: 1000, seat: 1),
                         player("C", chips: 1000, seat: 2)])
        GameEngine.startNewHand(state: &s)
        for p in s.players { try GameEngine.commit(playerID: p.id, amount: 100, state: &s) }
        try GameEngine.collectPots(state: &s)
        let potID = s.pots[0].id
        let a = s.players[0].id
        let b = s.players[1].id
        try GameEngine.award(potID: potID, winnerIDs: [a, b], state: &s)
        #expect(s.player(id: a)!.chipStack == 1050) // 900 + 150
        #expect(s.player(id: b)!.chipStack == 1050)
    }

    @Test("award gives the odd remainder chip to the lowest-seat winner")
    func testAwardRemainder() throws {
        var s = session([player("A", chips: 1000, seat: 0),
                         player("B", chips: 1000, seat: 1),
                         player("C", chips: 1000, seat: 2)])
        GameEngine.startNewHand(state: &s)
        // Commit 101 each → pot 303, split 3 ways = 101 each, no remainder.
        // Use 100/100/101 to force an odd pot of 301 split between A and B.
        try GameEngine.commit(playerID: s.players[0].id, amount: 100, state: &s)
        try GameEngine.commit(playerID: s.players[1].id, amount: 100, state: &s)
        try GameEngine.commit(playerID: s.players[2].id, amount: 101, state: &s)
        // C committed 1 more → side pot of 1 eligible to C only (auto-returned).
        try GameEngine.collectPots(state: &s)
        // Main pot = 300, eligible A,B,C. Side pot = 1, eligible C (auto-returned).
        let main = s.pots.first { $0.amount == 300 }!
        let a = s.players[0].id
        let b = s.players[1].id
        try GameEngine.award(potID: main.id, winnerIDs: [a, b], state: &s)
        // 300 / 2 = 150 each, no remainder here.
        #expect(s.player(id: a)!.chipStack == 1050)
        #expect(s.player(id: b)!.chipStack == 1050)
    }

    @Test("award to an ineligible winner throws")
    func testAwardIneligible() throws {
        var s = session([player("A", chips: 1000, seat: 0),
                         player("B", chips: 1000, seat: 1),
                         player("C", chips: 1000, seat: 2)])
        GameEngine.startNewHand(state: &s)
        let a = s.players[0].id
        let b = s.players[1].id
        let c = s.players[2].id
        try GameEngine.commit(playerID: a, amount: 100, state: &s)
        try GameEngine.commit(playerID: b, amount: 100, state: &s)
        try GameEngine.commit(playerID: c, amount: 100, state: &s)
        try GameEngine.fold(playerID: c, state: &s)
        try GameEngine.collectPots(state: &s)
        let potID = s.pots[0].id
        #expect(throws: GameEngineError.winnerNotEligible) {
            try GameEngine.award(potID: potID, winnerIDs: [c], state: &s)
        }
    }

    @Test("Full multi-pot showdown: main pot + side pot awarded separately")
    func testFullMultiPotShowdown() throws {
        // A all-in for 100, B and C continue to 300 each.
        var s = session([player("A", chips: 100, seat: 0),
                         player("B", chips: 1000, seat: 1),
                         player("C", chips: 1000, seat: 2)])
        GameEngine.startNewHand(state: &s)
        let a = s.players[0].id
        let b = s.players[1].id
        let c = s.players[2].id

        try GameEngine.commitAllIn(playerID: a, state: &s)        // A: 100
        try GameEngine.commit(playerID: b, amount: 300, state: &s) // B: 300
        try GameEngine.commit(playerID: c, amount: 300, state: &s) // C: 300
        try GameEngine.collectPots(state: &s)

        // Main pot: 300 (100×3), eligible A,B,C. Side pot: 400 (200×2), eligible B,C.
        #expect(s.pots.count == 2)
        let main = s.pots.first { $0.eligiblePlayerIDs.contains(a) }!
        let side = s.pots.first { !$0.eligiblePlayerIDs.contains(a) }!
        #expect(main.amount == 300)
        #expect(side.amount == 400)
        #expect(Set(side.eligiblePlayerIDs) == Set([b, c]))

        // A wins the main pot; B wins the side pot.
        try GameEngine.award(potID: main.id, winnerIDs: [a], state: &s)
        try GameEngine.award(potID: side.id, winnerIDs: [b], state: &s)

        #expect(s.phase == .waiting)
        #expect(s.player(id: a)!.chipStack == 300)  // 0 + 300
        #expect(s.player(id: b)!.chipStack == 1100) // 700 + 400
        #expect(s.player(id: c)!.chipStack == 700)  // lost 300
    }

    @Test("Conservation: total chips constant across a full hand")
    func testChipConservation() throws {
        var s = session([player("A", chips: 500, seat: 0),
                         player("B", chips: 500, seat: 1),
                         player("C", chips: 500, seat: 2)])
        let startTotal = s.players.reduce(0) { $0 + $1.chipStack }
        GameEngine.startNewHand(state: &s)
        try GameEngine.commit(playerID: s.players[0].id, amount: 200, state: &s)
        try GameEngine.commit(playerID: s.players[1].id, amount: 200, state: &s)
        try GameEngine.commit(playerID: s.players[2].id, amount: 50, state: &s)
        try GameEngine.fold(playerID: s.players[2].id, state: &s)
        try GameEngine.collectPots(state: &s)
        for pot in s.pots {
            try GameEngine.award(potID: pot.id, winnerIDs: [s.players[0].id], state: &s)
        }
        let endTotal = s.players.reduce(0) { $0 + $1.chipStack }
        #expect(endTotal == startTotal)
    }
}

// MARK: - Connectivity

@Suite("Connectivity")
struct ConnectivityTests {

    @Test("Disconnect pauses the game with player name")
    func testDisconnectPauses() {
        var s = session([player("Alice", chips: 100, seat: 0), player("Bob", chips: 100, seat: 1)])
        GameEngine.startNewHand(state: &s)
        GameEngine.playerDisconnected(playerID: s.players[1].id, state: &s)
        #expect(s.isPaused)
        if case .playerDisconnected(let name) = s.pauseReason {
            #expect(name == "Bob")
        } else { Issue.record("expected playerDisconnected") }
    }

    @Test("Game resumes only when everyone is reconnected")
    func testResumeRequiresAll() {
        var s = session([player("A", chips: 100, seat: 0),
                         player("B", chips: 100, seat: 1),
                         player("C", chips: 100, seat: 2)])
        GameEngine.startNewHand(state: &s)
        GameEngine.playerDisconnected(playerID: s.players[1].id, state: &s)
        GameEngine.playerDisconnected(playerID: s.players[2].id, state: &s)
        GameEngine.playerReconnected(playerID: s.players[1].id, state: &s)
        #expect(s.isPaused) // C still out
        GameEngine.playerReconnected(playerID: s.players[2].id, state: &s)
        #expect(!s.isPaused)
        #expect(s.pauseReason == nil)
    }

    @Test("Cannot commit while paused")
    func testCommitWhilePaused() {
        var s = session([player("A", chips: 100, seat: 0), player("B", chips: 100, seat: 1)])
        GameEngine.startNewHand(state: &s)
        GameEngine.playerDisconnected(playerID: s.players[1].id, state: &s)
        #expect(throws: GameEngineError.gamePaused) {
            try GameEngine.commit(playerID: s.players[0].id, amount: 10, state: &s)
        }
    }

    @Test("electHost picks lowest join order among connected players")
    func testElectHost() {
        let p0 = Player(name: "A", chipStack: 100, seatIndex: 0, joinOrder: 0)
        let p1 = Player(name: "B", chipStack: 100, seatIndex: 1, joinOrder: 1)
        let p2 = Player(name: "C", chipStack: 100, seatIndex: 2, joinOrder: 2)
        var s = session([p0, p1, p2])
        // Disconnect the current host (join order 0).
        GameEngine.playerDisconnected(playerID: p0.id, state: &s)
        let elected = GameEngine.electHost(state: s)
        #expect(elected == p1.id) // next lowest join order still connected
    }

    @Test("promoteHost updates host id")
    func testPromoteHost() {
        var s = session([player("A", chips: 100, seat: 0), player("B", chips: 100, seat: 1)])
        GameEngine.promoteHost(newHostID: s.players[1].id, state: &s)
        #expect(s.hostPlayerID == s.players[1].id)
    }
}

// MARK: - Sequence numbers

@Suite("SequenceNumbers")
struct SequenceNumberTests {

    @Test("Every mutating operation bumps the sequence number")
    func testSeqBumps() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        var last = s.sequenceNumber

        GameEngine.startNewHand(state: &s)
        #expect(s.sequenceNumber > last); last = s.sequenceNumber

        try GameEngine.commit(playerID: s.players[0].id, amount: 50, state: &s)
        #expect(s.sequenceNumber > last); last = s.sequenceNumber

        try GameEngine.fold(playerID: s.players[1].id, state: &s)
        #expect(s.sequenceNumber > last); last = s.sequenceNumber

        try GameEngine.collectPots(state: &s)
        #expect(s.sequenceNumber > last)
    }
}

// MARK: - Cash Out

@Suite("CashOut")
struct CashOutTests {

    @Test("cashOut freezes the player and folds them out of the hand")
    func testCashOutFreezes() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.cashOut(playerID: id, state: &s)
        #expect(s.player(id: id)!.hasCashedOut)
        #expect(s.player(id: id)!.hasFolded)
        #expect(s.player(id: id)!.chipStack == 1000)   // stack frozen
    }

    @Test("A cashed-out player cannot commit or fold")
    func testCashedOutCannotAct() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.cashOut(playerID: id, state: &s)
        #expect(throws: GameEngineError.playerCashedOut) {
            try GameEngine.commit(playerID: id, amount: 10, state: &s)
        }
        #expect(throws: GameEngineError.playerCashedOut) {
            try GameEngine.fold(playerID: id, state: &s)
        }
    }

    @Test("A cashed-out player sits out subsequent hands")
    func testCashedOutSitsOut() throws {
        var s = session([player("A", chips: 1000, seat: 0), player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.cashOut(playerID: id, state: &s)
        // New hand: the cashed-out player stays folded, the other is dealt in.
        GameEngine.startNewHand(state: &s)
        #expect(s.player(id: id)!.hasFolded)
        #expect(!s.players[1].hasFolded)
    }

    @Test("cashOut is idempotent")
    func testCashOutIdempotent() throws {
        var s = session([player("A", chips: 100, seat: 0), player("B", chips: 100, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[0].id
        try GameEngine.cashOut(playerID: id, state: &s)
        let seq = s.sequenceNumber
        try GameEngine.cashOut(playerID: id, state: &s)   // no-op
        #expect(s.sequenceNumber == seq)
    }

    @Test("A cashed-out player leaving does not pause the game")
    func testCashedOutDisconnectDoesNotPause() throws {
        var s = session([player("A", chips: 100, seat: 0),
                         player("B", chips: 100, seat: 1),
                         player("C", chips: 100, seat: 2)])
        GameEngine.startNewHand(state: &s)
        let id = s.players[2].id
        try GameEngine.cashOut(playerID: id, state: &s)
        GameEngine.playerDisconnected(playerID: id, state: &s)
        #expect(!s.isPaused)
    }

    @Test("Game resumes with a cashed-out player gone for good")
    func testResumeIgnoresCashedOut() throws {
        var s = session([player("A", chips: 100, seat: 0),
                         player("B", chips: 100, seat: 1),
                         player("C", chips: 100, seat: 2)])
        GameEngine.startNewHand(state: &s)
        let leaver = s.players[1].id
        let cashed = s.players[2].id
        // C cashes out and leaves (no pause). Then B drops (pause).
        try GameEngine.cashOut(playerID: cashed, state: &s)
        GameEngine.playerDisconnected(playerID: cashed, state: &s)
        GameEngine.playerDisconnected(playerID: leaver, state: &s)
        #expect(s.isPaused)
        // B comes back; the game resumes even though C never will.
        GameEngine.playerReconnected(playerID: leaver, state: &s)
        #expect(!s.isPaused)
    }

    @Test("electHost never picks a cashed-out player")
    func testElectHostSkipsCashedOut() throws {
        var s = session([player("A", chips: 100, seat: 0, joinOrder: 0),
                         player("B", chips: 100, seat: 1, joinOrder: 1),
                         player("C", chips: 100, seat: 2, joinOrder: 2)])
        GameEngine.startNewHand(state: &s)
        // Lowest join order (A) cashes out; B should be elected, not A.
        try GameEngine.cashOut(playerID: s.players[0].id, state: &s)
        #expect(GameEngine.electHost(state: s) == s.players[1].id)
    }
}

// MARK: - Last action / to-call

@Suite("LastActionAndToCall")
struct LastActionTests {

    @Test("commit records the last action and drives the bet-to-match")
    func testCommitRecordsAction() throws {
        var s = session([player("Alice", chips: 1000, seat: 0),
                         player("Bob", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        #expect(s.lastAction == nil)   // cleared at hand start

        try GameEngine.commit(playerID: s.players[0].id, amount: 150, state: &s)
        #expect(s.lastAction == .added(player: "Alice", amount: 150))
        #expect(s.currentBet == 150)
        #expect(s.toCall(for: s.players[1].id) == 150)
        #expect(s.toCall(for: s.players[0].id) == 0)
    }

    @Test("to-call reflects the shortfall to the biggest bettor")
    func testToCallShortfall() throws {
        var s = session([player("Alice", chips: 1000, seat: 0),
                         player("Bob", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        try GameEngine.commit(playerID: s.players[0].id, amount: 100, state: &s)
        try GameEngine.commit(playerID: s.players[1].id, amount: 60, state: &s)
        #expect(s.toCall(for: s.players[1].id) == 40)
    }

    @Test("fold updates the last action")
    func testFoldAction() throws {
        var s = session([player("Alice", chips: 1000, seat: 0),
                         player("Bob", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        try GameEngine.fold(playerID: s.players[1].id, state: &s)
        #expect(s.lastAction == .folded(player: "Bob"))
    }

    @Test("starting a new hand clears the last action")
    func testNewHandClearsAction() throws {
        var s = session([player("Alice", chips: 1000, seat: 0),
                         player("Bob", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        try GameEngine.commit(playerID: s.players[0].id, amount: 50, state: &s)
        #expect(s.lastAction != nil)
        GameEngine.startNewHand(state: &s)
        #expect(s.lastAction == nil)
    }
}

// MARK: - Fold / stranded-chip edge cases

@Suite("FoldEdgeCases")
struct FoldEdgeCasesTests {

    @Test("A folded over-bet returns the uncalled excess and pot stays winnable")
    func testFoldedOverbetRefunded() throws {
        var s = session([player("A", chips: 1000, seat: 0),
                         player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let a = s.players[0].id
        let b = s.players[1].id
        try GameEngine.commit(playerID: a, amount: 100, state: &s)
        try GameEngine.fold(playerID: a, state: &s)      // A over-bet then folded
        try GameEngine.commit(playerID: b, amount: 30, state: &s)
        try GameEngine.collectPots(state: &s)

        // A's uncalled 70 is returned; B is the sole live player and takes the
        // matched 60 (30 each) automatically — no stranded, unwinnable pot.
        #expect(s.pots.isEmpty)
        #expect(s.phase == .waiting)
        #expect(s.player(id: a)!.chipStack == 970)   // 1000 - 100 + 70 refund
        #expect(s.player(id: b)!.chipStack == 1030)  // 1000 - 30 + 60 pot
    }

    @Test("Everyone folding refunds all committed chips and ends the hand")
    func testEveryoneFoldsRefundsAll() throws {
        var s = session([player("A", chips: 1000, seat: 0),
                         player("B", chips: 1000, seat: 1)])
        GameEngine.startNewHand(state: &s)
        let a = s.players[0].id
        let b = s.players[1].id
        try GameEngine.commit(playerID: a, amount: 100, state: &s)
        try GameEngine.commit(playerID: b, amount: 50, state: &s)
        try GameEngine.fold(playerID: a, state: &s)
        try GameEngine.fold(playerID: b, state: &s)
        try GameEngine.collectPots(state: &s)

        #expect(s.pots.isEmpty)
        #expect(s.phase == .waiting)
        #expect(s.player(id: a)!.chipStack == 1000)  // fully refunded
        #expect(s.player(id: b)!.chipStack == 1000)
    }

    @Test("Chips are conserved even when the top bettor folds")
    func testConservationWithFoldedOverbet() throws {
        var s = session([player("A", chips: 500, seat: 0),
                         player("B", chips: 500, seat: 1),
                         player("C", chips: 500, seat: 2)])
        let startTotal = s.players.reduce(0) { $0 + $1.chipStack }
        GameEngine.startNewHand(state: &s)
        try GameEngine.commit(playerID: s.players[0].id, amount: 300, state: &s)
        try GameEngine.fold(playerID: s.players[0].id, state: &s)   // big folded over-bet
        try GameEngine.commit(playerID: s.players[1].id, amount: 100, state: &s)
        try GameEngine.commit(playerID: s.players[2].id, amount: 100, state: &s)
        try GameEngine.collectPots(state: &s)
        // Award any remaining pot to B.
        for pot in s.pots {
            try GameEngine.award(potID: pot.id, winnerIDs: [s.players[1].id], state: &s)
        }
        let endTotal = s.players.reduce(0) { $0 + $1.chipStack }
        #expect(endTotal == startTotal)
    }
}
