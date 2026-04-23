import Foundation
@preconcurrency import MultipeerConnectivity
import Network
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

    // MARK: - Network path monitoring
    //
    // When Wi-Fi drops (airplane mode, network switch, AP reconnect) MC
    // advertising/browsing silently dies. MC does not recover on its own —
    // the advertiser/browser/session must be torn down and recreated. We
    // watch NWPathMonitor and restart the stack on every satisfied edge.
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var lastPathSatisfied: Bool = true
    /// Remember last start params so we can restart transparently on network recovery.
    @ObservationIgnored private var lastStartParams: (deviceId: String, role: String, sessionId: String?)?

    override init() {
        self.peerId = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    // MARK: - Start / Stop

    func start(deviceId: String, role: String, sessionId: String? = nil) {
        lastStartParams = (deviceId, role, sessionId)
        if !isActive {
            bringUpStack(deviceId: deviceId, role: role, sessionId: sessionId)
        }
        startPathMonitorIfNeeded()
    }

    func stop() {
        tearDownStack()
        stopPathMonitor()
        lastStartParams = nil
        logger.info("Peer sync stopped")
    }

    /// Number of times `restart()` has run. Exposed for tests; not for UI.
    private(set) var restartCount: Int = 0

    /// Full restart of the MC stack while preserving last start params. Used on
    /// network-path recovery; safe to call even if the stack isn't running.
    func restart() {
        guard let params = lastStartParams else { return }
        restartCount += 1
        logger.info("Restarting peer sync stack")
        tearDownStack()
        bringUpStack(deviceId: params.deviceId, role: params.role, sessionId: params.sessionId)
    }

    /// Test hook: drive the network-path state machine without a real NWPathMonitor.
    func simulatePathChange(satisfied: Bool) {
        handlePathChange(satisfied: satisfied)
    }

    private func bringUpStack(deviceId: String, role: String, sessionId: String?) {
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

    private func tearDownStack() {
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
    }

    // MARK: - Network path monitoring

    private func startPathMonitorIfNeeded() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                self?.handlePathChange(satisfied: satisfied)
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.racetimerapp.PeerSync.path"))
        pathMonitor = monitor
        lastPathSatisfied = true // will be corrected on first update
    }

    private func stopPathMonitor() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    private func handlePathChange(satisfied: Bool) {
        let shouldRestart = Self.shouldRestart(
            satisfied: satisfied,
            lastSatisfied: lastPathSatisfied,
            hasStartParams: lastStartParams != nil
        )
        defer { lastPathSatisfied = satisfied }
        if shouldRestart {
            logger.info("Network path satisfied — restarting peer sync")
            restart()
        } else if !satisfied && lastPathSatisfied {
            logger.info("Network path lost — MC will be rebuilt when it returns")
        }
    }

    /// Pure decision function: should we kick the MC stack on this path edge?
    /// Restart only on a `.unsatisfied` -> `.satisfied` edge while sync was
    /// requested (i.e. `start` was called and `stop` hasn't been). Exposed
    /// internal so reconnection logic is unit-testable without a real network.
    static func shouldRestart(satisfied: Bool, lastSatisfied: Bool, hasStartParams: Bool) -> Bool {
        hasStartParams && satisfied && !lastSatisfied
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

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            logger.error("Advertiser failed to start: \(error.localizedDescription). Will retry on network recovery.")
        }
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

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            logger.error("Browser failed to start: \(error.localizedDescription). Will retry on network recovery.")
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
