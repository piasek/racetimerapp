import Foundation
import SwiftData
import os

/// Orchestrates merging incoming sync events into the local store.
/// Maintains a Lamport clock for outgoing events.
@MainActor
@Observable
final class SyncEngine {
    private(set) var lamportClock: Int = 0
    private let logger = Logger(subsystem: "com.racetimerapp", category: "SyncEngine")

    /// Increment and return the next Lamport clock value for a local event.
    func nextClock() -> Int {
        lamportClock += 1
        return lamportClock
    }

    /// Update clock on receiving a remote event.
    func receiveClock(_ remoteClock: Int) {
        lamportClock = max(lamportClock, remoteClock) + 1
    }

    /// Record a local mutation as a SyncEvent and return it for broadcast.
    func recordLocal(
        payload: SyncPayload,
        deviceId: String,
        in context: ModelContext
    ) -> SyncEventTransfer {
        let clock = nextClock()
        let event = SyncEvent(
            deviceId: deviceId,
            lamportClock: clock,
            payload: payload
        )
        context.insert(event)

        return SyncEventTransfer(
            id: event.id,
            deviceId: event.deviceId,
            lamportClock: event.lamportClock,
            wallClockTimestamp: event.wallClockTimestamp,
            payloadType: event.payloadType,
            payloadJSON: event.payloadJSON
        )
    }

    /// Merge incoming remote events: insert into the event log, then re-project.
    func mergeRemote(
        _ transfers: [SyncEventTransfer],
        in context: ModelContext
    ) throws {
        var newEvents: [SyncEvent] = []

        for transfer in transfers {
            receiveClock(transfer.lamportClock)

            // Check if we already have this event (idempotency)
            if try context.fetchByID(SyncEvent.self, id: transfer.id) != nil {
                continue
            }

            let event = SyncEvent(
                id: transfer.id,
                deviceId: transfer.deviceId,
                lamportClock: transfer.lamportClock,
                wallClockTimestamp: transfer.wallClockTimestamp,
                payload: .sessionDeleted(EntityIdPayload(id: UUID())) // placeholder, overwritten below
            )
            // Overwrite with actual payload data
            event.payloadType = transfer.payloadType
            event.payloadJSON = transfer.payloadJSON
            context.insert(event)
            newEvents.append(event)
        }

        if !newEvents.isEmpty {
            logger.info("Merged \(newEvents.count) new remote events")
            // Re-project from the full log
            let allEvents = try context.fetch(FetchDescriptor<SyncEvent>())
            try ProjectionEngine.rebuild(from: allEvents, in: context)
        }
    }

    /// Get all local events for sending to peers (full sync).
    func allLocalEvents(in context: ModelContext) throws -> [SyncEventTransfer] {
        let events = try context.fetch(FetchDescriptor<SyncEvent>())
        return events.map { event in
            SyncEventTransfer(
                id: event.id,
                deviceId: event.deviceId,
                lamportClock: event.lamportClock,
                wallClockTimestamp: event.wallClockTimestamp,
                payloadType: event.payloadType,
                payloadJSON: event.payloadJSON
            )
        }
    }
}
