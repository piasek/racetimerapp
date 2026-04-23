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
                courseName: "",
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
}

private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.name)
                .font(.headline)
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
}
