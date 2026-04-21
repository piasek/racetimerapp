import Foundation
import SwiftUI

/// Tracks this device's stable identity and current role assignment.
/// Device ID persists across launches via UserDefaults.
@MainActor
@Observable
final class RoleCoordinator {
    private static let deviceIdKey = "RaceTimer.deviceId"
    private static let displayNameKey = "RaceTimer.displayName"

    let deviceId: String

    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: Self.displayNameKey) }
    }

    var currentRole: DeviceRole = .observer
    var assignedCheckpointId: UUID?

    /// The session this device is currently operating in.
    var activeSessionId: UUID?

    init() {
        if let stored = UserDefaults.standard.string(forKey: Self.deviceIdKey) {
            self.deviceId = stored
        } else {
            let newId = UUID().uuidString
            UserDefaults.standard.set(newId, forKey: Self.deviceIdKey)
            self.deviceId = newId
        }
        self.displayName = UserDefaults.standard.string(forKey: Self.displayNameKey)
            ?? UIDevice.current.name
    }

    func assignRole(_ role: DeviceRole, checkpointId: UUID? = nil, sessionId: UUID) {
        currentRole = role
        assignedCheckpointId = checkpointId
        activeSessionId = sessionId
    }

    func clear() {
        currentRole = .observer
        assignedCheckpointId = nil
        activeSessionId = nil
    }
}
