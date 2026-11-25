import SwiftUI

/// The one prominent action: switching mode. Slate, like the board.
struct SwitchButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(scheme == .dark ? Theme.flap : Theme.nightSlate)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(scheme == .dark ? 0.08 : 0), lineWidth: 1)
                    )
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// Quiet text actions: Sleep now, Quit, Remove permission.
struct QuietButtonStyle: ButtonStyle {
    var weight: Font.Weight = .regular

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: weight))
            .foregroundStyle(.secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A plain outlined button, for the one-time setup.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A small switch in the board's colours.
struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Theme.platformGreen : Color.primary.opacity(0.18))
                    .frame(width: 28, height: 16)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.2), radius: 0.5, y: 0.5)
                            .padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
