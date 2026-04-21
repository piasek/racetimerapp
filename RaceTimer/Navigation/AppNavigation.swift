import SwiftUI

enum Route: Hashable {
    case sessionSetup
    case sessionDetail(UUID)
    case roleSelection(UUID)
    case startLine(UUID)
    case checkpointCapture(UUID, checkpointId: UUID)
    case finishLine(UUID)
    case liveResults(UUID)
    case reviewAndCorrect(UUID)
    case export(UUID)
}

struct AppNavigation: View {
    @State private var path = NavigationPath()
    @State private var roleCoordinator = RoleCoordinator()

    var body: some View {
        NavigationStack(path: $path) {
            SessionSetupView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .sessionSetup:
                        SessionSetupView(path: $path)
                    case .sessionDetail(let id):
                        SessionDetailView(path: $path, sessionId: id)
                    case .roleSelection(let id):
                        RoleSelectionView(path: $path, sessionId: id)
                    case .startLine(let id):
                        StartLineView(sessionId: id)
                    case .checkpointCapture(let sid, let cpId):
                        CheckpointCaptureView(sessionId: sid, checkpointId: cpId)
                    case .finishLine(let id):
                        FinishLineView(sessionId: id)
                    case .liveResults(let id):
                        LiveResultsView(sessionId: id)
                    case .reviewAndCorrect(let id):
                        ReviewAndCorrectView(sessionId: id)
                    case .export(let id):
                        ExportView(sessionId: id)
                    }
                }
        }
        .environment(roleCoordinator)
    }
}
