import SwiftUI

/// The countdown shown in the middle of the screen before the Mac sleeps, styled like the
/// system's volume and brightness overlays: a moon in a ring that drains as time runs out.
public struct SleepCountdownView: View {
    let endsAt: Date
    let duration: TimeInterval
    /// Draw one fixed moment (seconds left), for the README previews.
    let fixedRemaining: TimeInterval?
    let onCancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// VoiceOver moves into this window when it opens; put its cursor straight on Cancel.
    @AccessibilityFocusState private var cancelFocused: Bool

    public init(endsAt: Date, duration: TimeInterval, fixedRemaining: TimeInterval? = nil,
                onCancel: @escaping () -> Void) {
        self.endsAt = endsAt
        self.duration = duration
        self.fixedRemaining = fixedRemaining
        self.onCancel = onCancel
    }

    public var body: some View {
        Group {
            if let fixedRemaining {
                content(remaining: fixedRemaining)
            } else {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    content(remaining: max(0, endsAt.timeIntervalSince(context.date)))
                }
            }
        }
        .onAppear {
            // After VoiceOver has landed in the new window, then move it to Cancel.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { cancelFocused = true }
        }
    }

    private func content(remaining: TimeInterval) -> some View {
        let seconds = max(1, Int(remaining.rounded(.up)))
        // With Reduce Motion, the ring stays full and only the number changes.
        let fraction = reduceMotion ? 1 : CGFloat(remaining / duration)
        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Mode.travelling.color(in: scheme),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.primary)
            }
            .frame(width: 86, height: 86)
            .padding(.top, 6)
            .accessibilityHidden(true)

            Text("Sleeping in \(seconds)…")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: seconds)
                .accessibilityHidden(true)

            // The only VoiceOver stop here, so VO-Space cancels wherever the cursor lands.
            Button("Cancel", action: onCancel)
                .buttonStyle(OutlineButtonStyle())
                .focusRing(cornerRadius: 6)
                // No per-second value: VoiceOver re-reads the button each time it changes, cutting
                // itself off. The announcement gives the time, and the ticks mark the last seconds.
                .accessibilityLabel("Cancel sleep")
                .accessibilityHint("Keeps the Mac awake.")
                .accessibilityFocused($cancelFocused)
        }
        .padding(22)
        .frame(width: 210)
    }
}
