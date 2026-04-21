import SwiftUI
import SwiftData

struct SessionSetupView: View {
    @Binding var path: NavigationPath
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Environment(\.modelContext) private var modelContext

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
        let session = Session(name: newSessionName)
        modelContext.insert(session)

        // Auto-create Start and Finish checkpoints
        let start = Checkpoint(indexInCourse: 0, name: "Start")
        start.session = session
        modelContext.insert(start)

        let finish = Checkpoint(indexInCourse: 1, name: "Finish")
        finish.session = session
        modelContext.insert(finish)

        newSessionName = ""
        path.append(Route.sessionDetail(session.id))
    }

    private func deleteSessions(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(sessions[index])
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
