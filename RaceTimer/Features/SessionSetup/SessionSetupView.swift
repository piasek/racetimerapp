import SwiftUI

struct SessionSetupView: View {
    @Binding var path: NavigationPath

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "timer")
                .font(.system(size: 64))
                .foregroundStyle(.tint)

            Text("RaceTimer")
                .font(.largeTitle.bold())

            Text("Create or select a session to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                path.append(Route.roleSelection)
            } label: {
                Label("New Session", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding()
        .navigationTitle("Sessions")
    }
}
