import Testing
import Foundation
@testable import PokerSettle

// MARK: - In-memory virtual network
//
// Wires several GameCoordinators together and routes their NetEffects between
// them, exactly as a real transport would — but synchronously and in-process.
// This lets us test the full distributed protocol (lobby, play, sync, host
// election) without MultipeerConnectivity or real devices.

@MainActor
final class VirtualNetwork {
    private(set) var nodes: [UUID: GameCoordinator] = [:]
    /// Players currently reachable. Effects to/from unreachable nodes are dropped.
    var reachable: Set<UUID> = []
    private(set) var notifications: [(player: UUID, text: String)] = []

    func add(_ coordinator: GameCoordinator) {
        nodes[coordinator.localPlayer.id] = coordinator
        reachable.insert(coordinator.localPlayer.id)
    }

    /// Replace a node with a fresh coordinator that reuses the same identity —
    /// models a device that left and relaunched (state lost, UUID persisted).
    func replace(_ coordinator: GameCoordinator) {
        nodes[coordinator.localPlayer.id] = coordinator
        reachable.insert(coordinator.localPlayer.id)
    }

    func disconnect(_ playerID: UUID) {
        reachable.remove(playerID)
        // Every other reachable node observes the drop.
        for (id, node) in nodes where id != playerID && reachable.contains(id) {
            deliverEffects(node.peerDisconnected(playerID: playerID), from: id)
        }
    }

    func reconnect(_ playerID: UUID) {
        reachable.insert(playerID)
        // Other nodes observe the (re)connection (host marks present, rebroadcasts).
        for (id, node) in nodes where id != playerID && reachable.contains(id) {
            deliverEffects(node.peerReconnected(playerID: playerID), from: id)
        }
        // The rejoining node asks to be caught up.
        if let node = nodes[playerID] {
            deliverEffects(node.requestSync(), from: playerID)
        }
    }

    /// Execute a batch of effects originating from `sender`, recursively
    /// delivering any effects they produce until the network is quiescent.
    func deliverEffects(_ effects: [NetEffect], from sender: UUID) {
        guard reachable.contains(sender) else { return }
        for effect in effects {
            switch effect {
            case .notify(let text):
                notifications.append((sender, text))
            case .send(let message, let recipient):
                for target in resolve(recipient, sender: sender) where target != sender {
                    guard reachable.contains(target), let node = nodes[target] else { continue }
                    let produced = node.receive(message, from: sender)
                    deliverEffects(produced, from: target)
                }
            }
        }
    }

    private func resolve(_ recipient: Recipient, sender: UUID) -> [UUID] {
        switch recipient {
        case .all:
            return Array(nodes.keys)
        case .player(let id):
            return [id]
        case .host:
            // Use the sender's view of who the host is; fall back (lobby) to the
            // initial host node.
            if let hostID = nodes[sender]?.state?.hostPlayerID {
                return [hostID]
            }
            if let hostNode = nodes.values.first(where: { $0.isHost }) {
                return [hostNode.localPlayer.id]
            }
            return []
        }
    }

    func node(_ id: UUID) -> GameCoordinator { nodes[id]! }
}

// MARK: - Codable round-trips

@Suite("MessageCodec")
struct MessageCodecTests {

    private func roundTrip(_ message: NetMessage) throws -> NetMessage {
        let data = try JSONEncoder().encode(message)
        return try JSONDecoder().decode(NetMessage.self, from: data)
    }

    @Test("hello round-trips")
    func testHello() throws {
        let m = NetMessage.hello(PlayerInfo(name: "Alice", joinOrder: 2))
        #expect(try roundTrip(m) == m)
    }

    @Test("request variants round-trip")
    func testRequests() throws {
        let pid = UUID()
        let pot = UUID()
        let variants: [GameRequest] = [
            .startNewHand,
            .commit(playerID: pid, amount: 100),
            .commitAllIn(playerID: pid),
            .fold(playerID: pid),
            .cashOut(playerID: pid),
            .collectPots,
            .award(potID: pot, winnerIDs: [pid, UUID()])
        ]
        for r in variants {
            let m = NetMessage.request(r)
            #expect(try roundTrip(m) == m)
        }
    }

    @Test("stateUpdate round-trips a full game state")
    func testStateUpdate() throws {
        let players = [
            Player(name: "A", chipStack: 1000, seatIndex: 0, joinOrder: 0),
            Player(name: "B", chipStack: 1000, seatIndex: 1, joinOrder: 1),
        ]
        var s = GameEngine.startSession(players: players)
        GameEngine.startNewHand(state: &s)
        let m = NetMessage.stateUpdate(s)
        #expect(try roundTrip(m) == m)
    }

    @Test("pause reason survives encoding")
    func testPauseReasonCodable() throws {
        var s = GameEngine.startSession(players: [
            Player(name: "A", chipStack: 100, seatIndex: 0, joinOrder: 0),
            Player(name: "B", chipStack: 100, seatIndex: 1, joinOrder: 1),
        ])
        GameEngine.startNewHand(state: &s)
        GameEngine.playerDisconnected(playerID: s.players[0].id, state: &s)
        let decoded = try roundTrip(.stateUpdate(s))
        if case .stateUpdate(let s2) = decoded {
            #expect(s2.pauseReason == s.pauseReason)
        } else { Issue.record("wrong case") }
    }
}

// MARK: - Lobby formation

@Suite("Lobby")
@MainActor
struct LobbyTests {

    func makeNetwork(peers: Int) -> (VirtualNetwork, GameCoordinator, [GameCoordinator]) {
        let net = VirtualNetwork()
        let host = GameCoordinator(localPlayer: PlayerInfo(name: "Host"), isInitialHost: true)
        net.add(host)
        var peerNodes: [GameCoordinator] = []
        for i in 0..<peers {
            let p = GameCoordinator(localPlayer: PlayerInfo(name: "P\(i)"), isInitialHost: false)
            net.add(p)
            peerNodes.append(p)
        }
        return (net, host, peerNodes)
    }

    @Test("Peers announcing themselves populate the host roster and all peers see it")
    func testLobbyAssembly() {
        let (net, host, peers) = makeNetwork(peers: 2)
        for p in peers {
            net.deliverEffects(p.announceSelf(), from: p.localPlayer.id)
        }
        #expect(host.lobby.count == 3) // host + 2 peers
        // Every peer received the final lobby broadcast
        for p in peers {
            #expect(p.lobby.count == 3)
        }
        // Join order is deterministic and unique
        let orders = host.lobby.map { $0.joinOrder }.sorted()
        #expect(orders == [0, 1, 2])
    }

    @Test("startGame distributes identical initial state to every device")
    func testStartGamePropagates() {
        let (net, host, peers) = makeNetwork(peers: 2)
        for p in peers { net.deliverEffects(p.announceSelf(), from: p.localPlayer.id) }
        net.deliverEffects(host.startGame(startingStack: 1000), from: host.localPlayer.id)

        #expect(host.state != nil)
        for p in peers {
            #expect(p.state != nil)
            #expect(p.state == host.state)             // identical replicas
            #expect(p.state?.phase == .betting)
            #expect(p.state?.players.count == 3)
        }
        // Everyone agrees the host is the host.
        #expect(host.isHost)
        #expect(peers.allSatisfy { !$0.isHost })
    }
}

// MARK: - In-game replication

@Suite("Replication")
@MainActor
struct ReplicationTests {

    func startedGame(peers: Int, stack: Int = 1000) -> (VirtualNetwork, GameCoordinator, [GameCoordinator]) {
        let net = VirtualNetwork()
        let host = GameCoordinator(localPlayer: PlayerInfo(name: "Host"), isInitialHost: true)
        net.add(host)
        var peerNodes: [GameCoordinator] = []
        for i in 0..<peers {
            let p = GameCoordinator(localPlayer: PlayerInfo(name: "P\(i)"), isInitialHost: false)
            net.add(p)
            peerNodes.append(p)
        }
        for p in peerNodes { net.deliverEffects(p.announceSelf(), from: p.localPlayer.id) }
        net.deliverEffects(host.startGame(startingStack: stack), from: host.localPlayer.id)
        return (net, host, peerNodes)
    }

    @Test("A peer's request is applied by the host and reflected on all devices")
    func testPeerRequestReplicated() {
        let (net, host, peers) = startedGame(peers: 2)
        let actor = peers[0]
        let actorID = actor.localPlayer.id

        net.deliverEffects(actor.submit(.commit(playerID: actorID, amount: 250)),
                           from: actorID)

        // Host applied it; every replica reflects the same stack.
        for node in [host] + peers {
            let p = node.state!.player(id: actorID)!
            #expect(p.chipStack == 750)
            #expect(p.committed == 250)
        }
        // Sequence numbers all match.
        let seqs = ([host] + peers).map { $0.state!.sequenceNumber }
        #expect(Set(seqs).count == 1)
    }

    @Test("Host-submitted actions replicate to peers")
    func testHostRequestReplicated() {
        let (net, host, peers) = startedGame(peers: 1)
        let hostID = host.localPlayer.id
        net.deliverEffects(host.submit(.commit(playerID: hostID, amount: 100)), from: hostID)
        for p in peers {
            #expect(p.state!.player(id: hostID)!.committed == 100)
        }
    }

    @Test("Full hand: commit, collect, award replicates end-to-end")
    func testFullHandReplicated() {
        let (net, host, peers) = startedGame(peers: 2)
        let ids = host.state!.players.map { $0.id }

        for id in ids {
            let owner = ([host] + peers).first { $0.localPlayer.id == id }!
            net.deliverEffects(owner.submit(.commit(playerID: id, amount: 100)), from: id)
        }
        net.deliverEffects(host.submit(.collectPots), from: host.localPlayer.id)
        #expect(host.state!.phase == .showdown)

        let potID = host.state!.pots[0].id
        net.deliverEffects(host.submit(.award(potID: potID, winnerIDs: [ids[0]])),
                           from: host.localPlayer.id)

        for node in [host] + peers {
            #expect(node.state!.phase == .waiting)
            #expect(node.state!.player(id: ids[0])!.chipStack == 1200) // 900 + 300
        }
    }

    @Test("Peer requests are ignored by non-hosts (only host mutates)")
    func testNonHostIgnoresRequests() {
        let (net, host, peers) = startedGame(peers: 2)
        let p0 = peers[0], p1 = peers[1]
        // Deliver a request straight to a non-host peer; it must not mutate.
        let before = p1.state!.sequenceNumber
        _ = p1.receive(.request(.commit(playerID: p0.localPlayer.id, amount: 50)),
                       from: p0.localPlayer.id)
        #expect(p1.state!.sequenceNumber == before)
    }
}

// MARK: - Disconnect, sync, and host election

@Suite("ResilienceProtocol")
@MainActor
struct ResilienceProtocolTests {

    func startedGame(peers: Int, stack: Int = 1000) -> (VirtualNetwork, GameCoordinator, [GameCoordinator]) {
        let net = VirtualNetwork()
        let host = GameCoordinator(localPlayer: PlayerInfo(name: "Host"), isInitialHost: true)
        net.add(host)
        var peerNodes: [GameCoordinator] = []
        for i in 0..<peers {
            let p = GameCoordinator(localPlayer: PlayerInfo(name: "P\(i)"), isInitialHost: false)
            net.add(p)
            peerNodes.append(p)
        }
        for p in peerNodes { net.deliverEffects(p.announceSelf(), from: p.localPlayer.id) }
        net.deliverEffects(host.startGame(startingStack: stack), from: host.localPlayer.id)
        return (net, host, peerNodes)
    }

    @Test("A peer dropping pauses the game on the host and notifies others")
    func testPeerDropPauses() {
        let (net, host, peers) = startedGame(peers: 2)
        net.disconnect(peers[0].localPlayer.id)
        #expect(host.state!.isPaused)
        // Surviving devices got a disconnect notification.
        #expect(net.notifications.contains { $0.text.contains("disconnected") })
    }

    @Test("Reconnecting the last missing player resumes the game everywhere")
    func testReconnectResumes() {
        let (net, host, peers) = startedGame(peers: 2)
        let droppedID = peers[0].localPlayer.id
        net.disconnect(droppedID)
        #expect(host.state!.isPaused)

        net.reconnect(droppedID)
        #expect(!host.state!.isPaused)
        // Host broadcast the resume; all replicas agree.
        for node in [host] + peers {
            #expect(!node.state!.isPaused)
        }
        #expect(net.notifications.contains { $0.text.contains("resumed") })
    }

    @Test("Rejoining peer is caught up via sync to the host's latest state")
    func testSyncCatchesUpRejoiner() {
        let (net, host, peers) = startedGame(peers: 2)
        let rejoiner = peers[0]
        let rejoinerID = rejoiner.localPlayer.id

        net.disconnect(rejoinerID)            // host pauses; sequence advances
        #expect(host.state!.isPaused)
        let pausedSeq = host.state!.sequenceNumber

        net.reconnect(rejoinerID)             // host resumes; sequence advances again
        #expect(!host.state!.isPaused)

        // The rejoiner missed both the pause and the resume broadcasts while
        // away, yet is now fully caught up to the host's latest state.
        #expect(host.state!.sequenceNumber > pausedSeq)
        #expect(rejoiner.state!.sequenceNumber == host.state!.sequenceNumber)
        #expect(rejoiner.state == host.state)
    }

    @Test("Host dropping promotes exactly the lowest-join-order survivor")
    func testHostElection() {
        let (net, host, peers) = startedGame(peers: 2)
        // Join order: host=0, peers[0]=1, peers[1]=2.
        net.disconnect(host.localPlayer.id)

        // peers[0] (join order 1) should have promoted itself.
        #expect(peers[0].isHost)
        #expect(!peers[1].isHost)
        #expect(peers[0].state!.hostPlayerID == peers[0].localPlayer.id)
        // The other survivor adopted the new host via broadcast.
        #expect(peers[1].state!.hostPlayerID == peers[0].localPlayer.id)
        // The game stays paused — the old host is still a disconnected player.
        #expect(peers[0].state!.isPaused)
        #expect(net.notifications.contains { $0.text.contains("now the host") })
    }

    @Test("New host drives the game once the old host returns and play resumes")
    func testNewHostDrivesAfterResume() {
        let (net, host, peers) = startedGame(peers: 2)
        let oldHostID = host.localPlayer.id
        net.disconnect(oldHostID)
        let newHost = peers[0]
        #expect(newHost.isHost)
        #expect(newHost.state!.isPaused)   // paused until everyone is back

        net.reconnect(oldHostID)
        #expect(!newHost.state!.isPaused)  // resumed
        // The returned old host learns it is no longer the host.
        #expect(host.state!.hostPlayerID == newHost.localPlayer.id)
        #expect(!host.isHost)

        // The promoted host now drives; every device reflects the action.
        let actorID = newHost.localPlayer.id
        net.deliverEffects(newHost.submit(.commit(playerID: actorID, amount: 300)), from: actorID)
        #expect(host.state!.player(id: actorID)!.committed == 300)
        #expect(peers[1].state!.player(id: actorID)!.committed == 300)
    }

    @Test("Only one survivor promotes — no split brain")
    func testNoSplitBrain() {
        let (net, host, peers) = startedGame(peers: 3)
        net.disconnect(host.localPlayer.id)
        let hostCount = ([peers]).flatMap { $0 }.filter { $0.isHost }.count
        #expect(hostCount == 1)
    }
}

// MARK: - Join control: late joiners vs. returning members

@Suite("JoinControl")
@MainActor
struct JoinControlTests {

    func startedGame(peers: Int, stack: Int = 1000) -> (VirtualNetwork, GameCoordinator, [GameCoordinator]) {
        let net = VirtualNetwork()
        let host = GameCoordinator(localPlayer: PlayerInfo(name: "Host"), isInitialHost: true)
        net.add(host)
        var peerNodes: [GameCoordinator] = []
        for i in 0..<peers {
            let p = GameCoordinator(localPlayer: PlayerInfo(name: "P\(i)"), isInitialHost: false)
            net.add(p)
            peerNodes.append(p)
        }
        for p in peerNodes { net.deliverEffects(p.announceSelf(), from: p.localPlayer.id) }
        net.deliverEffects(host.startGame(startingStack: stack), from: host.localPlayer.id)
        return (net, host, peerNodes)
    }

    @Test("A brand-new device is rejected from an in-progress game")
    func testLateJoinerRejected() {
        let (net, host, _) = startedGame(peers: 1)
        let newcomer = GameCoordinator(localPlayer: PlayerInfo(name: "Latecomer"), isInitialHost: false)
        net.add(newcomer)

        net.deliverEffects(newcomer.announceSelf(), from: newcomer.localPlayer.id)

        #expect(newcomer.rejectionMessage != nil)
        #expect(newcomer.state == nil)                       // never shown the table
        #expect(host.state!.players.count == 2)              // roster unchanged (host + P0)
        #expect(!host.state!.players.contains { $0.name == "Latecomer" })
    }

    @Test("A rejected newcomer ignores later state broadcasts")
    func testRejectedNewcomerIgnoresState() {
        let (net, host, _) = startedGame(peers: 1)
        let newcomer = GameCoordinator(localPlayer: PlayerInfo(name: "Latecomer"), isInitialHost: false)
        net.add(newcomer)
        net.deliverEffects(newcomer.announceSelf(), from: newcomer.localPlayer.id)
        #expect(newcomer.rejectionMessage != nil)

        // Host plays on; the broadcast must not leak into the rejected device.
        let hostID = host.localPlayer.id
        net.deliverEffects(host.submit(.commit(playerID: hostID, amount: 100)), from: hostID)
        #expect(newcomer.state == nil)
    }

    @Test("A device hosting a fresh game is never pulled into another game")
    func testHostStartsFreshNotAbsorbed() {
        // An existing, in-progress game.
        let (net, hostA, _) = startedGame(peers: 1)

        // A separate device that wants to HOST its own new game.
        let soloHost = GameCoordinator(localPlayer: PlayerInfo(name: "Solo"), isInitialHost: true)
        net.add(soloHost)

        // The existing game plays on and broadcasts to everyone reachable.
        let aID = hostA.localPlayer.id
        net.deliverEffects(hostA.submit(.commit(playerID: aID, amount: 50)), from: aID)

        // The fresh host must not have been absorbed into the old game.
        #expect(soloHost.state == nil)
        #expect(soloHost.isHost)
    }

    @Test("A member who left can rejoin their seat and resume play")
    func testMemberCanRejoinAfterLeaving() {
        let (net, host, peers) = startedGame(peers: 1)
        let memberID = peers[0].localPlayer.id
        let memberName = peers[0].localPlayer.name

        // They leave (drop off the mesh); the host pauses.
        net.disconnect(memberID)
        #expect(host.state!.isPaused)

        // They come back as a *fresh* coordinator (state lost) but with the SAME
        // persistent identity — exactly what the Leave → rejoin flow produces.
        let returning = GameCoordinator(
            localPlayer: PlayerInfo(id: memberID, name: memberName),
            isInitialHost: false
        )
        net.replace(returning)
        net.deliverEffects(returning.announceSelf(), from: memberID)

        // The host recognized the returning member, resumed, and caught them up.
        #expect(!host.state!.isPaused)
        #expect(returning.rejectionMessage == nil)
        #expect(returning.state != nil)
        #expect(returning.state!.player(id: memberID) != nil)
        #expect(returning.state == host.state)
    }
}
