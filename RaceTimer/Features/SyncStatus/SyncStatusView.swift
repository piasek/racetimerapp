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

/// Persistent low-profile sync status strip. Designed to sit under the
/// navigation bar via `.safeAreaInset(edge: .top)` so every screen shows
/// at-a-glance peer connection state. Tap to open the full SyncStatusView.
struct SyncStatusBar: View {
    @Environment(SyncCoordinator.self) private var syncCoordinator
    @State private var showing = false

    var body: some View {
        let summary = makeSummary()
        Button {
            showing = true
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(summary.color)
                    .frame(width: 8, height: 8)
                Text(summary.label)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                summary.color.opacity(0.10)
                    .background(.ultraThinMaterial)
            }
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sync status: \(summary.label)")
        .accessibilityHint("Opens sync details")
        .sheet(isPresented: $showing) {
            SyncStatusView()
        }
    }

    private struct Summary {
        let label: String
        let color: Color
    }

    private func makeSummary() -> Summary {
        let peers = syncCoordinator.peerSync.discoveredPeers
        let connected = peers.filter { $0.state == .connected }.count
        let connecting = peers.filter { $0.state == .connecting }.count

        guard syncCoordinator.peerSync.isActive else {
            return Summary(label: "Sync off", color: .red)
        }
        if connected > 0 {
            let plural = connected == 1 ? "peer" : "peers"
            return Summary(label: "\(connected) \(plural) connected", color: .green)
        }
        if connecting > 0 {
            return Summary(label: "Connecting…", color: .orange)
        }
        return Summary(label: "Searching for peers…", color: .secondary)
    }
}

extension View {
    /// Pin a persistent sync status strip above content. Apply once at the
    /// NavigationStack root so it appears on every screen.
    func syncStatusBar() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            SyncStatusBar()
        }
    }
}
