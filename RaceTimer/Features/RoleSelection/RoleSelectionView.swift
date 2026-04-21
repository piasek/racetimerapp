import SwiftUI

struct RoleSelectionView: View {
    @Binding var path: NavigationPath
    let sessionId: UUID

    var body: some View {
        List {
            Section("Select Your Role") {
                roleButton(label: "Start Official", icon: "flag.fill", route: .startLine(sessionId))
                roleButton(label: "Checkpoint Official", icon: "mappin.circle.fill", route: .checkpointCapture(sessionId))
                roleButton(label: "Finish Official", icon: "flag.checkered", route: .finishLine(sessionId))
            }

            Section("Views") {
                roleButton(label: "Live Results", icon: "chart.bar.fill", route: .liveResults(sessionId))
                roleButton(label: "Review & Correct", icon: "pencil.circle.fill", route: .reviewAndCorrect(sessionId))
                roleButton(label: "Export", icon: "square.and.arrow.up.fill", route: .export(sessionId))
            }
        }
        .navigationTitle("Role")
    }

    private func roleButton(label: String, icon: String, route: Route) -> some View {
        Button {
            path.append(route)
        } label: {
            Label(label, systemImage: icon)
        }
    }
}
