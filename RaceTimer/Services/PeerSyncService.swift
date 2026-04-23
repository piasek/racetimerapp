import Foundation
@preconcurrency import MultipeerConnectivity
import SwiftData
import os

/// Manages MultipeerConnectivity for peer-to-peer sync between devices.
@MainActor
@Observable
final class PeerSyncService: NSObject {
    private static let serviceType = "racetimer-sync" // max 15 chars, lowercase + hyphens

    private let peerId: MCPeerID
    /// Accessed from both @MainActor (start/stop/send) and nonisolated delegate callbacks.
    /// Excluded from @Observable tracking; nonisolated(unsafe) because MC delegates are
    /// called on arbitrary threads but we guarantee single-writer (start/stop) on MainActor.
    @ObservationIgnored
    nonisolated(unsafe) private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private(set) var connectedPeers: [MCPeerID] = []
    /// Peers seen by the browser (not yet connected). Keyed by MCPeerID.
    private(set) var discoveredPeers: [DiscoveredPeer] = []
    private(set) var isActive = false

    var localDisplayName: String { peerId.displayName }

    var onEventsReceived: (([SyncEventTransfer]) -> Void)?
    /// Called when a peer finishes connecting. Coordinator uses this to push
    /// its full local event log to the new peer for catch-up.
    var onPeerConnected: ((MCPeerID) -> Void)?

    /// Internal bookkeeping of peer info seen by the browser (discovery payload).
    /// Used to populate `DiscoveredPeer` entries with role/sessionId.
    private var peerInfo: [MCPeerID: [String: String]] = [:]
    /// Raw per-peer state driven by MCSessionState transitions + browser events.
    private var peerStates: [MCPeerID: DiscoveredPeer.State] = [:]

    private let logger = Logger(subsystem: "com.racetimerapp", category: "PeerSync")

    override init() {
        self.peerId = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    // MARK: - Start / Stop

    func start(deviceId: String, role: String, sessionId: String? = nil) {
        guard !isActive else { return }

        let session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        var discoveryInfo = ["deviceId": deviceId, "role": role]
        if let sessionId { discoveryInfo["sessionId"] = sessionId }

        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerId,
            discoveryInfo: discoveryInfo,
            serviceType: Self.serviceType
        )
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser

        let browser = MCNearbyServiceBrowser(peer: peerId, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser

        isActive = true
        logger.info("Peer sync started as \(self.peerId.displayName)")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        advertiser = nil
        browser = nil
        session = nil
        connectedPeers = []
        discoveredPeers = []
        peerInfo.removeAll()
        peerStates.removeAll()
        isActive = false
        logger.info("Peer sync stopped")
    }

    private func refreshDiscoveredPeers() {
        discoveredPeers = peerStates
            .map { (peer, state) in
                DiscoveredPeer(
                    displayName: peer.displayName,
                    state: state,
                    role: peerInfo[peer]?["role"],
                    sessionId: peerInfo[peer]?["sessionId"],
                    deviceId: peerInfo[peer]?["deviceId"]
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Send events

    /// Broadcast events to all currently-connected peers.
    func sendEvents(_ events: [SyncEventTransfer]) {
        guard let session, !session.connectedPeers.isEmpty, !events.isEmpty else { return }
        sendEvents(events, to: session.connectedPeers)
    }

    /// Send events to specific peers only (used for per-peer full-sync catch-up).
    func sendEvents(_ events: [SyncEventTransfer], to peers: [MCPeerID]) {
        guard let session, !peers.isEmpty, !events.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(events)
            try session.send(data, toPeers: peers, with: .reliable)
            logger.info("Sent \(events.count) events to \(peers.count) peers")
        } catch {
            logger.error("Failed to send events: \(error.localizedDescription)")
        }
    }
}

// MARK: - MCSessionDelegate

extension PeerSyncService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            connectedPeers = session.connectedPeers
            switch state {
            case .connected:
                peerStates[peerID] = .connected
                logger.info("Peer connected: \(peerID.displayName)")
                onPeerConnected?(peerID)
            case .notConnected:
                // Keep the peer in "discovered" if the browser still sees it; otherwise drop.
                if peerInfo[peerID] != nil {
                    peerStates[peerID] = .discovered
                } else {
                    peerStates.removeValue(forKey: peerID)
                }
                logger.info("Peer disconnected: \(peerID.displayName)")
            case .connecting:
                peerStates[peerID] = .connecting
                logger.info("Peer connecting: \(peerID.displayName)")
            @unknown default:
                break
            }
            refreshDiscoveredPeers()
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let events = try? JSONDecoder().decode([SyncEventTransfer].self, from: data) {
            Task { @MainActor in
                logger.info("Received \(events.count) events from \(peerID.displayName)")
                onEventsReceived?(events)
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension PeerSyncService: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerSyncService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            logger.info("Found peer: \(peerID.displayName)")
            peerInfo[peerID] = info ?? [:]
            if peerStates[peerID] == nil { peerStates[peerID] = .discovered }
            refreshDiscoveredPeers()
            guard let session else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            logger.info("Lost peer: \(peerID.displayName)")
            peerInfo.removeValue(forKey: peerID)
            // If not currently connected, remove from state map entirely.
            if peerStates[peerID] != .connected {
                peerStates.removeValue(forKey: peerID)
            }
            refreshDiscoveredPeers()
        }
    }
}

// MARK: - Transfer models

struct SyncEventTransfer: Codable, Sendable {
    var id: UUID
    var deviceId: String
    var lamportClock: Int
    var wallClockTimestamp: Date
    var payloadType: String
    var payloadJSON: Data
}

/// Lightweight snapshot of a peer we've seen over the network, exposed for UI.
struct DiscoveredPeer: Identifiable, Hashable {
    enum State: String { case discovered, connecting, connected }
    let displayName: String
    let state: State
    let role: String?
    let sessionId: String?
    let deviceId: String?

    var id: String { displayName }
}
