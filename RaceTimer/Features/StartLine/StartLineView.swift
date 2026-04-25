import SwiftUI
import SwiftData

struct StartLineView: View {
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(RoleCoordinator.self) private var roleCoordinator
    @Environment(SyncCoordinator.self) private var syncCoordinator

    @State private var session: Session?
    @State private var riderQueue: [Rider] = []
    @State private var lastSendTime: Date?
    @State private var elapsedSinceLastSend: TimeInterval = 0
    @State private var timer: Timer?

    private let minimumGap: TimeInterval = 30

    var body: some View {
        VStack(spacing: 0) {
            // Interval-since-last-start banner
            if lastSendTime != nil {
                gapBanner
            }

            List {
                Section("Next Up") {
                    if riderQueue.isEmpty {
                        Text("All riders have been sent.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(riderQueue) { rider in
                        HStack {
                            Text(rider.displayName)
                            Spacer()
                            if rider.id == riderQueue.first?.id {
                                Text("NEXT")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(.green, in: Capsule())
                            }
                        }
                    }
                }

                if let session {
                    Section("Sent (\(sentRuns(session).count))") {
                        ForEach(sentRuns(session), id: \.id) { run in
                            if let rider = run.rider {
                                HStack {
                                    Text(rider.displayName)
                                    Spacer()
                                    if let start = run.startTime {
                                        Text(start, style: .time)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Big send button
            CaptureButton(title: "Send Rider", color: .green) {
                sendNextRider()
            }
            .disabled(riderQueue.isEmpty)
        }
        .navigationTitle("Start Line")
        .onAppear { loadSession() }
        .onDisappear { timer?.invalidate() }
    }

    // MARK: - Gap banner

    private var gapBanner: some View {
        HStack {
            Image(systemName: elapsedSinceLastSend < minimumGap ? "exclamationmark.triangle.fill" : "clock")
                .foregroundStyle(elapsedSinceLastSend < minimumGap ? .yellow : .green)
            Text("Since last: \(formattedInterval(elapsedSinceLastSend))")
                .monospacedDigit()
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(elapsedSinceLastSend < minimumGap ? Color.yellow.opacity(0.15) : Color.green.opacity(0.10))
    }

    // MARK: - Actions

    private func sendNextRider() {
        guard let session, let rider = riderQueue.first else { return }
        let startCheckpoint = session.sortedCheckpoints.first { $0.isStart }
        guard let cp = startCheckpoint else { return }

        let runId = UUID()
        let eventId = UUID()

        syncCoordinator.apply([
            .runCreated(RunPayload(
                runId: runId,
                sessionId: session.id,
                riderId: rider.id,
                status: RunStatus.started.rawValue
            )),
            .checkpointEventRecorded(CheckpointEventPayload(
                eventId: eventId,
                runId: runId,
                checkpointId: cp.id,
                timestamp: .now,
                recordedByDeviceId: roleCoordinator.deviceId,
                autoAssignedRiderId: rider.id
            )),
        ])

        lastSendTime = .now
        startGapTimer()
        rebuildQueue()
    }

    private func startGapTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
            Task { @MainActor in
                if let last = self.lastSendTime {
                    self.elapsedSinceLastSend = Date.now.timeIntervalSince(last)
                }
            }
        }
    }

    // MARK: - Data

    private func loadSession() {
        session = try? modelContext.fetchByID(Session.self, id: sessionId)
        rebuildQueue()
    }

    private func rebuildQueue() {
        guard let session else { riderQueue = []; return }
        let sentRiderIds = Set(session.runs.compactMap { $0.rider?.id })
        riderQueue = session.riders.filter { !sentRiderIds.contains($0.id) }
    }

    private func sentRuns(_ session: Session) -> [Run] {
        session.runs
            .filter { $0.status == .started || $0.status == .finished }
            .sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
    }

    private func formattedInterval(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#if DEBUG
#Preview {
    let scenario = PreviewSupport.makeScenario(riderCount: 6, startedCount: 2, finishedCount: 0, role: .start)
    NavigationStack {
        StartLineView(sessionId: scenario.sessionId)
    }
    .previewEnvironment(scenario)
}
#endif
