import Foundation
import SwiftData

/// Read-only helpers over SwiftData for derived race results.
///
/// All domain **mutations** go through `SyncCoordinator.apply(_:)` so that
/// every change is appended to the event log and broadcast to peers.
/// This type intentionally exposes no mutating operations.
@MainActor
final class SessionStore: ObservableObject {
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = modelContainer.mainContext
    }

    func fetchSessions() throws -> [Session] {
        let descriptor = FetchDescriptor<Session>()
        return try modelContext.fetch(descriptor).sorted { $0.date > $1.date }
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
}

struct RunResult: Sendable {
    let runId: UUID
    let riderName: String
    let bibNumber: Int?
    let status: RunStatus
    let splits: [SplitTime]
    let totalTime: TimeInterval?
}
