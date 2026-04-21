import Foundation
import SwiftData

enum DeviceRole: String, Codable, CaseIterable, Sendable {
    case start
    case checkpoint
    case finish
    case observer
}

@Model
final class DeviceInfo {
    @Attribute(.unique) var deviceId: String
    var displayName: String
    var roleRaw: String
    var assignedCheckpointId: UUID?

    var role: DeviceRole {
        get { DeviceRole(rawValue: roleRaw) ?? .observer }
        set { roleRaw = newValue.rawValue }
    }

    init(
        deviceId: String = UUID().uuidString,
        displayName: String = "",
        role: DeviceRole = .observer,
        assignedCheckpointId: UUID? = nil
    ) {
        self.deviceId = deviceId
        self.displayName = displayName
        self.roleRaw = role.rawValue
        self.assignedCheckpointId = assignedCheckpointId
    }
}
