import SwiftUI

/// Live view of peer-to-peer sync status: this device's name, which peers
/// are visible, their connection state, and recent sync activity.
struct SyncStatusView: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("This Device") {
                    LabeledContent("Name", value: syncCoordinator.peerSync.localDisplayName)
                    LabeledContent("Sync", value: syncCoordinator.peerSync.isActive ? "Running" : "Stopped")
                }

                peersSection

                Section("Activity") {
                    LabeledContent("Events sent", value: "\(syncCoordinator.eventsSent)")
                    LabeledContent("Events received", value: "\(syncCoordinator.eventsReceived)")
                    if let sent = syncCoordinator.lastSentAt {
                        LabeledContent("Last sent", value: sent.formatted(.relative(presentation: .numeric)))
                    }
                    if let recv = syncCoordinator.lastReceivedAt {
                        LabeledContent("Last received", value: recv.formatted(.relative(presentation: .numeric)))
                    }
                }

                Section {
                    Text("Devices must be on the same Wi‑Fi network and have Local Network permission granted. MultipeerConnectivity does not work in the iOS Simulator over Bluetooth.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sync Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var peersSection: some View {
        let peers = syncCoordinator.peerSync.discoveredPeers
        Section("Peers (\(peers.count))") {
            if peers.isEmpty {
                ContentUnavailableView(
                    "No peers found",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Make sure another device is running RaceTimer on the same Wi‑Fi network.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(peers) { peer in
                    PeerRow(peer: peer)
                }
            }
        }
    }
}

private struct PeerRow: View {
    let peer: DiscoveredPeer

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName)
                    .font(.body)
                HStack(spacing: 6) {
                    Text(peer.state.rawValue.capitalized)
                    if let role = peer.role {
                        Text("·")
                        Text(role)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var icon: String {
        switch peer.state {
        case .discovered: "antenna.radiowaves.left.and.right"
        case .connecting: "arrow.triangle.2.circlepath"
        case .connected:  "checkmark.circle.fill"
        }
    }

    private var color: Color {
        switch peer.state {
        case .discovered: .secondary
        case .connecting: .orange
        case .connected:  .green
        }
    }
}

/// Toolbar button + sheet wrapper. Badge shows connected-peer count.
struct SyncStatusToolbarButton: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: iconName)
                .symbolRenderingMode(.hierarchical)
                .overlay(alignment: .topTrailing) {
                    if connectedCount > 0 {
                        Text("\(connectedCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Color.green))
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .accessibilityLabel("Sync status")
        .sheet(isPresented: $showing) {
            SyncStatusView()
        }
    }

    private var connectedCount: Int {
        syncCoordinator.peerSync.discoveredPeers.filter { $0.state == .connected }.count
    }

    private var iconName: String {
        connectedCount > 0
            ? "antenna.radiowaves.left.and.right"
            : "antenna.radiowaves.left.and.right.slash"
    }
}
