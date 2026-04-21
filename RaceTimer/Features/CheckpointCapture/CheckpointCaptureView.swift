import SwiftUI
import SwiftData

struct CheckpointCaptureView: View {
    let sessionId: UUID
    let checkpointId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(RoleCoordinator.self) private var roleCoordinator

    @State private var session: Session?
    @State private var checkpoint: Checkpoint?
    @State private var recentCaptures: [CaptureRecord] = []
    @State private var expectedRiders: [Rider] = []
    @State private var showOverrideSheet = false
    @State private var overrideTarget: CaptureRecord?

    var body: some View {
        VStack(spacing: 0) {
            // Expected riders panel
            expectedPanel

            Divider()

            // Recent captures
            List {
                Section("Recent Captures") {
                    if recentCaptures.isEmpty {
                        Text("No captures yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(recentCaptures) { capture in
                        captureRow(capture)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    markDeleted(capture)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }

            // Big capture button
            Button {
                capturePass()
            } label: {
                Text("Rider Passed")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .padding()
        }
        .navigationTitle(checkpoint?.name ?? "Checkpoint")
        .onAppear { loadData() }
        .sheet(isPresented: $showOverrideSheet) {
            overrideSheet
        }
    }

    // MARK: - Expected riders

    private var expectedPanel: some View {
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
                                .foregroundStyle(.orange)
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
    }

    // MARK: - Capture

    private func capturePass() {
        guard let session, let checkpoint else { return }
        let timestamp = Date.now
        let expectedRider = expectedRiders.first
        let run = findOrCreateRun(for: expectedRider, in: session)

        let event = CheckpointEvent(
            timestamp: timestamp,
            recordedByDeviceId: roleCoordinator.deviceId,
            autoAssignedRiderId: expectedRider?.id
        )
        event.run = run
        event.checkpoint = checkpoint
        modelContext.insert(event)

        let record = CaptureRecord(
            id: event.id,
            riderName: expectedRider?.displayName ?? "Unknown",
            timestamp: timestamp,
            eventId: event.id
        )
        recentCaptures.insert(record, at: 0)
        rebuildExpected()
    }

    private func findOrCreateRun(for rider: Rider?, in session: Session) -> Run? {
        if let rider {
            // Find an active run for this rider
            return session.runs.first { $0.rider?.id == rider.id && $0.status == .started }
        }
        return nil
    }

    // MARK: - Override

    @ViewBuilder
    private var overrideSheet: some View {
        NavigationStack {
            List {
                if let session {
                    ForEach(session.riders) { rider in
                        Button {
                            reassignCapture(to: rider)
                        } label: {
                            Text(rider.displayName)
                        }
                    }
                }
            }
            .navigationTitle("Reassign Rider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showOverrideSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func reassignCapture(to rider: Rider) {
        guard let target = overrideTarget, let session else { return }
        let eventId = target.eventId
        let descriptor = FetchDescriptor<CheckpointEvent>(predicate: #Predicate { $0.id == eventId })
        guard let event = try? modelContext.fetch(descriptor).first else { return }

        let newRun = session.runs.first { $0.rider?.id == rider.id && $0.status == .started }
        event.run = newRun
        event.manualOverride = true

        if let idx = recentCaptures.firstIndex(where: { $0.id == target.id }) {
            recentCaptures[idx] = CaptureRecord(
                id: target.id,
                riderName: rider.displayName,
                timestamp: target.timestamp,
                eventId: target.eventId
            )
        }
        showOverrideSheet = false
    }

    private func markDeleted(_ capture: CaptureRecord) {
        let eventId = capture.eventId
        let descriptor = FetchDescriptor<CheckpointEvent>(predicate: #Predicate { $0.id == eventId })
        if let event = try? modelContext.fetch(descriptor).first {
            event.deleted = true
        }
        recentCaptures.removeAll { $0.id == capture.id }
        rebuildExpected()
    }

    // MARK: - Capture row

    private func captureRow(_ capture: CaptureRecord) -> some View {
        Button {
            overrideTarget = capture
            showOverrideSheet = true
        } label: {
            HStack {
                Text(capture.riderName)
                Spacer()
                Text(capture.timestamp, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data loading

    private func loadData() {
        let sid = sessionId
        let cid = checkpointId
        let sd = FetchDescriptor<Session>(predicate: #Predicate { $0.id == sid })
        session = try? modelContext.fetch(sd).first
        let cd = FetchDescriptor<Checkpoint>(predicate: #Predicate { $0.id == cid })
        checkpoint = try? modelContext.fetch(cd).first
        rebuildExpected()
    }

    private func rebuildExpected() {
        guard let session, let checkpoint else { expectedRiders = []; return }
        let cpId = checkpoint.id
        // Riders with started runs who haven't passed this checkpoint yet
        let startedRuns = session.runs.filter { $0.status == .started }
        let ridersAlreadyPassed = Set(
            startedRuns.flatMap { $0.effectiveEvents }
                .filter { $0.checkpoint?.id == cpId }
                .compactMap { $0.run?.rider?.id }
        )
        expectedRiders = startedRuns
            .compactMap { $0.rider }
            .filter { !ridersAlreadyPassed.contains($0.id) }
            .sorted { ($0.runs.first?.startTime ?? .distantFuture) < ($1.runs.first?.startTime ?? .distantFuture) }
    }
}

struct CaptureRecord: Identifiable {
    let id: UUID
    let riderName: String
    let timestamp: Date
    let eventId: UUID
}
