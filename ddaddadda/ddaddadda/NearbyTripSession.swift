import Foundation
import MultipeerConnectivity
import Observation

@MainActor @Observable
final class NearbyTripSession: NSObject {
    private static let serviceType = "trip-picks"
    private var peerID: MCPeerID
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private(set) var isHosting = false
    private(set) var connectedNames: [String] = []
    private(set) var statusText = "공유 꺼짐"
    var onStateReceived: ((SharedTripState) -> Void)?

    init(displayName: String) {
        peerID = MCPeerID(displayName: String(displayName.prefix(24)))
        super.init(); configure()
    }
    func updateDisplayName(_ name: String) {
        let running = isHosting; stop(); peerID = MCPeerID(displayName: String(name.prefix(24))); configure(); if running { start() }
    }
    func start() {
        guard !isHosting else { return }; isHosting = true
        advertiser.startAdvertisingPeer(); browser.startBrowsingForPeers(); statusText = "친구를 찾는 중…"
    }
    func stop() {
        advertiser?.stopAdvertisingPeer(); browser?.stopBrowsingForPeers(); session?.disconnect()
        isHosting = false; connectedNames = []; statusText = "공유 꺼짐"
    }
    func send(_ state: SharedTripState) {
        guard isHosting, !session.connectedPeers.isEmpty, let data = try? JSONEncoder().encode(state) else { return }
        try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }
    private func configure() {
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required); session.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: nil, serviceType: Self.serviceType); advertiser.delegate = self
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType); browser.delegate = self
    }
    private func refreshPeers() {
        connectedNames = session.connectedPeers.map(\.displayName).sorted()
        statusText = connectedNames.isEmpty ? "친구를 찾는 중…" : "\(connectedNames.count)명 연결됨"
    }
}

extension NearbyTripSession: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) { Task { @MainActor in self.refreshPeers() } }
    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard let state = try? JSONDecoder().decode(SharedTripState.self, from: data) else { return }
            self.onStateReceived?(state)
        }
    }
    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
extension NearbyTripSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in invitationHandler(true, self.session) }
    }
}
extension NearbyTripSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            guard peerID != self.peerID else { return }
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
        }
    }
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
