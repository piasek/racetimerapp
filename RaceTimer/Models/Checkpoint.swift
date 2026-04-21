import Foundation
import SwiftData

@Model
final class Checkpoint {
    @Attribute(.unique) var id: UUID
    var indexInCourse: Int
    var name: String

    var session: Session?

    init(id: UUID = UUID(), indexInCourse: Int, name: String) {
        self.id = id
        self.indexInCourse = indexInCourse
        self.name = name
    }

    var isStart: Bool { indexInCourse == 0 }

    var isFinish: Bool {
        guard let session else { return false }
        let maxIndex = session.checkpoints.map(\.indexInCourse).max() ?? 0
        return indexInCourse == maxIndex
    }
}
