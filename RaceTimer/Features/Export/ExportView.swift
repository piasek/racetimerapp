import SwiftUI

struct ExportView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "square.and.arrow.up.fill")
                .font(.system(size: 64))
                .foregroundStyle(.teal)

            Text("Export")
                .font(.title.bold())

            Text("Generate CSV, PDF, or email results.")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("Export")
    }
}
