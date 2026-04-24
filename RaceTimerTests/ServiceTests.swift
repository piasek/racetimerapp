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
                    sessionId: sessionId, name: "Race 1", date: .now, notes: ""
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
                    sessionId: sessionId, name: "S", date: .now, notes: ""
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
                    sessionId: sessionId, name: "S", date: .now, notes: ""
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
            sessionId: sessionId, name: "Race", date: .now, notes: ""
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
                sessionId: sessionId, name: "S", date: .now, notes: ""
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
            sessionId: UUID(), name: "X", date: .now, notes: ""
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

// MARK: - Issue #5: Finish-line shift on accidental-tap delete

@MainActor
@Suite
struct FinishLineShiftTests {
    /// Builds a session with `riderCount` riders, all started, and a finish
    /// CheckpointEvent for each rider in start order. Returns (session, finishCp, runs).
    private func makeFinishedScenario(
        in context: ModelContext,
        riderCount: Int
    ) throws -> (Session, Checkpoint, [Run]) {
        let sessionId = UUID()
        let startId = UUID()
        let finishId = UUID()
        var events: [SyncEvent] = [
            SyncEvent(deviceId: "a", lamportClock: 1, payload: .sessionUpserted(SessionPayload(
                sessionId: sessionId, name: "S", date: .now, notes: ""))),
            SyncEvent(deviceId: "a", lamportClock: 2, payload: .checkpointUpserted(CheckpointPayload(
                checkpointId: startId, sessionId: sessionId, indexInCourse: 0, name: "Start"))),
            SyncEvent(deviceId: "a", lamportClock: 3, payload: .checkpointUpserted(CheckpointPayload(
                checkpointId: finishId, sessionId: sessionId, indexInCourse: 1, name: "Finish"))),
        ]
        var clock = 4
        var riderIds: [UUID] = []
        var runIds: [UUID] = []
        let baseStart = Date(timeIntervalSince1970: 1_000_000)
        for i in 0..<riderCount {
            let riderId = UUID()
            let runId = UUID()
            riderIds.append(riderId)
            runIds.append(runId)
            events.append(SyncEvent(deviceId: "a", lamportClock: clock, payload: .riderUpserted(
                RiderPayload(riderId: riderId, sessionId: sessionId, firstName: "R\(i)"))))
            clock += 1
            events.append(SyncEvent(deviceId: "a", lamportClock: clock, payload: .runCreated(
                RunPayload(runId: runId, sessionId: sessionId, riderId: riderId, status: RunStatus.started.rawValue))))
            clock += 1
            // Start checkpoint event so totalTime can be computed
            events.append(SyncEvent(deviceId: "a", lamportClock: clock, payload: .checkpointEventRecorded(
                CheckpointEventPayload(eventId: UUID(), runId: runId, checkpointId: startId,
                    timestamp: baseStart.addingTimeInterval(Double(i)),
                    recordedByDeviceId: "a", autoAssignedRiderId: riderId))))
            clock += 1
        }
        // Finish events in start order, 10s apart
        let baseFinish = baseStart.addingTimeInterval(60)
        for i in 0..<riderCount {
            events.append(SyncEvent(deviceId: "a", lamportClock: clock, payload: .checkpointEventRecorded(
                CheckpointEventPayload(eventId: UUID(), runId: runIds[i], checkpointId: finishId,
                    timestamp: baseFinish.addingTimeInterval(Double(i) * 10),
                    recordedByDeviceId: "a", autoAssignedRiderId: riderIds[i]))))
            clock += 1
            events.append(SyncEvent(deviceId: "a", lamportClock: clock, payload: .runStatusChanged(
                RunStatusPayload(runId: runIds[i], status: RunStatus.finished.rawValue))))
            clock += 1
        }
        events.forEach { context.insert($0) }
        try ProjectionEngine.rebuild(from: events, in: context)
        try context.save()

        let session = try #require(try context.fetchByID(Session.self, id: sessionId))
        let finishCp = try #require(try context.fetchByID(Checkpoint.self, id: finishId))
        let runs = try runIds.map { try #require(try context.fetchByID(Run.self, id: $0)) }
        return (session, finishCp, runs)
    }

    /// Returns finish events for `cp`, sorted by timestamp ascending,
    /// excluding tombstoned ones.
    private func finishEvents(_ session: Session, _ cp: Checkpoint) -> [CheckpointEvent] {
        session.runs
            .flatMap(\.events)
            .filter { $0.checkpoint?.id == cp.id && !$0.isTombstoned }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Apply the same shift logic the FinishLineView uses. Mirroring it here
    /// keeps the test focused on observable behavior without launching SwiftUI.
    private func applyAccidentalDelete(
        eventToDelete event: CheckpointEvent,
        in session: Session,
        finish cp: Checkpoint,
        coord: SyncCoordinator
    ) {
        let ordered = finishEvents(session, cp)
        guard let idx = ordered.firstIndex(where: { $0.id == event.id }) else { return }
        let preRunIds = Set(ordered.compactMap { $0.run?.id })
        var payloads: [SyncPayload] = [
            .checkpointEventEdited(CheckpointEventEditPayload(
                eventId: ordered[idx].id, reassignedRunId: nil, deleted: true,
                ignored: nil, manualOverride: nil, note: nil))
        ]
        for j in (idx + 1)..<ordered.count {
            if let prev = ordered[j - 1].run?.id {
                payloads.append(.checkpointEventEdited(CheckpointEventEditPayload(
                    eventId: ordered[j].id, reassignedRunId: prev, deleted: nil,
                    ignored: nil, manualOverride: nil, note: nil)))
            }
        }
        var post: Set<UUID> = []
        for (i, e) in ordered.enumerated() where i != idx {
            let assigned = i < idx ? e.run?.id : ordered[i - 1].run?.id
            if let assigned { post.insert(assigned) }
        }
        for runId in preRunIds.subtracting(post) {
            payloads.append(.runStatusChanged(RunStatusPayload(
                runId: runId, status: RunStatus.started.rawValue)))
        }
        coord.apply(payloads)
    }

    @Test func deletingMiddleFinishShiftsLaterRidersUp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (session, finish, runs) = try makeFinishedScenario(in: context, riderCount: 4)
        let coord = SyncCoordinator(modelContext: context, deviceId: "dev-1")
        let ordered = finishEvents(session, finish)
        // Sanity: each rider initially mapped to its own event.
        #expect(zip(ordered, runs).allSatisfy { $0.0.run?.id == $0.1.id })
        let toDeleteId = ordered[1].id

        // Delete the second tap (idx=1) — accidental.
        applyAccidentalDelete(eventToDelete: ordered[1], in: session, finish: finish, coord: coord)

        // Re-fetch to bypass any stale relationship caches.
        let freshSession = try #require(try context.fetchByID(Session.self, id: session.id))
        let freshFinish = try #require(try context.fetchByID(Checkpoint.self, id: finish.id))
        let freshRuns = try runs.map { try #require(try context.fetchByID(Run.self, id: $0.id)) }
        let deletedEvent = try #require(try context.fetchByID(CheckpointEvent.self, id: toDeleteId))
        #expect(deletedEvent.isTombstoned == true)
        let after = finishEvents(freshSession, freshFinish)
        #expect(after.count == 3)
        #expect(after[0].run?.id == freshRuns[0].id)
        #expect(after[1].run?.id == freshRuns[1].id)
        #expect(after[2].run?.id == freshRuns[2].id)
        #expect(freshRuns[3].status == .started)
        // R0..R2 stay finished
        #expect(freshRuns[0].status == .finished)
        #expect(freshRuns[1].status == .finished)
        #expect(freshRuns[2].status == .finished)
    }

    @Test func deletingLastFinishOnlyRevertsThatRider() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (session, finish, runs) = try makeFinishedScenario(in: context, riderCount: 3)
        let coord = SyncCoordinator(modelContext: context, deviceId: "dev-1")
        let ordered = finishEvents(session, finish)

        applyAccidentalDelete(eventToDelete: ordered[2], in: session, finish: finish, coord: coord)

        let freshSession = try #require(try context.fetchByID(Session.self, id: session.id))
        let freshFinish = try #require(try context.fetchByID(Checkpoint.self, id: finish.id))
        let freshRuns = try runs.map { try #require(try context.fetchByID(Run.self, id: $0.id)) }
        let after = finishEvents(freshSession, freshFinish)
        #expect(after.count == 2)
        #expect(after[0].run?.id == freshRuns[0].id)
        #expect(after[1].run?.id == freshRuns[1].id)
        #expect(freshRuns[0].status == .finished)
        #expect(freshRuns[1].status == .finished)
        #expect(freshRuns[2].status == .started)
    }

    @Test func deletingFirstFinishShiftsAllUp() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let (session, finish, runs) = try makeFinishedScenario(in: context, riderCount: 3)
        let coord = SyncCoordinator(modelContext: context, deviceId: "dev-1")
        let ordered = finishEvents(session, finish)

        applyAccidentalDelete(eventToDelete: ordered[0], in: session, finish: finish, coord: coord)

        let freshSession = try #require(try context.fetchByID(Session.self, id: session.id))
        let freshFinish = try #require(try context.fetchByID(Checkpoint.self, id: finish.id))
        let freshRuns = try runs.map { try #require(try context.fetchByID(Run.self, id: $0.id)) }
        let after = finishEvents(freshSession, freshFinish)
        #expect(after.count == 2)
        #expect(after[0].run?.id == freshRuns[0].id)
        #expect(after[1].run?.id == freshRuns[1].id)
        #expect(freshRuns[2].status == .started)
    }
}

// MARK: - Issue #4: Implicit per-device checkpoint creation

@MainActor
struct ImplicitCheckpointTests {
    private func makeBaseSession(in context: ModelContext) throws -> Session {
        let sessionId = UUID()
        let events: [SyncEvent] = [
            SyncEvent(deviceId: "a", lamportClock: 1, payload: .sessionUpserted(SessionPayload(
                sessionId: sessionId, name: "S", date: .now, notes: ""))),
            SyncEvent(deviceId: "a", lamportClock: 2, payload: .checkpointUpserted(CheckpointPayload(
                checkpointId: UUID(), sessionId: sessionId, indexInCourse: 0, name: "Start"))),
            SyncEvent(deviceId: "a", lamportClock: 3, payload: .checkpointUpserted(CheckpointPayload(
                checkpointId: UUID(), sessionId: sessionId, indexInCourse: 1, name: "Finish"))),
        ]
        events.forEach { context.insert($0) }
        try ProjectionEngine.rebuild(from: events, in: context)
        return try #require(try context.fetchByID(Session.self, id: sessionId))
    }

    @Test func createdByDeviceIdRoundTripsThroughProjection() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let coord = SyncCoordinator(modelContext: context, deviceId: "dev-X")
        let session = try makeBaseSession(in: context)

        let cpId = UUID()
        coord.apply(.checkpointUpserted(CheckpointPayload(
            checkpointId: cpId,
            sessionId: session.id,
            indexInCourse: 1,
            name: "Checkpoint - Phone X",
            createdByDeviceId: "dev-X"
        )))

        let cp = try #require(try context.fetchByID(Checkpoint.self, id: cpId))
        #expect(cp.createdByDeviceId == "dev-X")
        #expect(cp.name == "Checkpoint - Phone X")
    }

    @Test func twoDevicesGetIndependentCheckpoints() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let session = try makeBaseSession(in: context)

        let coordA = SyncCoordinator(modelContext: context, deviceId: "dev-A")
        let coordB = SyncCoordinator(modelContext: context, deviceId: "dev-B")

        coordA.apply(.checkpointUpserted(CheckpointPayload(
            checkpointId: UUID(), sessionId: session.id, indexInCourse: 1,
            name: "Checkpoint - A", createdByDeviceId: "dev-A")))
        coordB.apply(.checkpointUpserted(CheckpointPayload(
            checkpointId: UUID(), sessionId: session.id, indexInCourse: 1,
            name: "Checkpoint - B", createdByDeviceId: "dev-B")))

        let aCps = session.checkpoints.filter { $0.createdByDeviceId == "dev-A" }
        let bCps = session.checkpoints.filter { $0.createdByDeviceId == "dev-B" }
        #expect(aCps.count == 1)
        #expect(bCps.count == 1)
        #expect(aCps.first?.id != bCps.first?.id)
    }

    @Test func startAndFinishHaveNilCreator() throws {
        let container = try makeTestContainer()
        let context = container.mainContext
        let session = try makeBaseSession(in: context)
        for cp in session.checkpoints {
            #expect(cp.createdByDeviceId == nil)
        }
    }
}
