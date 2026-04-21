import SwiftUI

struct CheckpointCaptureView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.orange)

            Text("Checkpoint")
                .font(.title.bold())

            Text("Tap when a rider passes.")
                .foregroundStyle(.secondary)

            Button {
                // TODO: Record pass action
            } label: {
                Text("Rider Passed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.orange)

            Spacer()
        }
        .padding()
        .navigationTitle("Checkpoint")
    }
}
