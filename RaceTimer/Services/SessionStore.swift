import Foundation
import SwiftData

/// Wraps SwiftData ModelContext for session CRUD and derived results.
@MainActor
final class SessionStore: ObservableObject {
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
    }

    // MARK: - Session CRUD

    func createSession(name: String, courseName: String = "", notes: String = "") -> Session {
        let session = Session(name: name, courseName: courseName, notes: notes)
        modelContext.insert(session)
        return session
    }

    func fetchSessions() throws -> [Session] {
        let descriptor = FetchDescriptor<Session>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return try modelContext.fetch(descriptor)
    }

    func deleteSession(_ session: Session) {
        modelContext.delete(session)
    }

    // MARK: - Checkpoint management

    func addCheckpoint(to session: Session, name: String) -> Checkpoint {
        let nextIndex = session.checkpoints.count
        let checkpoint = Checkpoint(indexInCourse: nextIndex, name: name)
        checkpoint.session = session
        modelContext.insert(checkpoint)
        return checkpoint
    }

    // MARK: - Rider management

    func addRider(
        to session: Session,
        firstName: String,
        lastName: String? = nil,
        bibNumber: Int? = nil,
        category: String? = nil
    ) -> Rider {
        let rider = Rider(
            firstName: firstName,
            lastName: lastName,
            bibNumber: bibNumber,
            category: category
        )
        rider.session = session
        modelContext.insert(rider)
        return rider
    }

    // MARK: - Run management

    func createRun(in session: Session, for rider: Rider) -> Run {
        let run = Run(status: .scheduled)
        run.rider = rider
        run.session = session
        modelContext.insert(run)
        return run
    }

    func recordCheckpointEvent(
        for run: Run,
        at checkpoint: Checkpoint,
        timestamp: Date = .now,
        recordedByDeviceId: String,
        autoAssignedRiderId: UUID? = nil
    ) -> CheckpointEvent {
        let event = CheckpointEvent(
            timestamp: timestamp,
            recordedByDeviceId: recordedByDeviceId,
            autoAssignedRiderId: autoAssignedRiderId
        )
        event.run = run
        event.checkpoint = checkpoint
        modelContext.insert(event)
        return event
    }

    // MARK: - Derived results

    /// Compute results for all runs in a session, sorted by total time.
    func results(for session: Session) -> [RunResult] {
        session.runs
            .compactMap { run -> RunResult? in
                guard let rider = run.rider else { return nil }
                return RunResult(
                    runId: run.id,
                    riderName: rider.displayName,
                    bibNumber: rider.bibNumber,
                    status: run.status,
                    splits: run.splits,
                    totalTime: run.totalTime
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.totalTime, rhs.totalTime) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.riderName < rhs.riderName
                }
            }
    }

    func save() throws {
        try modelContext.save()
    }
}

struct RunResult: Sendable {
    let runId: UUID
    let riderName: String
    let bibNumber: Int?
    let status: RunStatus
    let splits: [SplitTime]
    let totalTime: TimeInterval?
}
