import SwiftUI

struct LiveResultsView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "chart.bar.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Live Results")
                .font(.title.bold())

            Text("Running list of riders, splits, and status.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Live Results")
    }
}
