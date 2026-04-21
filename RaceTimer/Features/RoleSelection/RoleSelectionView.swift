import SwiftUI
import SwiftData

struct RoleSelectionView: View {
    @Binding var path: NavigationPath
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(RoleCoordinator.self) private var roleCoordinator

    @State private var session: Session?
    @State private var selectedCheckpointId: UUID?
    @State private var showCheckpointPicker = false

    var body: some View {
        List {
            Section {
                Text(session?.name ?? "Session")
                    .font(.headline)
                Text(session?.courseName ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Race Officials") {
                roleRow(
                    label: "Start Official",
                    subtitle: "Send riders off and start their timer",
                    icon: "flag.fill",
                    color: .green
                ) {
                    selectRole(.start)
                }

                roleRow(
                    label: "Checkpoint Official",
                    subtitle: "Record riders passing your checkpoint",
                    icon: "mappin.circle.fill",
                    color: .orange
                ) {
                    showCheckpointPicker = true
                }

                roleRow(
                    label: "Finish Official",
                    subtitle: "Record riders crossing the finish",
                    icon: "flag.checkered",
                    color: .red
                ) {
                    selectRole(.finish)
                }
            }

            Section("Observer") {
                roleRow(
                    label: "Live Results",
                    subtitle: "Watch race results in real time",
                    icon: "chart.bar.fill",
                    color: .blue
                ) {
                    selectRole(.observer, navigateTo: .liveResults(sessionId))
                }
            }
        }
        .navigationTitle("Select Role")
        .onAppear { loadSession() }
        .sheet(isPresented: $showCheckpointPicker) {
            checkpointPickerSheet
        }
    }

    // MARK: - Checkpoint picker

    @ViewBuilder
    private var checkpointPickerSheet: some View {
        NavigationStack {
            List {
                if let session {
                    let intermediates = session.sortedCheckpoints.filter { !$0.isStart && !$0.isFinish }
                    if intermediates.isEmpty {
                        ContentUnavailableView(
                            "No Intermediate Checkpoints",
                            systemImage: "mappin.slash",
                            description: Text("Add checkpoints in session setup first.")
                        )
                    } else {
                        ForEach(intermediates) { cp in
                            Button {
                                selectedCheckpointId = cp.id
                                showCheckpointPicker = false
                                selectRole(.checkpoint, checkpointId: cp.id)
                            } label: {
                                Label(cp.name, systemImage: "mappin.circle.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Pick Checkpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showCheckpointPicker = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func roleRow(
        label: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(.body)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func selectRole(
        _ role: DeviceRole,
        checkpointId: UUID? = nil,
        navigateTo route: Route? = nil
    ) {
        roleCoordinator.assignRole(role, checkpointId: checkpointId, sessionId: sessionId)
        if let route {
            path.append(route)
        } else {
            switch role {
            case .start:
                path.append(Route.startLine(sessionId))
            case .checkpoint:
                if let cpId = checkpointId {
                    path.append(Route.checkpointCapture(sessionId, checkpointId: cpId))
                }
            case .finish:
                path.append(Route.finishLine(sessionId))
            case .observer:
                path.append(Route.liveResults(sessionId))
            }
        }
    }

    private func loadSession() {
        session = try? modelContext.fetchByID(Session.self, id: sessionId)
    }
}
