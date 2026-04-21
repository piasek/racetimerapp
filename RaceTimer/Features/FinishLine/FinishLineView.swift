import SwiftUI

struct FinishLineView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "flag.checkered")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Finish Line")
                .font(.title.bold())

            Text("Tap when a rider finishes.")
                .foregroundStyle(.secondary)

            Button {
                // TODO: Record finish action
            } label: {
                Text("Rider Finished")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.red)

            Spacer()
        }
        .padding()
        .navigationTitle("Finish Line")
    }
}
