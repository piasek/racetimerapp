import Foundation
import SwiftData

@Model
final class Checkpoint {
    @Attribute(.unique) var id: UUID
    var indexInCourse: Int
    var name: String
    /// Device that implicitly created this checkpoint (nil for Start/Finish
    /// or any checkpoint provisioned by the session organizer).
    var createdByDeviceId: String?

    var session: Session?

    init(
        id: UUID = UUID(),
        indexInCourse: Int,
        name: String,
        createdByDeviceId: String? = nil
    ) {
        self.id = id
        self.indexInCourse = indexInCourse
        self.name = name
        self.createdByDeviceId = createdByDeviceId
    }

    var isStart: Bool { indexInCourse == 0 }

    var isFinish: Bool {
        guard let session else { return false }
        let maxIndex = session.checkpoints.map(\.indexInCourse).max() ?? 0
        return indexInCourse == maxIndex
    }
}
