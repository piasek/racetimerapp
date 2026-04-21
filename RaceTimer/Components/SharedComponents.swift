import SwiftUI

/// Banner shown when peer clock skew exceeds threshold.
struct ClockSkewBanner: View {
    let message: String?

    var body: some View {
        if let message {
            HStack {
                Image(systemName: "clock.badge.exclamationmark")
                Text(message)
                    .font(.caption)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(.orange, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal)
        }
    }
}

/// A large capture button with haptic feedback.
struct CaptureButton: View {
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button {
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            action()
        } label: {
            Text(title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
        .controlSize(.large)
        .padding()
        .accessibilityHint("Double-tap to record a timing event")
    }
}

/// Formatted time interval display.
struct TimeText: View {
    let interval: TimeInterval

    var body: some View {
        Text(formatted)
            .monospacedDigit()
    }

    private var formatted: String {
        let m = Int(interval) / 60
        let s = Int(interval) % 60
        let ms = Int((interval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}
