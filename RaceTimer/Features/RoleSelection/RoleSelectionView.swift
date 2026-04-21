import SwiftUI

struct RoleSelectionView: View {
    @Binding var path: NavigationPath

    var body: some View {
        List {
            Section("Select Your Role") {
                roleButton(label: "Start Official", icon: "flag.fill", route: .startLine)
                roleButton(label: "Checkpoint Official", icon: "mappin.circle.fill", route: .checkpointCapture)
                roleButton(label: "Finish Official", icon: "flag.checkered", route: .finishLine)
            }

            Section("Views") {
                roleButton(label: "Live Results", icon: "chart.bar.fill", route: .liveResults)
                roleButton(label: "Review & Correct", icon: "pencil.circle.fill", route: .reviewAndCorrect)
                roleButton(label: "Export", icon: "square.and.arrow.up.fill", route: .export)
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
