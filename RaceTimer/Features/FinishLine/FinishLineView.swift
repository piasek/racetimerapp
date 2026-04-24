import SwiftUI
import SwiftData

/// Finish line is a specialised checkpoint capture at the last checkpoint.
struct FinishLineView: View {
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(RoleCoordinator.self) private var roleCoordinator
    @Environment(SyncCoordinator.self) private var syncCoordinator

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

        let eventId = UUID()
        var payloads: [SyncPayload] = [
            .checkpointEventRecorded(CheckpointEventPayload(
                eventId: eventId,
                runId: run?.id,
                checkpointId: cp.id,
                timestamp: timestamp,
                recordedByDeviceId: roleCoordinator.deviceId,
                autoAssignedRiderId: expectedRider?.id
            ))
        ]
        if let run {
            payloads.append(.runStatusChanged(RunStatusPayload(
                runId: run.id,
                status: RunStatus.finished.rawValue
            )))
        }
        syncCoordinator.apply(payloads)

        let record = FinishRecord(
            id: eventId,
            riderName: expectedRider?.displayName ?? "Unknown",
            timestamp: timestamp,
            totalTime: run?.totalTime
        )
        recentFinishes.insert(record, at: 0)
        rebuildExpected()
    }

    private func deleteFinish(at offsets: IndexSet) {
        guard let session, let cp = finishCheckpoint else { return }

        // All non-deleted finish events for this session at the finish
        // checkpoint, sorted by capture time. This is the canonical sequence
        // we shift over when an accidental tap is removed.
        var orderedEvents = session.runs
            .flatMap(\.events)
            .filter { $0.checkpoint?.id == cp.id && !$0.isTombstoned }
            .sorted { $0.timestamp < $1.timestamp }

        var payloads: [SyncPayload] = []

        for offset in offsets {
            let record = recentFinishes[offset]
            guard let idx = orderedEvents.firstIndex(where: { $0.id == record.id }) else { continue }

            // Snapshot the run-id chain before the shift so we can compute
            // which runs are no longer assigned to any finish event.
            let preRunIds = Set(orderedEvents.compactMap { $0.run?.id })

            // Tombstone the deleted (accidental) event.
            payloads.append(.checkpointEventEdited(CheckpointEventEditPayload(
                eventId: orderedEvents[idx].id,
                reassignedRunId: nil,
                deleted: true,
                ignored: nil,
                manualOverride: nil,
                note: nil
            )))

            // Each later event slides up by one rider in the original chain.
            // The rider who was previously last loses their finish (handled
            // below via the run-id set diff).
            for j in (idx + 1)..<orderedEvents.count {
                if let prevRunId = orderedEvents[j - 1].run?.id {
                    payloads.append(.checkpointEventEdited(CheckpointEventEditPayload(
                        eventId: orderedEvents[j].id,
                        reassignedRunId: prevRunId,
                        deleted: nil,
                        ignored: nil,
                        manualOverride: nil,
                        note: nil
                    )))
                }
            }

            // Compute the post-shift chain to find which run no longer has
            // a finish event and revert its status to .started.
            var postRunIds: Set<UUID> = []
            for (i, e) in orderedEvents.enumerated() where i != idx {
                let assigned = i < idx ? e.run?.id : orderedEvents[i - 1].run?.id
                if let assigned { postRunIds.insert(assigned) }
            }
            for runId in preRunIds.subtracting(postRunIds) {
                payloads.append(.runStatusChanged(RunStatusPayload(
                    runId: runId,
                    status: RunStatus.started.rawValue
                )))
            }

            orderedEvents.remove(at: idx)
        }

        syncCoordinator.apply(payloads)
        rebuildRecentFinishes()
        rebuildExpected()
    }

    /// Re-derive `recentFinishes` from the current model state. Called after
    /// any edit so the visible rider names reflect post-shift assignments.
    private func rebuildRecentFinishes() {
        guard let session, let cp = finishCheckpoint else { recentFinishes = []; return }
        let events = session.runs
            .flatMap(\.events)
            .filter { $0.checkpoint?.id == cp.id && !$0.isTombstoned }
            .sorted { $0.timestamp > $1.timestamp }

        recentFinishes = events.map { event in
            FinishRecord(
                id: event.id,
                riderName: event.run?.rider?.displayName ?? "Unknown",
                timestamp: event.timestamp,
                totalTime: event.run?.totalTime
            )
        }
    }

    // MARK: - Data

    private func loadData() {
        session = try? modelContext.fetchByID(Session.self, id: sessionId)
        finishCheckpoint = session?.sortedCheckpoints.last { $0.isFinish }
        rebuildRecentFinishes()
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
