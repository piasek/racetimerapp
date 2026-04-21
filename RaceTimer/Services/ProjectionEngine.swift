import Foundation
import SwiftData

/// Rebuilds projected domain objects from the append-only SyncEvent log.
/// Uses last-writer-wins per (entityId, field), Lamport clock for ordering,
/// deviceId as tiebreaker.
struct ProjectionEngine {

    /// Apply a sorted sequence of SyncEvents to the given ModelContext,
    /// upserting Riders, Runs, and CheckpointEvents.
    static func rebuild(from events: [SyncEvent], in context: ModelContext) throws {
        let sorted = events.sorted { lhs, rhs in
            if lhs.lamportClock != rhs.lamportClock {
                return lhs.lamportClock < rhs.lamportClock
            }
            return lhs.deviceId < rhs.deviceId
        }

        for event in sorted {
            guard let payload = event.payload else { continue }
            switch payload {
            case .riderUpserted(let p):
                try applyRiderUpserted(p, clock: event.lamportClock, deviceId: event.deviceId, in: context)
            case .runCreated(let p):
                try applyRunCreated(p, in: context)
            case .checkpointEventRecorded(let p):
                try applyCheckpointEventRecorded(p, in: context)
            case .checkpointEventEdited(let p):
                try applyCheckpointEventEdited(p, in: context)
            case .runStatusChanged(let p):
                try applyRunStatusChanged(p, in: context)
            }
        }
    }

    // MARK: - Apply individual event types

    private static func applyRiderUpserted(
        _ p: RiderPayload,
        clock: Int,
        deviceId: String,
        in context: ModelContext
    ) throws {
        if let existing = try fetchRider(id: p.riderId, in: context) {
            existing.firstName = p.firstName
            existing.lastName = p.lastName
            existing.bibNumber = p.bibNumber
            existing.category = p.category
            existing.notes = p.notes
        } else {
            let rider = Rider(
                id: p.riderId,
                firstName: p.firstName,
                lastName: p.lastName,
                bibNumber: p.bibNumber,
                category: p.category,
                notes: p.notes
            )
            context.insert(rider)
        }
    }

    private static func applyRunCreated(_ p: RunPayload, in context: ModelContext) throws {
        guard try fetchRun(id: p.runId, in: context) == nil else { return }
        let run = Run(id: p.runId, status: RunStatus(rawValue: p.status) ?? .scheduled)
        run.rider = try fetchRider(id: p.riderId, in: context)
        context.insert(run)
    }

    private static func applyCheckpointEventRecorded(
        _ p: CheckpointEventPayload,
        in context: ModelContext
    ) throws {
        guard try fetchCheckpointEvent(id: p.eventId, in: context) == nil else { return }
        let event = CheckpointEvent(
            id: p.eventId,
            timestamp: p.timestamp,
            recordedByDeviceId: p.recordedByDeviceId,
            autoAssignedRiderId: p.autoAssignedRiderId
        )
        event.run = try fetchRun(id: p.runId, in: context)
        event.checkpoint = try fetchCheckpoint(id: p.checkpointId, in: context)
        context.insert(event)
    }

    private static func applyCheckpointEventEdited(
        _ p: CheckpointEventEditPayload,
        in context: ModelContext
    ) throws {
        guard let event = try fetchCheckpointEvent(id: p.eventId, in: context) else { return }
        if let reassignedRunId = p.reassignedRunId {
            event.run = try fetchRun(id: reassignedRunId, in: context)
            event.manualOverride = true
        }
        if let deleted = p.deleted { event.deleted = deleted }
        if let ignored = p.ignored { event.ignored = ignored }
        if let manualOverride = p.manualOverride { event.manualOverride = manualOverride }
        if let note = p.note { event.note = note }
    }

    private static func applyRunStatusChanged(_ p: RunStatusPayload, in context: ModelContext) throws {
        guard let run = try fetchRun(id: p.runId, in: context) else { return }
        run.status = RunStatus(rawValue: p.status) ?? run.status
    }

    // MARK: - Fetch helpers

    private static func fetchRider(id: UUID, in context: ModelContext) throws -> Rider? {
        try context.fetchByID(Rider.self, id: id)
    }

    private static func fetchRun(id: UUID, in context: ModelContext) throws -> Run? {
        try context.fetchByID(Run.self, id: id)
    }

    private static func fetchCheckpoint(id: UUID, in context: ModelContext) throws -> Checkpoint? {
        try context.fetchByID(Checkpoint.self, id: id)
    }

    private static func fetchCheckpointEvent(id: UUID, in context: ModelContext) throws -> CheckpointEvent? {
        try context.fetchByID(CheckpointEvent.self, id: id)
    }
}
