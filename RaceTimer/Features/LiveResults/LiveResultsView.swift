import SwiftUI
import SwiftData

struct LiveResultsView: View {
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var session: Session?
    @State private var results: [ResultRow] = []
    @State private var refreshTimer: Timer?

    var body: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView(
                    "No Results Yet",
                    systemImage: "chart.bar",
                    description: Text("Results will appear as riders finish.")
                )
            }

            ForEach(Array(results.enumerated()), id: \.element.id) { index, row in
                HStack {
                    Text("\(index + 1)")
                        .font(.headline.monospacedDigit())
                        .frame(width: 30, alignment: .trailing)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.riderName)
                            .font(.body)
                        if !row.splits.isEmpty {
                            Text(row.splits.map { formattedTime($0) }.joined(separator: " · "))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        if let total = row.totalTime {
                            Text(formattedTime(total))
                                .font(.body.monospacedDigit().bold())
                        }
                        statusBadge(row.status)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Live Results")
        .onAppear {
            loadSession()
            startAutoRefresh()
        }
        .onDisappear { refreshTimer?.invalidate() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    refreshResults()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private func statusBadge(_ status: RunStatus) -> some View {
        let (text, color): (String, Color) = switch status {
        case .finished: ("FIN", .green)
        case .started: ("ON COURSE", .blue)
        case .dnf: ("DNF", .red)
        case .dns: ("DNS", .gray)
        case .incomplete: ("INC", .orange)
        case .scheduled: ("SCHED", .gray)
        }
        Text(text)
            .font(.caption2.bold())
            .foregroundStyle(color)
    }

    // MARK: - Data

    private func loadSession() {
        session = try? modelContext.fetchByID(Session.self, id: sessionId)
        refreshResults()
    }

    private func refreshResults() {
        guard let session else { return }
        results = session.runs.compactMap { run -> ResultRow? in
            guard let rider = run.rider else { return nil }
            return ResultRow(
                id: run.id,
                riderName: rider.displayName,
                status: run.status,
                totalTime: run.totalTime,
                splits: run.splits.map(\.elapsed)
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.totalTime, rhs.totalTime) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.riderName < rhs.riderName
            }
        }
    }

    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [self] _ in
            Task { @MainActor in
                self.refreshResults()
            }
        }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        let ms = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}

private struct ResultRow: Identifiable {
    let id: UUID
    let riderName: String
    let status: RunStatus
    let totalTime: TimeInterval?
    let splits: [TimeInterval]
}

#if DEBUG
#Preview {
    let scenario = PreviewSupport.makeScenario(riderCount: 6, startedCount: 6, finishedCount: 4)
    NavigationStack {
        LiveResultsView(sessionId: scenario.sessionId)
    }
    .previewEnvironment(scenario)
}
#endif
