import SwiftUI
import SwiftData

struct SessionSetupView: View {
    @Binding var path: NavigationPath
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncCoordinator.self) private var syncCoordinator

    @State private var showingNewSession = false
    @State private var newSessionName = ""

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "timer",
                    description: Text("Create a session to get started.")
                )
            }

            ForEach(sessions) { session in
                Button {
                    path.append(Route.sessionDetail(session.id))
                } label: {
                    SessionRow(session: session)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        cloneSession(session)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.blue)
                }
            }
            .onDelete(perform: deleteSessions)
        }
        .navigationTitle("Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewSession = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New Session", isPresented: $showingNewSession) {
            TextField("Session name", text: $newSessionName)
            Button("Create") { createSession() }
            Button("Cancel", role: .cancel) { newSessionName = "" }
        } message: {
            Text("Enter a name for the new race session.")
        }
    }

    private func createSession() {
        guard !newSessionName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let sessionId = UUID()
        let startId = UUID()
        let finishId = UUID()
        let name = newSessionName

        syncCoordinator.apply([
            .sessionUpserted(SessionPayload(
                sessionId: sessionId,
                name: name,
                date: .now,
                notes: ""
            )),
            .checkpointUpserted(CheckpointPayload(
                checkpointId: startId,
                sessionId: sessionId,
                indexInCourse: 0,
                name: "Start"
            )),
            .checkpointUpserted(CheckpointPayload(
                checkpointId: finishId,
                sessionId: sessionId,
                indexInCourse: 1,
                name: "Finish"
            )),
        ])

        newSessionName = ""
        path.append(Route.sessionDetail(sessionId))
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            syncCoordinator.apply(.sessionDeleted(EntityIdPayload(id: sessions[index].id)))
        }
    }

    /// Duplicate an existing session: same name (with " (copy)" suffix), today's
    /// date, copied checkpoints and riders. Runs and checkpoint events are not
    /// copied — the new session starts with no timing data.
    private func cloneSession(_ source: Session) {
        let newSessionId = UUID()
        var payloads: [SyncPayload] = [
            .sessionUpserted(SessionPayload(
                sessionId: newSessionId,
                name: "\(source.name) (copy)",
                date: .now,
                notes: source.notes
            )),
        ]
        for cp in source.sortedCheckpoints {
            payloads.append(.checkpointUpserted(CheckpointPayload(
                checkpointId: UUID(),
                sessionId: newSessionId,
                indexInCourse: cp.indexInCourse,
                name: cp.name
            )))
        }
        for rider in source.riders {
            payloads.append(.riderUpserted(RiderPayload(
                riderId: UUID(),
                sessionId: newSessionId,
                firstName: rider.firstName,
                lastName: rider.lastName,
                bibNumber: rider.bibNumber,
                category: rider.category,
                notes: rider.notes
            )))
        }
        syncCoordinator.apply(payloads)
    }
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .font(.headline)
            if let dateText {
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(session.riders.count)", systemImage: "person.2")
                Label("\(session.checkpoints.count) cp", systemImage: "mappin")
                Label("\(session.runs.count) runs", systemImage: "flag")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Hide the date if the session is in the future and hasn't occurred yet.
    private var dateText: String? {
        let now = Date()
        guard session.date <= now else { return nil }
        return session.date.formatted(.dateTime.weekday().month().day().year())
    }
}
