import SwiftUI

struct StartLineView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "flag.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Start Line")
                .font(.title.bold())

            Text("Queue riders and send them off.")
                .foregroundStyle(.secondary)

            Button {
                // TODO: Send rider action
            } label: {
                Text("Send Rider")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.green)

            Spacer()
        }
        .padding()
        .navigationTitle("Start Line")
    }
}
