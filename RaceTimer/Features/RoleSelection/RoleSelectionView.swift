import SwiftUI
import SwiftData

struct RoleSelectionView: View {
    @Binding var path: NavigationPath
    let sessionId: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(RoleCoordinator.self) private var roleCoordinator
    @Environment(SyncCoordinator.self) private var syncCoordinator

    @State private var session: Session?

    var body: some View {
        List {
            Section("Select Role") {
                roleRow(
                    label: "Start",
                    subtitle: "Send riders off and start their timer",
                    icon: "flag.fill",
                    color: .green
                ) {
                    selectRole(.start)
                }

                roleRow(
                    label: "Checkpoint",
                    subtitle: "Record riders passing your checkpoint",
                    icon: "mappin.circle.fill",
                    color: .orange
                ) {
                    enterCheckpointRole()
                }

                roleRow(
                    label: "Finish",
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
        .navigationTitle("Start Timing")
        .onAppear { loadSession() }
    }

    // MARK: - Checkpoint role (implicit per-device checkpoint)

    /// Find this device's checkpoint for the session (matched by deviceId),
    /// or implicitly create one named after the device's display name.
    /// Then push CheckpointCaptureView for that checkpoint.
    private func enterCheckpointRole() {
        guard let session else { return }
        let myDeviceId = roleCoordinator.deviceId

        let existing = session.checkpoints.first { $0.createdByDeviceId == myDeviceId }
        let cpId: UUID

        if let existing {
            cpId = existing.id
        } else {
            cpId = UUID()
            let sorted = session.sortedCheckpoints
            // Insert before the finish: take the current finish's index, push
            // finish out by one. If there is no finish yet, fall back to 1.
            let insertIndex = max(sorted.count - 1, 1)

            var payloads: [SyncPayload] = []
            if let finish = sorted.last, finish.indexInCourse == insertIndex {
                payloads.append(.checkpointUpserted(CheckpointPayload(
                    checkpointId: finish.id,
                    sessionId: session.id,
                    indexInCourse: insertIndex + 1,
                    name: finish.name,
                    createdByDeviceId: finish.createdByDeviceId
                )))
            }
            payloads.append(.checkpointUpserted(CheckpointPayload(
                checkpointId: cpId,
                sessionId: session.id,
                indexInCourse: insertIndex,
                name: "Checkpoint - \(roleCoordinator.displayName)",
                createdByDeviceId: myDeviceId
            )))
            syncCoordinator.apply(payloads)
        }

        selectRole(.checkpoint, checkpointId: cpId)
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

#if DEBUG
#Preview {
    let scenario = PreviewSupport.makeScenario()
    NavigationStack {
        RoleSelectionView(path: .constant(NavigationPath()), sessionId: scenario.sessionId)
    }
    .previewEnvironment(scenario)
}
#endif
