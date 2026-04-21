import SwiftUI

enum Route: Hashable {
    case sessionSetup
    case roleSelection
    case startLine
    case checkpointCapture
    case finishLine
    case liveResults
    case reviewAndCorrect
    case export
}

struct AppNavigation: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            SessionSetupView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .sessionSetup:
                        SessionSetupView(path: $path)
                    case .roleSelection:
                        RoleSelectionView(path: $path)
                    case .startLine:
                        StartLineView()
                    case .checkpointCapture:
                        CheckpointCaptureView()
                    case .finishLine:
                        FinishLineView()
                    case .liveResults:
                        LiveResultsView()
                    case .reviewAndCorrect:
                        ReviewAndCorrectView()
                    case .export:
                        ExportView()
                    }
                }
        }
    }
}
