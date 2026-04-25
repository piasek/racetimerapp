#if DEBUG
import Foundation
import SwiftUI
import SwiftData

/// Helpers for SwiftUI previews. Builds an in-memory ModelContainer plus the
/// RoleCoordinator/SyncCoordinator environment objects every feature view
/// expects, and seeds a small but realistic race scenario.
///
/// Usage in a view file:
/// ```swift
/// #Preview {
///     let s = PreviewSupport.makeScenario()
///     return MyView(sessionId: s.sessionId).previewEnvironment(s)
/// }
/// ```
@MainActor
enum PreviewSupport {
    struct Scenario {
        let container: ModelContainer
        let role: RoleCoordinator
        let sync: SyncCoordinator
        let session: Session
        let startCheckpoint: Checkpoint
        let intermediateCheckpoint: Checkpoint
        let finishCheckpoint: Checkpoint
        let riders: [Rider]
        let runs: [Run]

        var sessionId: UUID { session.id }
        var startCheckpointId: UUID { startCheckpoint.id }
        var intermediateCheckpointId: UUID { intermediateCheckpoint.id }
        var finishCheckpointId: UUID { finishCheckpoint.id }
    }

    /// Build an in-memory scenario.
    /// - Parameters:
    ///   - riderCount: total riders to seed
    ///   - startedCount: of those, how many have a Start event recorded
    ///   - finishedCount: of those, how many have a Finish event recorded
    ///   - role: the role this preview device should act as
    static func makeScenario(
        riderCount: Int = 6,
        startedCount: Int = 4,
        finishedCount: Int = 2,
        role: DeviceRole = .observer
    ) -> Scenario {
        precondition(finishedCount <= startedCount && startedCount <= riderCount)

        let schema = Schema([
            Session.self, Checkpoint.self, Rider.self, Run.self,
            CheckpointEvent.self, DeviceInfo.self, SyncEvent.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Preview container failed: \(error)")
        }
        let context = container.mainContext

        let session = Session(name: "Preview Race", date: Date())
        context.insert(session)

        let start = Checkpoint(indexInCourse: 0, name: "Start")
        let intermediate = Checkpoint(
            indexInCourse: 1,
            name: "Checkpoint - Preview",
            createdByDeviceId: "preview-device"
        )
        let finish = Checkpoint(indexInCourse: 2, name: "Finish")
        for cp in [start, intermediate, finish] {
            cp.session = session
            context.insert(cp)
        }

        let firstNames = ["Alex", "Bea", "Cory", "Dani", "Eli", "Fran", "Gus", "Hana", "Ivy", "Jules"]
        var riders: [Rider] = []
        var runs: [Run] = []
        let baseStart = Date().addingTimeInterval(-600)
        for i in 0..<riderCount {
            let rider = Rider(
                firstName: firstNames[i % firstNames.count],
                bibNumber: i + 1
            )
            rider.session = session
            context.insert(rider)
            riders.append(rider)

            let run = Run(status: .scheduled)
            run.rider = rider
            run.session = session
            context.insert(run)
            runs.append(run)

            if i < startedCount {
                run.status = .started
                let startEvent = CheckpointEvent(
                    timestamp: baseStart.addingTimeInterval(Double(i) * 30),
                    recordedByDeviceId: "preview-start",
                    autoAssignedRiderId: rider.id
                )
                startEvent.run = run
                startEvent.checkpoint = start
                context.insert(startEvent)
            }
            if i < finishedCount {
                run.status = .finished
                let finishEvent = CheckpointEvent(
                    timestamp: baseStart.addingTimeInterval(Double(i) * 30 + 180),
                    recordedByDeviceId: "preview-finish",
                    autoAssignedRiderId: rider.id
                )
                finishEvent.run = run
                finishEvent.checkpoint = finish
                context.insert(finishEvent)
            }
        }

        try? context.save()

        let roleCoord = RoleCoordinator()
        roleCoord.assignRole(role, checkpointId: intermediate.id, sessionId: session.id)
        let syncCoord = SyncCoordinator(modelContext: context, deviceId: roleCoord.deviceId)

        return Scenario(
            container: container,
            role: roleCoord,
            sync: syncCoord,
            session: session,
            startCheckpoint: start,
            intermediateCheckpoint: intermediate,
            finishCheckpoint: finish,
            riders: riders,
            runs: runs
        )
    }
}

extension View {
    /// Inject the model container + RoleCoordinator + SyncCoordinator
    /// produced by `PreviewSupport.makeScenario()`.
    @MainActor
    func previewEnvironment(_ scenario: PreviewSupport.Scenario) -> some View {
        self
            .modelContainer(scenario.container)
            .environment(scenario.role)
            .environment(scenario.sync)
    }
}
#endif
