import SwiftUI

/// The one prominent action: switching mode. Slate, like the board.
struct SwitchButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.paper)
            // A fixed height: the laptop and suitcase icons differ in height, and the panel
            // shouldn't change size between modes.
            .frame(maxWidth: .infinity, minHeight: 36, maxHeight: 36)
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

/// Text actions. `prominent` ones (Sleep now) use the primary colour so they read as clickable;
/// the rest (Quit, the password option) stay secondary.
struct QuietButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(prominent ? .medium : .regular))
            .foregroundStyle(prominent ? .primary : .secondary)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A plain outlined button, for the cards.
struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.35), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// A small switch drawn in SwiftUI (so the README previews can render it), with native-level
/// contrast: the system accent colour when on, a clearly visible track when off.
/// VoiceOver reads it as a switch, not a button.
struct PillToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { configuration.isOn.toggle() }
        } label: {
            HStack {
                configuration.label
                    .font(.callout)
                    .foregroundStyle(.primary)
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? Color.accentColor : Color.primary.opacity(0.32))
                    .frame(width: 28, height: 16)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .overlay(Circle().strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                            .padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusRing(cornerRadius: 6)
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

/// Custom button styles get no system focus ring, so draw one in the accent colour when focused
/// (Tab with Full Keyboard Access).
struct FocusRing: ViewModifier {
    let cornerRadius: CGFloat
    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focused($focused)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .padding(-3)
                    .opacity(focused ? 1 : 0)
            )
    }
}

extension View {
    func focusRing(cornerRadius: CGFloat) -> some View { modifier(FocusRing(cornerRadius: cornerRadius)) }
}
