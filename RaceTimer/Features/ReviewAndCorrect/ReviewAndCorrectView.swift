import SwiftUI

struct ReviewAndCorrectView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "pencil.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.purple)

            Text("Review & Correct")
                .font(.title.bold())

            Text("Reorder, reassign, or delete checkpoint events.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Review & Correct")
    }
}
