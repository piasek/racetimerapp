import SwiftUI
import SwiftData

@main
struct RaceTimerApp: App {
    let modelContainer: ModelContainer
    @State private var roleCoordinator: RoleCoordinator
    @State private var syncCoordinator: SyncCoordinator

    init() {
        let schema = Schema([
            Session.self,
            Checkpoint.self,
            Rider.self,
            Run.self,
            CheckpointEvent.self,
            DeviceInfo.self,
            SyncEvent.self,
        ])
        let config = ModelConfiguration(schema: schema)
        let container: ModelContainer
        do {
            container = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        self.modelContainer = container
        let role = RoleCoordinator()
        self._roleCoordinator = State(initialValue: role)
        self._syncCoordinator = State(
            initialValue: SyncCoordinator(
                modelContext: container.mainContext,
                deviceId: role.deviceId
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            AppNavigation()
                .environment(roleCoordinator)
                .environment(syncCoordinator)
        }
        .modelContainer(modelContainer)
    }
}
