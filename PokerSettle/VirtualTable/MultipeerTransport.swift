import Foundation
import MultipeerConnectivity
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MultipeerTransport
//
// The radio. Wraps MCSession + advertiser + browser and drives a GameCoordinator
// for all decision-making. Its only jobs are:
//   • discover/connect peers over Bluetooth + local Wi-Fi,
//   • encode/decode NetMessages over MCSession's Data API,
//   • map MCPeerID ↔ player UUID, and
//   • execute the NetEffects the coordinator returns.
//
// Each peer's MCPeerID displayName is set to its player UUID string, which makes
// the identity mapping trivial and reliable across reconnects.

@MainActor
final class MultipeerTransport: NSObject, ObservableObject {

    static let serviceType = "pokersettle"   // must be ≤15 chars, a-z0-9 and '-'

    let coordinator: GameCoordinator
    private let localPeerID: MCPeerID
    private let session: MCSession

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    /// Surfaced to the UI: transient banners (disconnects, host changes, resume).
    @Published private(set) var banner: String?
    /// Surfaced to the UI: whether the app is foregrounded. MultipeerConnectivity
    /// stops working when backgrounded, so the UI nudges players to stay in-app.
    @Published private(set) var isForeground = true
    @Published private(set) var connectedPeerCount = 0
    /// Surfaced to the UI: nearby tables a joiner can pick from.
    @Published private(set) var discoveredHosts: [DiscoveredHost] = []

    init(localPlayer: PlayerInfo, isInitialHost: Bool) {
        self.coordinator = GameCoordinator(localPlayer: localPlayer, isInitialHost: isInitialHost)
        // Encode the UUID in the displayName for reliable peer↔player mapping.
        self.localPeerID = MCPeerID(displayName: localPlayer.id.uuidString)
        self.session = MCSession(peer: localPeerID,
                                 securityIdentity: nil,
                                 encryptionPreference: .required)
        super.init()
        session.delegate = self
        observeForegroundState()
    }

    // MARK: Discovery lifecycle

    /// Host: advertise this session so peers can find it. The host's name rides
    /// along in the discovery info so joiners can tell tables apart.
    func startHosting() {
        ensureAdvertising()
    }

    /// Begin advertising if we aren't already. Called when hosting, and again if
    /// we get promoted to host mid-game (a promoted peer must become discoverable
    /// so players — including the departed host — can find and rejoin the table).
    private func ensureAdvertising() {
        guard advertiser == nil else { return }
        let advertiser = MCNearbyServiceAdvertiser(peer: localPeerID,
                                                   discoveryInfo: ["name": coordinator.localPlayer.name],
                                                   serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
    }

    /// Peer: browse for hosts to join. Discovered tables surface in
    /// `discoveredHosts` for the user to pick from — we never auto-join, so a
    /// joiner can't accidentally bridge two separate hosts into one session.
    func startBrowsing() {
        let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    /// Peer: join a specific discovered table.
    func join(_ host: DiscoveredHost) {
        browser?.invitePeer(host.peerID, to: session, withContext: nil, timeout: 30)
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session.disconnect()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: UI-driven actions

    func startGame(startingStack: Int, buyInDollars: Double) {
        run(coordinator.startGame(startingStack: startingStack, buyInDollars: buyInDollars))
    }

    func submit(_ request: GameRequest) {
        run(coordinator.submit(request))
    }

    // MARK: Effect execution

    private func run(_ effects: [NetEffect]) {
        for effect in effects {
            switch effect {
            case .notify(let text):
                banner = text
            case .send(let message, let recipient):
                sendMessage(message, to: recipient)
            }
        }
        // Once we're in a game, stop discovering. Otherwise a lingering browser
        // could pull us into a *different* host's newly advertised game.
        if coordinator.state != nil {
            browser?.stopBrowsingForPeers()
        }
        // If we're the host (including after being promoted via election), make
        // sure we're advertising so players can find and rejoin the table.
        if coordinator.isHost {
            ensureAdvertising()
        }
    }

    private func sendMessage(_ message: NetMessage, to recipient: Recipient) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        let targets: [MCPeerID]
        switch recipient {
        case .all:
            targets = session.connectedPeers
        case .host:
            targets = peerID(for: coordinator.state?.hostPlayerID).map { [$0] } ?? hostFallbackTargets()
        case .player(let id):
            targets = peerID(for: id).map { [$0] } ?? []
        }
        guard !targets.isEmpty else { return }
        try? session.send(data, toPeers: targets, with: .reliable)
    }

    // Before the host's UUID is known (lobby bootstrap), a freshly connected
    // peer addresses ".host" by sending to every connected peer — in practice
    // just the advertiser it connected to.
    private func hostFallbackTargets() -> [MCPeerID] {
        coordinator.state == nil ? session.connectedPeers : []
    }

    private func peerID(for playerID: UUID?) -> MCPeerID? {
        guard let playerID else { return nil }
        if playerID == coordinator.localPlayer.id { return nil }  // never send to self
        return session.connectedPeers.first { $0.displayName == playerID.uuidString }
    }

    private func playerID(for peerID: MCPeerID) -> UUID? {
        UUID(uuidString: peerID.displayName)
    }

    // MARK: Foreground observation

    private func observeForegroundState() {
        #if canImport(UIKit)
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didEnterBackground),
                       name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(willEnterForeground),
                       name: UIApplication.willEnterForegroundNotification, object: nil)
        #endif
    }

    @objc private func didEnterBackground() { isForeground = false }
    @objc private func willEnterForeground() { isForeground = true }
}

// MARK: - MCSessionDelegate

extension MultipeerTransport: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let id = UUID(uuidString: peerID.displayName)
        Task { @MainActor in
            self.connectedPeerCount = session.connectedPeers.count
            guard let id else { return }
            switch state {
            case .connected:
                if self.coordinator.state == nil {
                    // Lobby: a peer announces itself to the host.
                    self.run(self.coordinator.announceSelf())
                } else {
                    // In-game (re)connection: host marks present & rebroadcasts;
                    // the local device also asks to be caught up.
                    self.run(self.coordinator.peerReconnected(playerID: id))
                    self.run(self.coordinator.requestSync())
                }
            case .notConnected:
                if self.coordinator.state != nil {
                    self.run(self.coordinator.peerDisconnected(playerID: id))
                }
            case .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let message = try? JSONDecoder().decode(NetMessage.self, from: data) else { return }
        let sender = UUID(uuidString: peerID.displayName) ?? UUID()
        Task { @MainActor in
            self.run(self.coordinator.receive(message, from: sender))
            // If the host turned us away, leave the mesh so we stop receiving
            // broadcasts (which would otherwise leak the in-progress game to us).
            if self.coordinator.rejectionMessage != nil {
                self.stop()
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - Advertiser / Browser delegates

extension MultipeerTransport: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept invitations into our session (in-room, trusted play).
        invitationHandler(true, session)
    }
}

extension MultipeerTransport: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String : String]?) {
        // Surface the table for the user to choose — never auto-join, so we
        // can't bridge two separate hosts into one session.
        let name = info?["name"] ?? "Table"
        Task { @MainActor in
            if !self.discoveredHosts.contains(where: { $0.peerID == peerID }) {
                self.discoveredHosts.append(DiscoveredHost(peerID: peerID, name: name))
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredHosts.removeAll { $0.peerID == peerID }
        }
    }
}

// MARK: - Discovered host

struct DiscoveredHost: Identifiable, Equatable {
    let peerID: MCPeerID
    let name: String
    var id: String { peerID.displayName }
}
