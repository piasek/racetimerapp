import Testing
import Foundation
import SwiftData
@testable import RaceTimer

/// Creates an in-memory ModelContainer for testing.
func makeTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Session.self, Checkpoint.self, Rider.self, Run.self,
        CheckpointEvent.self, DeviceInfo.self, SyncEvent.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Run splits & total time

@MainActor
struct RunResultsTests {
    @Test func totalTimeFromStartToFinish() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let session = Session(name: "Test")
        context.insert(session)

        let start = Checkpoint(indexInCourse: 0, name: "Start")
        start.session = session
        context.insert(start)

        let finish = Checkpoint(indexInCourse: 1, name: "Finish")
        finish.session = session
        context.insert(finish)

        let rider = Rider(firstName: "Alice", bibNumber: 1)
        rider.session = session
        context.insert(rider)

        let run = Run(status: .started)
        run.rider = rider
        run.session = session
        context.insert(run)

        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1042.5)

        let e0 = CheckpointEvent(timestamp: t0, recordedByDeviceId: "d1")
        e0.run = run
        e0.checkpoint = start
        context.insert(e0)

        let e1 = CheckpointEvent(timestamp: t1, recordedByDeviceId: "d2")
        e1.run = run
        e1.checkpoint = finish
        context.insert(e1)

        #expect(run.totalTime == 42.5)
        #expect(run.splits.count == 1)
        #expect(run.splits.first?.elapsed == 42.5)
    }

    @Test func deletedEventsExcludedFromTotal() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let session = Session(name: "Test")
        context.insert(session)

        let cp0 = Checkpoint(indexInCourse: 0, name: "Start")
        cp0.session = session
        context.insert(cp0)

        let cp1 = Checkpoint(indexInCourse: 1, name: "Finish")
        cp1.session = session
        context.insert(cp1)

        let rider = Rider(firstName: "Bob")
        rider.session = session
        context.insert(rider)

        let run = Run(status: .started)
        run.rider = rider
        run.session = session
        context.insert(run)

        let e0 = CheckpointEvent(timestamp: Date(timeIntervalSince1970: 100), recordedByDeviceId: "d1")
        e0.run = run
        e0.checkpoint = cp0
        context.insert(e0)

        let e1 = CheckpointEvent(timestamp: Date(timeIntervalSince1970: 200), recordedByDeviceId: "d1", isTombstoned: true)
        e1.run = run
        e1.checkpoint = cp1
        context.insert(e1)

        #expect(run.totalTime == nil)
        #expect(run.effectiveEvents.count == 1)
    }

    @Test func splitsWithMultipleCheckpoints() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let session = Session(name: "Test")
        context.insert(session)

        let cpNames = ["Start", "Split 1", "Split 2", "Finish"]
        var checkpoints: [Checkpoint] = []
        for (i, name) in cpNames.enumerated() {
            let cp = Checkpoint(indexInCourse: i, name: name)
            cp.session = session
            context.insert(cp)
            checkpoints.append(cp)
        }

        let rider = Rider(firstName: "Charlie", bibNumber: 3)
        rider.session = session
        context.insert(rider)

        let run = Run(status: .finished)
        run.rider = rider
        run.session = session
        context.insert(run)

        let times: [TimeInterval] = [0, 10, 25, 42]
        for (i, t) in times.enumerated() {
            let event = CheckpointEvent(
                timestamp: Date(timeIntervalSince1970: t),
                recordedByDeviceId: "d1"
            )
            event.run = run
            event.checkpoint = checkpoints[i]
            context.insert(event)
        }

        #expect(run.splits.count == 3)
        #expect(run.splits[0].elapsed == 10)
        #expect(run.splits[1].elapsed == 15)
        #expect(run.splits[2].elapsed == 17)
        #expect(run.totalTime == 42)
    }
}

// MARK: - Run status derivation

struct RunStatusTests {
    @Test func statusEnumRoundTrips() {
        for status in RunStatus.allCases {
            let run = Run(status: status)
            #expect(run.status == status)
        }
    }
}

// MARK: - Projection engine

@MainActor
struct ProjectionEngineTests {
    @Test func projectionAppliesRiderUpsert() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let riderId = UUID()
        let event = SyncEvent(
            deviceId: "d1",
            lamportClock: 1,
            payload: .riderUpserted(RiderPayload(
                riderId: riderId,
                sessionId: UUID(),
                firstName: "Eve",
                lastName: "Smith",
                bibNumber: 7
            ))
        )
        context.insert(event)

        try ProjectionEngine.rebuild(from: [event], in: context)

        let riders = try context.fetch(FetchDescriptor<Rider>())
        #expect(riders.count == 1)
        #expect(riders.first?.firstName == "Eve")
        #expect(riders.first?.bibNumber == 7)
    }

    @Test func projectionAppliesEventsIdempotently() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let riderId = UUID()
        let event = SyncEvent(
            deviceId: "d1",
            lamportClock: 1,
            payload: .riderUpserted(RiderPayload(riderId: riderId, sessionId: UUID(), firstName: "Eve"))
        )
        context.insert(event)

        try ProjectionEngine.rebuild(from: [event, event], in: context)

        let riders = try context.fetch(FetchDescriptor<Rider>())
        #expect(riders.count == 1)
    }

    @Test func projectionMergesLastWriterWins() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let riderId = UUID()
        let sessionId = UUID()
        let e1 = SyncEvent(
            deviceId: "d1",
            lamportClock: 1,
            payload: .riderUpserted(RiderPayload(riderId: riderId, sessionId: sessionId, firstName: "Eve"))
        )
        let e2 = SyncEvent(
            deviceId: "d2",
            lamportClock: 2,
            payload: .riderUpserted(RiderPayload(riderId: riderId, sessionId: sessionId, firstName: "Updated"))
        )
        context.insert(e1)
        context.insert(e2)

        // Apply in reverse order — higher lamport clock should win.
        try ProjectionEngine.rebuild(from: [e2, e1], in: context)

        let riders = try context.fetch(FetchDescriptor<Rider>())
        #expect(riders.count == 1)
        #expect(riders.first?.firstName == "Updated")
    }
}

// MARK: - ModelContext.fetchByID

@MainActor
struct FetchByIDTests {
    @Test func fetchesCorrectSessionWhenMultipleExist() throws {
        let container = try makeTestContainer()
        let context = container.mainContext

        let first = Session(name: "First")
        let second = Session(name: "Second")
        context.insert(first)
        context.insert(second)
        try context.save()

        let fetchedFirst = try context.fetchByID(Session.self, id: first.id)
        let fetchedSecond = try context.fetchByID(Session.self, id: second.id)

        #expect(fetchedFirst?.id == first.id)
        #expect(fetchedSecond?.id == second.id)
    }
}
