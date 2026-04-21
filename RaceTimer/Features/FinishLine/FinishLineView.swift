import SwiftUI
import SwiftData

/// Finish line is a specialised checkpoint capture at the last checkpoint.
struct FinishLineView: View {
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(RoleCoordinator.self) private var roleCoordinator

    @State private var session: Session?
    @State private var finishCheckpoint: Checkpoint?
    @State private var recentFinishes: [FinishRecord] = []
    @State private var expectedRiders: [Rider] = []

    var body: some View {
        VStack(spacing: 0) {
            // Expected
            VStack(alignment: .leading, spacing: 6) {
                Text("Expected Next")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                if expectedRiders.isEmpty {
                    Text("No riders en route")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expectedRiders.prefix(3)) { rider in
                        HStack {
                            if rider.id == expectedRiders.first?.id {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            Text(rider.displayName)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // Recent finishes
            List {
                Section("Finished (\(recentFinishes.count))") {
                    ForEach(recentFinishes) { record in
                        HStack {
                            Text(record.riderName)
                            Spacer()
                            if let total = record.totalTime {
                                Text(formattedTime(total))
                                    .font(.body.monospacedDigit().bold())
                            }
                            Text(record.timestamp, style: .time)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deleteFinish)
                }
            }

            // Big finish button
            CaptureButton(title: "Rider Finished", color: .red) {
                recordFinish()
            }
        }
        .navigationTitle("Finish Line")
        .onAppear { loadData() }
    }

    // MARK: - Actions

    private func recordFinish() {
        guard let session, let cp = finishCheckpoint else { return }
        let timestamp = Date.now
        let expectedRider = expectedRiders.first
        let run = session.runs.first { $0.rider?.id == expectedRider?.id && $0.status == .started }

        let event = CheckpointEvent(
            timestamp: timestamp,
            recordedByDeviceId: roleCoordinator.deviceId,
            autoAssignedRiderId: expectedRider?.id
        )
        event.run = run
        event.checkpoint = cp
        modelContext.insert(event)

        if let run {
            run.status = .finished
        }

        let record = FinishRecord(
            id: event.id,
            riderName: expectedRider?.displayName ?? "Unknown",
            timestamp: timestamp,
            totalTime: run?.totalTime
        )
        recentFinishes.insert(record, at: 0)
        rebuildExpected()
    }

    private func deleteFinish(at offsets: IndexSet) {
        for index in offsets {
            let record = recentFinishes[index]
            let eid = record.id
            if let event = try? modelContext.fetchByID(CheckpointEvent.self, id: eid) {
                event.deleted = true
            }
        }
        recentFinishes.remove(atOffsets: offsets)
        rebuildExpected()
    }

    // MARK: - Data

    private func loadData() {
        session = try? modelContext.fetchByID(Session.self, id: sessionId)
        finishCheckpoint = session?.sortedCheckpoints.last { $0.isFinish }
        rebuildExpected()
    }

    private func rebuildExpected() {
        guard let session else { expectedRiders = []; return }
        let finishedRiderIds = Set(
            session.runs.filter { $0.status == .finished }.compactMap { $0.rider?.id }
        )
        expectedRiders = session.runs
            .filter { $0.status == .started }
            .compactMap { $0.rider }
            .filter { !finishedRiderIds.contains($0.id) }
            .sorted { ($0.runs.first?.startTime ?? .distantFuture) < ($1.runs.first?.startTime ?? .distantFuture) }
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        let ms = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}

private struct FinishRecord: Identifiable {
    let id: UUID
    let riderName: String
    let timestamp: Date
    let totalTime: TimeInterval?
}
