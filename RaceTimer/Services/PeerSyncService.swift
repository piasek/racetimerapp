import Foundation
import MultipeerConnectivity
import SwiftData
import os

/// Manages MultipeerConnectivity for peer-to-peer sync between devices.
@MainActor
@Observable
final class PeerSyncService: NSObject {
    private static let serviceType = "racetimer-sync" // max 15 chars, lowercase + hyphens

    private let peerId: MCPeerID
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private(set) var connectedPeers: [MCPeerID] = []
    private(set) var isActive = false

    var onEventsReceived: (([SyncEventTransfer]) -> Void)?

    private let logger = Logger(subsystem: "com.racetimerapp", category: "PeerSync")

    override init() {
        self.peerId = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    // MARK: - Start / Stop

    func start(deviceId: String, role: String) {
        guard !isActive else { return }

        let session = MCSession(peer: peerId, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let discoveryInfo = ["deviceId": deviceId, "role": role]

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
        isActive = false
        logger.info("Peer sync stopped")
    }

    // MARK: - Send events

    func sendEvents(_ events: [SyncEventTransfer]) {
        guard let session, !session.connectedPeers.isEmpty else { return }
        do {
            let data = try JSONEncoder().encode(events)
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            logger.info("Sent \(events.count) events to \(session.connectedPeers.count) peers")
        } catch {
            logger.error("Failed to send events: \(error.localizedDescription)")
        }
    }

    /// Request a full sync from all connected peers.
    func requestFullSync() {
        guard let session, !session.connectedPeers.isEmpty else { return }
        let request = SyncRequest(type: .fullSync)
        if let data = try? JSONEncoder().encode(request) {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
        }
    }
}

// MARK: - MCSessionDelegate

extension PeerSyncService: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        let peers = session.connectedPeers
        Task { @MainActor in
            connectedPeers = peers
            switch state {
            case .connected:
                logger.info("Peer connected: \(peerID.displayName)")
            case .notConnected:
                logger.info("Peer disconnected: \(peerID.displayName)")
            case .connecting:
                logger.info("Peer connecting: \(peerID.displayName)")
            @unknown default:
                break
            }
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
        // Auto-accept all invitations from nearby peers
        Task { @MainActor in
            invitationHandler(true, session)
        }
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension PeerSyncService: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            logger.info("Found peer: \(peerID.displayName)")
            guard let session else { return }
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            logger.info("Lost peer: \(peerID.displayName)")
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

struct SyncRequest: Codable {
    enum RequestType: String, Codable {
        case fullSync
    }
    var type: RequestType
}
