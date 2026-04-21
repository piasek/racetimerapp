import Foundation
import os

/// Detects clock skew between peer devices using NTP-style ping exchanges.
/// Surfaces a warning when any peer's clock differs by more than the threshold.
@MainActor
@Observable
final class ClockService {
    /// Skew threshold in seconds. Warn if any peer exceeds this.
    static let skewThreshold: TimeInterval = 0.5

    /// Estimated clock offsets per peer device (deviceId → offset in seconds).
    /// Positive means the remote clock is ahead of ours.
    private(set) var peerOffsets: [String: TimeInterval] = [:]

    /// True if any connected peer has skew above the threshold.
    var hasSkewWarning: Bool {
        peerOffsets.values.contains { abs($0) > Self.skewThreshold }
    }

    /// Human-readable worst skew for display.
    var worstSkewDescription: String? {
        guard let worst = peerOffsets.values.max(by: { abs($0) < abs($1) }),
              abs(worst) > Self.skewThreshold else { return nil }
        let ms = Int(abs(worst) * 1000)
        return "Clock skew detected: ~\(ms)ms"
    }

    private let logger = Logger(subsystem: "com.racetimerapp", category: "ClockService")

    // MARK: - NTP-style ping

    /// Create a ping message to send to a peer.
    func createPing() -> ClockPing {
        ClockPing(sentAt: Date.now, receivedAt: nil, replyAt: nil)
    }

    /// Process a received ping (fill in receivedAt) and create a pong.
    func createPong(from ping: ClockPing) -> ClockPing {
        ClockPing(sentAt: ping.sentAt, receivedAt: Date.now, replyAt: Date.now)
    }

    /// Process a returned pong to estimate peer clock offset.
    func processPong(_ pong: ClockPing, from deviceId: String) {
        guard let sentAt = pong.sentAt,
              let receivedAt = pong.receivedAt,
              let _ = pong.replyAt else { return }

        let now = Date.now
        let roundTrip = now.timeIntervalSince(sentAt)
        let oneWay = roundTrip / 2.0
        let offset = receivedAt.timeIntervalSince(sentAt) - oneWay

        peerOffsets[deviceId] = offset
        logger.info("Peer \(deviceId) offset: \(String(format: "%.1f", offset * 1000))ms (RTT: \(String(format: "%.1f", roundTrip * 1000))ms)")

        if abs(offset) > Self.skewThreshold {
            logger.warning("Clock skew with \(deviceId) exceeds threshold: \(String(format: "%.0f", abs(offset) * 1000))ms")
        }
    }

    func removePeer(_ deviceId: String) {
        peerOffsets.removeValue(forKey: deviceId)
    }
}

struct ClockPing: Codable, Sendable {
    var sentAt: Date?
    var receivedAt: Date?
    var replyAt: Date?
}
