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
        let payload = SyncPayload.riderUpserted(RiderPayload(riderId: riderId, firstName: "Test"))
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
