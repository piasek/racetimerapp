import Foundation
import SwiftData

/// The append-only event log entry — source of truth for sync.
@Model
final class SyncEvent {
    @Attribute(.unique) var id: UUID
    var deviceId: String
    var lamportClock: Int
    var wallClockTimestamp: Date
    var payloadType: String
    var payloadJSON: Data

    init(
        id: UUID = UUID(),
        deviceId: String,
        lamportClock: Int,
        wallClockTimestamp: Date = .now,
        payload: SyncPayload
    ) {
        self.id = id
        self.deviceId = deviceId
        self.lamportClock = lamportClock
        self.wallClockTimestamp = wallClockTimestamp
        self.payloadType = payload.payloadType
        self.payloadJSON = (try? JSONEncoder().encode(payload)) ?? Data()
    }

    var payload: SyncPayload? {
        try? JSONDecoder().decode(SyncPayload.self, from: payloadJSON)
    }
}

// MARK: - Sync payloads

enum SyncPayload: Codable, Sendable {
    case sessionUpserted(SessionPayload)
    case sessionDeleted(EntityIdPayload)
    case checkpointUpserted(CheckpointPayload)
    case checkpointDeleted(EntityIdPayload)
    case riderUpserted(RiderPayload)
    case riderDeleted(EntityIdPayload)
    case runCreated(RunPayload)
    case runDeleted(EntityIdPayload)
    case checkpointEventRecorded(CheckpointEventPayload)
    case checkpointEventEdited(CheckpointEventEditPayload)
    case runStatusChanged(RunStatusPayload)

    var payloadType: String {
        switch self {
        case .sessionUpserted: "sessionUpserted"
        case .sessionDeleted: "sessionDeleted"
        case .checkpointUpserted: "checkpointUpserted"
        case .checkpointDeleted: "checkpointDeleted"
        case .riderUpserted: "riderUpserted"
        case .riderDeleted: "riderDeleted"
        case .runCreated: "runCreated"
        case .runDeleted: "runDeleted"
        case .checkpointEventRecorded: "checkpointEventRecorded"
        case .checkpointEventEdited: "checkpointEventEdited"
        case .runStatusChanged: "runStatusChanged"
        }
    }
}

struct EntityIdPayload: Codable, Sendable {
    var id: UUID
}

struct SessionPayload: Codable, Sendable {
    var sessionId: UUID
    var name: String
    var date: Date
    var notes: String
}

struct CheckpointPayload: Codable, Sendable {
    var checkpointId: UUID
    var sessionId: UUID
    var indexInCourse: Int
    var name: String
}

struct RiderPayload: Codable, Sendable {
    var riderId: UUID
    var sessionId: UUID
    var firstName: String
    var lastName: String?
    var bibNumber: Int?
    var category: String?
    var notes: String?
}

struct RunPayload: Codable, Sendable {
    var runId: UUID
    var sessionId: UUID
    var riderId: UUID
    var status: String
}

struct CheckpointEventPayload: Codable, Sendable {
    var eventId: UUID
    var runId: UUID?
    var checkpointId: UUID
    var timestamp: Date
    var recordedByDeviceId: String
    var autoAssignedRiderId: UUID?
}

struct CheckpointEventEditPayload: Codable, Sendable {
    var eventId: UUID
    var reassignedRunId: UUID?
    var deleted: Bool?
    var ignored: Bool?
    var manualOverride: Bool?
    var note: String?
}

struct RunStatusPayload: Codable, Sendable {
    var runId: UUID
    var status: String
}
