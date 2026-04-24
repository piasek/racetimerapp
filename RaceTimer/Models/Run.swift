import Foundation
import SwiftData

enum RunStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case started
    case finished
    case incomplete
    case dnf
    case dns
}

@Model
final class Run {
    @Attribute(.unique) var id: UUID
    var statusRaw: String

    var session: Session?
    var rider: Rider?

    @Relationship(deleteRule: .cascade, inverse: \CheckpointEvent.run)
    var events: [CheckpointEvent]

    var status: RunStatus {
        get { RunStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), status: RunStatus = .scheduled) {
        self.id = id
        self.statusRaw = status.rawValue
        self.events = []
    }

    /// Non-deleted, non-ignored events sorted by checkpoint index.
    var effectiveEvents: [CheckpointEvent] {
        events
            .filter { !$0.isTombstoned && !$0.ignored }
            .sorted { ($0.checkpoint?.indexInCourse ?? 0) < ($1.checkpoint?.indexInCourse ?? 0) }
    }

    /// Start timestamp (event at checkpoint index 0), if present.
    var startTime: Date? {
        effectiveEvents.first { $0.checkpoint?.isStart == true }?.timestamp
    }

    /// Finish timestamp (event at the last checkpoint), if present.
    var finishTime: Date? {
        effectiveEvents.first { $0.checkpoint?.isFinish == true }?.timestamp
    }

    /// Total elapsed time from start to finish.
    var totalTime: TimeInterval? {
        guard let start = startTime, let finish = finishTime else { return nil }
        return finish.timeIntervalSince(start)
    }

    /// Split times between consecutive checkpoints.
    var splits: [SplitTime] {
        let sorted = effectiveEvents
        guard sorted.count >= 2 else { return [] }
        return zip(sorted, sorted.dropFirst()).compactMap { prev, curr in
            guard let prevCp = prev.checkpoint, let currCp = curr.checkpoint else { return nil }
            return SplitTime(
                fromCheckpoint: prevCp.name,
                toCheckpoint: currCp.name,
                elapsed: curr.timestamp.timeIntervalSince(prev.timestamp)
            )
        }
    }
}

struct SplitTime: Sendable {
    let fromCheckpoint: String
    let toCheckpoint: String
    let elapsed: TimeInterval
}
