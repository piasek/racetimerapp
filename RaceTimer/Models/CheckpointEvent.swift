import Foundation
import SwiftData

@Model
final class CheckpointEvent {
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var recordedByDeviceId: String
    var autoAssignedRiderId: UUID?
    var manualOverride: Bool
    var ignored: Bool
    var isTombstoned: Bool
    var note: String?

    var run: Run?
    var checkpoint: Checkpoint?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        recordedByDeviceId: String = "",
        autoAssignedRiderId: UUID? = nil,
        manualOverride: Bool = false,
        ignored: Bool = false,
        isTombstoned: Bool = false,
        note: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.recordedByDeviceId = recordedByDeviceId
        self.autoAssignedRiderId = autoAssignedRiderId
        self.manualOverride = manualOverride
        self.ignored = ignored
        self.isTombstoned = isTombstoned
        self.note = note
    }
}
