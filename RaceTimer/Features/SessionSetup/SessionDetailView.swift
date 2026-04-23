import SwiftUI
import SwiftData

struct SessionDetailView: View {
    @Binding var path: NavigationPath
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncCoordinator.self) private var syncCoordinator

    let sessionId: UUID
    @State private var session: Session?

    // Checkpoint add
    @State private var newCheckpointName = ""

    // Rider add
    @State private var showingAddRider = false
    @State private var riderFirstName = ""
    @State private var riderLastName = ""
    @State private var riderBibString = ""
    @State private var riderCategory = ""

    // Session edit
    @State private var editedName = ""
    @State private var editedNotes = ""

    var body: some View {
        Group {
            if let session {
                sessionContent(session)
            } else {
                ContentUnavailableView("Session not found", systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear { loadSession() }
    }

    @ViewBuilder
    private func sessionContent(_ session: Session) -> some View {
        List {
            // MARK: - Info section
            Section("Session Info") {
                TextField("Name", text: $editedName)
                    .onChange(of: editedName) { _, newValue in
                        broadcastSessionEdits(session, name: newValue, notes: editedNotes)
                    }
                TextField("Notes", text: $editedNotes, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: editedNotes) { _, newValue in
                        broadcastSessionEdits(session, name: editedName, notes: newValue)
                    }
            }

            // MARK: - Checkpoints section
            Section {
                ForEach(session.sortedCheckpoints) { cp in
                    HStack {
                        Text(cp.name)
                        Spacer()
                        Text(checkpointBadge(cp))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    deleteCheckpoints(offsets, from: session)
                }

                HStack {
                    TextField("New checkpoint", text: $newCheckpointName)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        addCheckpoint(to: session)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newCheckpointName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Checkpoints (\(session.checkpoints.count))")
            } footer: {
                Text("Start and Finish are created automatically. Add intermediate checkpoints here.")
            }

            // MARK: - Riders section
            Section {
                ForEach(session.riders) { rider in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rider.displayName)
                            .font(.body)
                        if let cat = rider.category, !cat.isEmpty {
                            Text(cat)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    deleteRiders(offsets, from: session)
                }

                Button {
                    showingAddRider = true
                } label: {
                    Label("Add Rider", systemImage: "person.badge.plus")
                }
            } header: {
                Text("Riders (\(session.riders.count))")
            }

            // MARK: - Continue
            Section {
                Button {
                    path.append(Route.roleSelection(session.id))
                } label: {
                    Label("Continue to Role Selection", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.checkpoints.count < 2 || session.riders.isEmpty)
            }
        }
        .navigationTitle(session.name)
        .sheet(isPresented: $showingAddRider) {
            addRiderSheet(session)
        }
    }

    private func broadcastSessionEdits(_ session: Session, name: String, notes: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        // Ignore empty-name edits — keep last valid value.
        let resolvedName = trimmedName.isEmpty ? session.name : trimmedName
        syncCoordinator.apply(.sessionUpserted(SessionPayload(
            sessionId: session.id,
            name: resolvedName,
            date: session.date,
            notes: notes
        )))
    }

    // MARK: - Checkpoint actions

    private func addCheckpoint(to session: Session) {
        let name = newCheckpointName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        // Insert before finish: new checkpoint gets second-to-last index.
        let sorted = session.sortedCheckpoints
        let insertIndex = max(sorted.count - 1, 1)

        var payloads: [SyncPayload] = []

        // Bump finish index if it collides with the new one.
        if let finish = sorted.last, finish.indexInCourse == insertIndex {
            payloads.append(.checkpointUpserted(CheckpointPayload(
                checkpointId: finish.id,
                sessionId: session.id,
                indexInCourse: insertIndex + 1,
                name: finish.name
            )))
        }

        payloads.append(.checkpointUpserted(CheckpointPayload(
            checkpointId: UUID(),
            sessionId: session.id,
            indexInCourse: insertIndex,
            name: name
        )))

        syncCoordinator.apply(payloads)
        newCheckpointName = ""
    }

    private func deleteCheckpoints(_ offsets: IndexSet, from session: Session) {
        let sorted = session.sortedCheckpoints
        var deleteIds: [UUID] = []
        for index in offsets {
            let cp = sorted[index]
            if session.checkpoints.count <= 2 { continue }
            if cp.isStart || cp.isFinish { continue }
            deleteIds.append(cp.id)
        }
        guard !deleteIds.isEmpty else { return }

        var payloads: [SyncPayload] = deleteIds.map { .checkpointDeleted(EntityIdPayload(id: $0)) }

        // Renumber remaining (excluding those we just deleted) contiguously.
        let remaining = sorted.filter { !deleteIds.contains($0.id) }
        for (i, cp) in remaining.enumerated() where cp.indexInCourse != i {
            payloads.append(.checkpointUpserted(CheckpointPayload(
                checkpointId: cp.id,
                sessionId: session.id,
                indexInCourse: i,
                name: cp.name
            )))
        }

        syncCoordinator.apply(payloads)
    }

    // MARK: - Rider actions

    private func deleteRiders(_ offsets: IndexSet, from session: Session) {
        let ids = offsets.map { session.riders[$0].id }
        syncCoordinator.apply(ids.map { .riderDeleted(EntityIdPayload(id: $0)) })
    }

    @ViewBuilder
    private func addRiderSheet(_ session: Session) -> some View {
        NavigationStack {
            Form {
                TextField("First name *", text: $riderFirstName)
                TextField("Last name", text: $riderLastName)
                TextField("Bib number", text: $riderBibString)
                    .keyboardType(.numberPad)
                TextField("Category", text: $riderCategory)
            }
            .navigationTitle("Add Rider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        clearRiderForm()
                        showingAddRider = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addRider(to: session)
                    }
                    .disabled(riderFirstName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func addRider(to session: Session) {
        syncCoordinator.apply(.riderUpserted(RiderPayload(
            riderId: UUID(),
            sessionId: session.id,
            firstName: riderFirstName.trimmingCharacters(in: .whitespaces),
            lastName: riderLastName.isEmpty ? nil : riderLastName,
            bibNumber: Int(riderBibString),
            category: riderCategory.isEmpty ? nil : riderCategory,
            notes: nil
        )))
        clearRiderForm()
        showingAddRider = false
    }

    private func clearRiderForm() {
        riderFirstName = ""
        riderLastName = ""
        riderBibString = ""
        riderCategory = ""
    }

    private func loadSession() {
        session = try? modelContext.fetchByID(Session.self, id: sessionId)
        if let session {
            editedName = session.name
            editedNotes = session.notes
        }
    }

    private func checkpointBadge(_ cp: Checkpoint) -> String {
        if cp.isStart { return "Start" }
        if cp.isFinish { return "Finish" }
        return "CP \(cp.indexInCourse)"
    }
}
