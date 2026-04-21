import SwiftUI
import SwiftData

@main
struct RaceTimerApp: App {
    let modelContainer: ModelContainer

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
        do {
            modelContainer = try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppNavigation()
        }
        .modelContainer(modelContainer)
    }
}
