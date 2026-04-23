import Testing
import Foundation
import SwiftData
@testable import RaceTimer

// MARK: - SyncEngine Lamport clock tests

struct SyncEngineTests {
    @Test @MainActor func lamportClockIncrements() {
        let engine = SyncEngine()
        let c1 = engine.nextClock()
        let c2 = engine.nextClock()
        #expect(c1 == 1)
        #expect(c2 == 2)
    }

    @Test @MainActor func receiveClockAdvancesToMax() {
        let engine = SyncEngine()
        _ = engine.nextClock() // 1
        engine.receiveClock(10)
        #expect(engine.lamportClock == 11)
        let next = engine.nextClock()
        #expect(next == 12)
    }

    @Test @MainActor func mergeRemoteIdempotent() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let engine = SyncEngine()

        let riderId = UUID()
        let payload = SyncPayload.riderUpserted(RiderPayload(
            riderId: riderId,
            sessionId: UUID(),
            firstName: "Test"
        ))
        let transfer = SyncEventTransfer(
            id: UUID(),
            deviceId: "remote-1",
            lamportClock: 5,
            wallClockTimestamp: .now,
            payloadType: payload.payloadType,
            payloadJSON: (try? JSONEncoder().encode(payload)) ?? Data()
        )

        try engine.mergeRemote([transfer], in: context)
        try engine.mergeRemote([transfer], in: context) // duplicate

        let events = try context.fetch(FetchDescriptor<SyncEvent>())
        #expect(events.count == 1)
    }

    @Test @MainActor func mergeRemoteProjectsRider() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let engine = SyncEngine()

        let riderId = UUID()
        let payload = SyncPayload.riderUpserted(RiderPayload(
            riderId: riderId,
            sessionId: UUID(),
            firstName: "Alice",
            lastName: "Smith",
            bibNumber: 42
        ))
        let transfer = SyncEventTransfer(
            id: UUID(),
            deviceId: "remote-1",
            lamportClock: 1,
            wallClockTimestamp: .now,
            payloadType: payload.payloadType,
            payloadJSON: (try? JSONEncoder().encode(payload)) ?? Data()
        )

        try engine.mergeRemote([transfer], in: context)

        let riders = try context.fetch(FetchDescriptor<Rider>())
        #expect(riders.count == 1)
        #expect(riders.first?.firstName == "Alice")
        #expect(riders.first?.bibNumber == 42)
    }
}

// MARK: - Extended projection: session, checkpoint, tombstones

@MainActor
struct ExtendedProjectionTests {
    @Test func sessionAndCheckpointUpsertCreateLinkedRider() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let sessionId = UUID()
        let startId = UUID()
        let finishId = UUID()
        let riderId = UUID()

        let events = [
            SyncEvent(deviceId: "a", lamportClock: 1,
                payload: .sessionUpserted(SessionPayload(
                    sessionId: sessionId, name: "Race 1", date: .now, courseName: "", notes: ""
                ))),
            SyncEvent(deviceId: "a", lamportClock: 2,
                payload: .checkpointUpserted(CheckpointPayload(
                    checkpointId: startId, sessionId: sessionId, indexInCourse: 0, name: "Start"
                ))),
            SyncEvent(deviceId: "a", lamportClock: 3,
                payload: .checkpointUpserted(CheckpointPayload(
                    checkpointId: finishId, sessionId: sessionId, indexInCourse: 1, name: "Finish"
                ))),
            SyncEvent(deviceId: "a", lamportClock: 4,
                payload: .riderUpserted(RiderPayload(
                    riderId: riderId, sessionId: sessionId, firstName: "A"
                ))),
        ]
        events.forEach { context.insert($0) }
        try ProjectionEngine.rebuild(from: events, in: context)

        let session = try context.fetchByID(Session.self, id: sessionId)
        #expect(session?.checkpoints.count == 2)
        #expect(session?.riders.count == 1)
        #expect(session?.riders.first?.firstName == "A")
    }

    @Test func riderDeletedTombstoneRemovesRider() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let sessionId = UUID()
        let riderId = UUID()
        let events = [
            SyncEvent(deviceId: "a", lamportClock: 1,
                payload: .sessionUpserted(SessionPayload(
                    sessionId: sessionId, name: "S", date: .now, courseName: "", notes: ""
                ))),
            SyncEvent(deviceId: "a", lamportClock: 2,
                payload: .riderUpserted(RiderPayload(
                    riderId: riderId, sessionId: sessionId, firstName: "A"
                ))),
            SyncEvent(deviceId: "b", lamportClock: 3,
                payload: .riderDeleted(EntityIdPayload(id: riderId))),
        ]
        events.forEach { context.insert($0) }
        try ProjectionEngine.rebuild(from: events, in: context)

        #expect(try context.fetchByID(Rider.self, id: riderId) == nil)
    }

    @Test func outOfOrderReplayConvergesToDeletion() throws {
        // Same events as above but given to rebuild in reverse. Projection
        // sorts by (lamport, deviceId) so final state must still be "deleted".
        let container = try makeTestContainer()
        let context = container.mainContext

        let sessionId = UUID()
        let riderId = UUID()
        let events = [
            SyncEvent(deviceId: "b", lamportClock: 3,
                payload: .riderDeleted(EntityIdPayload(id: riderId))),
            SyncEvent(deviceId: "a", lamportClock: 2,
                payload: .riderUpserted(RiderPayload(
                    riderId: riderId, sessionId: sessionId, firstName: "A"
                ))),
            SyncEvent(deviceId: "a", lamportClock: 1,
                payload: .sessionUpserted(SessionPayload(
                    sessionId: sessionId, name: "S", date: .now, courseName: "", notes: ""
                ))),
        ]
        events.forEach { context.insert($0) }
        try ProjectionEngine.rebuild(from: events, in: context)

        #expect(try context.fetchByID(Rider.self, id: riderId) == nil)
    }
}

// MARK: - SyncCoordinator

@MainActor
struct SyncCoordinatorTests {
    @Test func applyRecordsEventProjectsAndPersists() throws {
        let container = try makeTestContainer()
        let coord = SyncCoordinator(modelContext: container.mainContext, deviceId: "dev-1")

        let sessionId = UUID()
        coord.apply(.sessionUpserted(SessionPayload(
            sessionId: sessionId, name: "Race", date: .now, courseName: "", notes: ""
        )))

        let context = container.mainContext
        let events = try context.fetch(FetchDescriptor<SyncEvent>())
        #expect(events.count == 1)
        #expect(events.first?.lamportClock == 1)
        #expect(events.first?.deviceId == "dev-1")

        let session = try context.fetchByID(Session.self, id: sessionId)
        #expect(session?.name == "Race")
    }

    @Test func atomicBatchPreservesOrder() throws {
        let container = try makeTestContainer()
        let coord = SyncCoordinator(modelContext: container.mainContext, deviceId: "dev-1")

        let sessionId = UUID()
        let cpId = UUID()
        coord.apply([
            .sessionUpserted(SessionPayload(
                sessionId: sessionId, name: "S", date: .now, courseName: "", notes: ""
            )),
            .checkpointUpserted(CheckpointPayload(
                checkpointId: cpId, sessionId: sessionId, indexInCourse: 0, name: "Start"
            )),
        ])

        let cp = try container.mainContext.fetchByID(Checkpoint.self, id: cpId)
        #expect(cp?.session?.id == sessionId)
    }

    @Test func restoresLamportClockFromExistingEvents() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        // Seed a pre-existing event with a high Lamport clock.
        let seed = SyncEvent(
            deviceId: "old",
            lamportClock: 42,
            payload: .sessionDeleted(EntityIdPayload(id: UUID()))
        )
        context.insert(seed)
        try context.save()

        let coord = SyncCoordinator(modelContext: context, deviceId: "dev-1")
        let transfer = coord.apply(.sessionUpserted(SessionPayload(
            sessionId: UUID(), name: "X", date: .now, courseName: "", notes: ""
        )))

        #expect(transfer?.lamportClock == 44)
    }
}

// MARK: - ClockService tests

struct ClockServiceTests {
    @Test @MainActor func noSkewInitially() {
        let clock = ClockService()
        #expect(!clock.hasSkewWarning)
        #expect(clock.worstSkewDescription == nil)
    }

    @Test @MainActor func detectsSkewAboveThreshold() {
        let clock = ClockService()
        // Simulate a pong where the remote clock is 1 second ahead
        let ping = ClockPing(
            sentAt: Date(timeIntervalSince1970: 1000),
            receivedAt: Date(timeIntervalSince1970: 1001.5), // remote got it "late" = ahead
            replyAt: Date(timeIntervalSince1970: 1001.5)
        )
        clock.processPong(ping, from: "peer-1")
        #expect(clock.hasSkewWarning)
        #expect(clock.worstSkewDescription != nil)
    }

    @Test @MainActor func removePeerClearsOffset() {
        let clock = ClockService()
        let ping = ClockPing(
            sentAt: Date(timeIntervalSince1970: 1000),
            receivedAt: Date(timeIntervalSince1970: 1002),
            replyAt: Date(timeIntervalSince1970: 1002)
        )
        clock.processPong(ping, from: "peer-1")
        #expect(clock.hasSkewWarning)
        clock.removePeer("peer-1")
        #expect(!clock.hasSkewWarning)
    }
}

// MARK: - CSV export tests

struct ExportTests {
    @Test func csvEscaping() {
        // Test the escaping logic inline
        func escapeCSV(_ value: String) -> String {
            if value.contains(",") || value.contains("\"") || value.contains("\n") {
                return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
            }
            return value
        }

        #expect(escapeCSV("simple") == "simple")
        #expect(escapeCSV("has,comma") == "\"has,comma\"")
        #expect(escapeCSV("has\"quote") == "\"has\"\"quote\"")
        #expect(escapeCSV("line\nbreak") == "\"line\nbreak\"")
    }
}

// MARK: - PeerSyncService reconnection

@MainActor
struct PeerSyncReconnectTests {
    // The pure decision function — exhaustive truth table.

    @Test func neverRestartsBeforeStart() {
        // hasStartParams=false: any path change must not trigger restart.
        #expect(PeerSyncService.shouldRestart(satisfied: true,  lastSatisfied: false, hasStartParams: false) == false)
        #expect(PeerSyncService.shouldRestart(satisfied: true,  lastSatisfied: true,  hasStartParams: false) == false)
        #expect(PeerSyncService.shouldRestart(satisfied: false, lastSatisfied: true,  hasStartParams: false) == false)
        #expect(PeerSyncService.shouldRestart(satisfied: false, lastSatisfied: false, hasStartParams: false) == false)
    }

    @Test func restartsOnlyOnRecoveryEdge() {
        // Edge unsatisfied -> satisfied: restart.
        #expect(PeerSyncService.shouldRestart(satisfied: true,  lastSatisfied: false, hasStartParams: true) == true)
        // Steady satisfied: no restart.
        #expect(PeerSyncService.shouldRestart(satisfied: true,  lastSatisfied: true,  hasStartParams: true) == false)
        // Drop edge satisfied -> unsatisfied: no restart (we wait for recovery).
        #expect(PeerSyncService.shouldRestart(satisfied: false, lastSatisfied: true,  hasStartParams: true) == false)
        // Steady unsatisfied: no restart.
        #expect(PeerSyncService.shouldRestart(satisfied: false, lastSatisfied: false, hasStartParams: true) == false)
    }

    // End-to-end path-change scenario via the test hook.

    @Test func wifiDropAndRecoveryTriggersExactlyOneRestart() {
        let svc = PeerSyncService()
        svc.start(deviceId: "dev-1", role: "observer")
        #expect(svc.isActive)
        #expect(svc.restartCount == 0)

        // Simulate: airplane mode on (path becomes unsatisfied).
        svc.simulatePathChange(satisfied: false)
        #expect(svc.restartCount == 0, "Drop alone must not restart")

        // Simulate: airplane mode off / Wi-Fi back (path becomes satisfied again).
        svc.simulatePathChange(satisfied: true)
        #expect(svc.restartCount == 1, "Recovery edge must restart exactly once")
        #expect(svc.isActive, "Stack must be active after restart")

        svc.stop()
    }

    @Test func steadyPathDoesNotRestart() {
        let svc = PeerSyncService()
        svc.start(deviceId: "dev-1", role: "observer")

        // Multiple "still satisfied" updates must not trigger restarts.
        svc.simulatePathChange(satisfied: true)
        svc.simulatePathChange(satisfied: true)
        svc.simulatePathChange(satisfied: true)
        #expect(svc.restartCount == 0)

        svc.stop()
    }

    @Test func pathRecoveryBeforeStartIsIgnored() {
        let svc = PeerSyncService()
        // No start() called yet — path edges should not bring up the stack.
        svc.simulatePathChange(satisfied: false)
        svc.simulatePathChange(satisfied: true)
        #expect(svc.restartCount == 0)
        #expect(svc.isActive == false)
    }

    @Test func stopThenPathRecoveryDoesNotRestart() {
        let svc = PeerSyncService()
        svc.start(deviceId: "dev-1", role: "observer")
        svc.stop()
        // A late path edge after stop must not silently bring sync back up.
        svc.simulatePathChange(satisfied: false)
        svc.simulatePathChange(satisfied: true)
        #expect(svc.restartCount == 0)
        #expect(svc.isActive == false)
    }

    @Test func restartPreservesStartParams() {
        let svc = PeerSyncService()
        svc.start(deviceId: "dev-1", role: "start", sessionId: "s-42")
        #expect(svc.isActive)

        svc.restart()
        #expect(svc.restartCount == 1)
        // After an explicit restart, the stack is still active and a subsequent
        // recovery edge would restart again — params were retained.
        svc.simulatePathChange(satisfied: false)
        svc.simulatePathChange(satisfied: true)
        #expect(svc.restartCount == 2)

        svc.stop()
    }

    @Test func restartIsNoOpWhenNeverStarted() {
        let svc = PeerSyncService()
        svc.restart()
        #expect(svc.restartCount == 0)
        #expect(svc.isActive == false)
    }
}
