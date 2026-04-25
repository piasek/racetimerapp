import SwiftUI
import SwiftData

struct ReviewAndCorrectView: View {
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var session: Session?
    @State private var selectedRun: Run?

    var body: some View {
        List {
            if let session {
                ForEach(session.runs.sorted(by: { ($0.startTime ?? .distantFuture) < ($1.startTime ?? .distantFuture) })) { run in
                    Button {
                        selectedRun = run
                    } label: {
                        runRow(run)
                    }
                }
            }
        }
        .navigationTitle("Review & Correct")
        .onAppear { loadSession() }
        .sheet(item: $selectedRun) { run in
            RunDetailSheet(run: run, session: session)
        }
    }

    private func runRow(_ run: Run) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(run.rider?.displayName ?? "Unknown")
                    .font(.body)
                Text("\(run.effectiveEvents.count) events")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPicker(run)
            if let total = run.totalTime {
                Text(formattedTime(total))
                    .font(.body.monospacedDigit())
            }
        }
    }

    private func statusPicker(_ run: Run) -> some View {
        Picker("Status", selection: Binding(
            get: { run.status },
            set: { run.status = $0 }
        )) {
            ForEach(RunStatus.allCases, id: \.self) { status in
                Text(status.rawValue).tag(status)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
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

// MARK: - Run detail sheet

private struct RunDetailSheet: View {
    let run: Run
    let session: Session?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Rider") {
                    Text(run.rider?.displayName ?? "Unknown")
                }

                Section("Checkpoint Events") {
                    ForEach(run.events.sorted(by: {
                        ($0.checkpoint?.indexInCourse ?? 0) < ($1.checkpoint?.indexInCourse ?? 0)
                    })) { event in
                        eventRow(event)
                    }
                }

                Section("Status") {
                    Picker("Status", selection: Binding(
                        get: { run.status },
                        set: { run.status = $0 }
                    )) {
                        ForEach(RunStatus.allCases, id: \.self) { status in
                            Text(status.rawValue).tag(status)
                        }
                    }
                }
            }
            .navigationTitle("Run Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func eventRow(_ event: CheckpointEvent) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.checkpoint?.name ?? "?")
                    .font(.body)
                    .strikethrough(event.isTombstoned || event.ignored)
                Text(event.timestamp, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if event.manualOverride {
                Image(systemName: "arrow.triangle.swap")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            // Toggle flags
            Button {
                event.ignored.toggle()
            } label: {
                Image(systemName: event.ignored ? "eye.slash.fill" : "eye")
                    .foregroundStyle(event.ignored ? .orange : .secondary)
            }
            .buttonStyle(.borderless)

            Button {
                event.isTombstoned.toggle()
            } label: {
                Image(systemName: event.isTombstoned ? "trash.fill" : "trash")
                    .foregroundStyle(event.isTombstoned ? .red : .secondary)
            }
            .buttonStyle(.borderless)
        }
    }
}

#if DEBUG
#Preview {
    let scenario = PreviewSupport.makeScenario(riderCount: 6, startedCount: 6, finishedCount: 4)
    NavigationStack {
        ReviewAndCorrectView(sessionId: scenario.sessionId)
    }
    .previewEnvironment(scenario)
}
#endif
