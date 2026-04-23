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
    @Environment(RoleCoordinator.self) private var roleCoordinator
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.scenePhase) private var scenePhase

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
        .syncStatusBar()
        .onAppear(perform: startSyncIfPossible)
        .onChange(of: roleCoordinator.activeSessionId) { _, _ in startSyncIfPossible() }
        .onChange(of: roleCoordinator.currentRole) { _, _ in startSyncIfPossible() }
        .onChange(of: scenePhase) { _, phase in
            // Safety net: when returning to foreground, kick the MC stack so we
            // recover from any network transitions that happened while backgrounded.
            if phase == .active, syncCoordinator.isStarted {
                syncCoordinator.peerSync.restart()
            }
        }
    }

    /// Start the MC transport as soon as the app is up so users can see
    /// nearby devices from the Sessions screen (and diagnose connectivity).
    /// PeerSyncService.start is idempotent — first call advertises+browses;
    /// later calls are no-ops. Session-scoped invite filtering is tracked
    /// separately (see deferred todo `session-scoped-invites`).
    private func startSyncIfPossible() {
        syncCoordinator.start(
            role: roleCoordinator.currentRole.rawValue,
            activeSessionId: roleCoordinator.activeSessionId
        )
    }
}
