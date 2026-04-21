import Foundation
import SwiftData

@Model
final class Session {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: Date
    var courseName: String
    var notes: String

    @Relationship(deleteRule: .cascade, inverse: \Checkpoint.session)
    var checkpoints: [Checkpoint]

    @Relationship(deleteRule: .cascade, inverse: \Rider.session)
    var riders: [Rider]

    @Relationship(deleteRule: .cascade, inverse: \Run.session)
    var runs: [Run]

    init(
        id: UUID = UUID(),
        name: String,
        date: Date = .now,
        courseName: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.courseName = courseName
        self.notes = notes
        self.checkpoints = []
        self.riders = []
        self.runs = []
    }

    /// Checkpoints sorted by course index (0 = start, last = finish).
    var sortedCheckpoints: [Checkpoint] {
        checkpoints.sorted { $0.indexInCourse < $1.indexInCourse }
    }
}
