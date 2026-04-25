import SwiftUI
import SwiftData

struct ExportView: View {
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var session: Session?
    @State private var csvText: String?
    @State private var showShareSheet = false

    var body: some View {
        List {
            if let session {
                Section("Session") {
                    LabeledContent("Name", value: session.name)
                    LabeledContent("Riders", value: "\(session.riders.count)")
                    LabeledContent("Runs", value: "\(session.runs.count)")
                }

                Section("Export Options") {
                    Button {
                        generateCSV()
                    } label: {
                        Label("Generate CSV", systemImage: "doc.text")
                    }
                }

                if let csvText {
                    Section("Preview") {
                        Text(csvText)
                            .font(.system(.caption, design: .monospaced))
                    }

                    Section {
                        ShareLink(item: csvText) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .navigationTitle("Export")
        .onAppear { loadSession() }
    }

    // MARK: - CSV generation

    private func generateCSV() {
        guard let session else { return }
        var lines: [String] = []

        // Header
        let cpNames = session.sortedCheckpoints.map(\.name)
        let header = ["Pos", "Rider", "Bib", "Category", "Status"]
            + cpNames.dropFirst().map { "Split: \($0)" }
            + ["Total"]
        lines.append(header.joined(separator: ","))

        // Rows sorted by total time
        let sorted = session.runs
            .sorted { ($0.totalTime ?? .infinity) < ($1.totalTime ?? .infinity) }

        for (pos, run) in sorted.enumerated() {
            let rider = run.rider
            var row: [String] = [
                "\(pos + 1)",
                escapeCSV(rider?.displayName ?? "Unknown"),
                rider?.bibNumber.map(String.init) ?? "",
                escapeCSV(rider?.category ?? ""),
                run.status.rawValue,
            ]
            for split in run.splits {
                row.append(formattedTime(split.elapsed))
            }
            // Pad if fewer splits
            let expectedSplits = max(cpNames.count - 1, 0)
            while row.count < 5 + expectedSplits {
                row.append("")
            }
            row.append(run.totalTime.map(formattedTime) ?? "")
            lines.append(row.joined(separator: ","))
        }

        csvText = lines.joined(separator: "\n")
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }

    private func loadSession() {
        session = try? modelContext.fetchByID(Session.self, id: sessionId)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        let ms = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}

#if DEBUG
#Preview {
    let scenario = PreviewSupport.makeScenario(riderCount: 6, startedCount: 6, finishedCount: 6)
    NavigationStack {
        ExportView(sessionId: scenario.sessionId)
    }
    .previewEnvironment(scenario)
}
#endif
