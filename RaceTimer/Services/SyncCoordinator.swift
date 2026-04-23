import Foundation
import SwiftData
@preconcurrency import MultipeerConnectivity
import os

/// App-scoped facade that ties `PeerSyncService` + `SyncEngine` + `ProjectionEngine` together.
///
/// All domain mutations go through `apply(_:)`. That single entry point:
///   1. Appends a `SyncEvent` to the local log with the next Lamport clock.
///   2. Runs `ProjectionEngine.rebuild` so SwiftData projections reflect the new event.
///   3. Saves the ModelContext (persist before broadcast to survive crashes).
///   4. Broadcasts the transfer to connected peers.
///
/// Remote events arrive via `PeerSyncService.onEventsReceived` and are merged
/// through `SyncEngine.mergeRemote` (idempotent by event id). On each newly
/// connected peer, the full local log is pushed to that peer for catch-up.
@MainActor
@Observable
final class SyncCoordinator {
    let deviceId: String
    let peerSync: PeerSyncService
    let syncEngine: SyncEngine

    @ObservationIgnored
    private let modelContext: ModelContext

    @ObservationIgnored
    private let logger = Logger(subsystem: "com.racetimerapp", category: "SyncCoordinator")

    private(set) var isStarted = false

    // MARK: - Observable sync stats (for UI)
    private(set) var eventsSent: Int = 0
    private(set) var eventsReceived: Int = 0
    private(set) var lastSentAt: Date?
    private(set) var lastReceivedAt: Date?

    init(modelContext: ModelContext, deviceId: String) {
        self.modelContext = modelContext
        self.deviceId = deviceId
        self.peerSync = PeerSyncService()
        self.syncEngine = SyncEngine()

        restoreLamportClock()
        wireCallbacks()
    }

    // MARK: - Transport lifecycle

    func start(role: String, activeSessionId: UUID? = nil) {
        peerSync.start(
            deviceId: deviceId,
            role: role,
            sessionId: activeSessionId?.uuidString
        )
        isStarted = true
    }

    func stop() {
        peerSync.stop()
        isStarted = false
    }

    // MARK: - Local mutation entry point

    /// Record a local mutation, apply it to projections, persist, and broadcast.
    @discardableResult
    func apply(_ payload: SyncPayload) -> SyncEventTransfer? {
        apply([payload]).first
    }

    /// Atomic batch — useful for compound mutations (e.g. creating a session
    /// plus its Start/Finish checkpoints in one broadcast).
    @discardableResult
    func apply(_ payloads: [SyncPayload]) -> [SyncEventTransfer] {
        guard !payloads.isEmpty else { return [] }
        let transfers = payloads.map { payload in
            syncEngine.recordLocal(payload: payload, deviceId: deviceId, in: modelContext)
        }
        do {
            let allEvents = try modelContext.fetch(FetchDescriptor<SyncEvent>())
            try ProjectionEngine.rebuild(from: allEvents, in: modelContext)
            try modelContext.save()
        } catch {
            logger.error("Local apply failed: \(error.localizedDescription)")
        }
        peerSync.sendEvents(transfers)
        if !transfers.isEmpty {
            eventsSent += transfers.count
            lastSentAt = Date()
        }
        return transfers
    }

    // MARK: - Setup

    private func wireCallbacks() {
        peerSync.onEventsReceived = { [weak self] transfers in
            self?.handleRemoteEvents(transfers)
        }
        peerSync.onPeerConnected = { [weak self] peer in
            self?.sendFullLog(to: [peer])
        }
    }

    private func handleRemoteEvents(_ transfers: [SyncEventTransfer]) {
        do {
            try syncEngine.mergeRemote(transfers, in: modelContext)
            try modelContext.save()
            eventsReceived += transfers.count
            lastReceivedAt = Date()
        } catch {
            logger.error("Remote merge failed: \(error.localizedDescription)")
        }
    }

    private func sendFullLog(to peers: [MCPeerID]) {
        do {
            let all = try syncEngine.allLocalEvents(in: modelContext)
            if !all.isEmpty {
                peerSync.sendEvents(all, to: peers)
                eventsSent += all.count
                lastSentAt = Date()
                logger.info("Pushed full log (\(all.count) events) to new peer(s)")
            }
        } catch {
            logger.error("Full-log send failed: \(error.localizedDescription)")
        }
    }

    private func restoreLamportClock() {
        do {
            let maxClock = try modelContext
                .fetch(FetchDescriptor<SyncEvent>())
                .map(\.lamportClock)
                .max() ?? 0
            // `receiveClock` sets lamportClock = max(current, remote) + 1.
            if maxClock > 0 {
                syncEngine.receiveClock(maxClock)
            }
        } catch {
            logger.error("Lamport restore failed: \(error.localizedDescription)")
        }
    }
}
