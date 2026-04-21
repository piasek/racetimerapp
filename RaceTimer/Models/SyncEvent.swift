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
    case riderUpserted(RiderPayload)
    case runCreated(RunPayload)
    case checkpointEventRecorded(CheckpointEventPayload)
    case checkpointEventEdited(CheckpointEventEditPayload)
    case runStatusChanged(RunStatusPayload)

    var payloadType: String {
        switch self {
        case .riderUpserted: "riderUpserted"
        case .runCreated: "runCreated"
        case .checkpointEventRecorded: "checkpointEventRecorded"
        case .checkpointEventEdited: "checkpointEventEdited"
        case .runStatusChanged: "runStatusChanged"
        }
    }
}

struct RiderPayload: Codable, Sendable {
    var riderId: UUID
    var firstName: String
    var lastName: String?
    var bibNumber: Int?
    var category: String?
    var notes: String?
}

struct RunPayload: Codable, Sendable {
    var runId: UUID
    var riderId: UUID
    var status: String
}

struct CheckpointEventPayload: Codable, Sendable {
    var eventId: UUID
    var runId: UUID
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
