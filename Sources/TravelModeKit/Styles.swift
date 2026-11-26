import AppKit
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

/// A two- or three-way choice drawn in SwiftUI, like a small segmented control.
/// VoiceOver reads each segment as a button, with the chosen one marked selected.
struct ChoicePicker<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: String
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let chosen = option == selection
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selection = option }
                } label: {
                    Text(title(option))
                        .font(.callout.weight(chosen ? .semibold : .regular))
                        .foregroundStyle(chosen ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(chosen ? Color.primary.opacity(0.14) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusRing(cornerRadius: 5)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// A small text button that opens a native menu of choices, with a check by the chosen one.
/// (Drawn in SwiftUI so the README previews can render it; the menu itself is AppKit.)
struct PopUpChoice<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let label: String
    let title: (Value) -> String
    var onPick: (Value) -> Void = { _ in }

    var body: some View {
        Button {
            showMenu()
        } label: {
            HStack(spacing: 3) {
                Text(title(selection))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusRing(cornerRadius: 4)
        .accessibilityLabel(label)
        .accessibilityValue(title(selection))
    }

    private func showMenu() {
        let menu = NSMenu()
        var chosenItem: NSMenuItem?
        for option in options {
            let item = ClosureMenuItem(title: title(option)) {
                selection = option
                onPick(option)
            }
            if option == selection {
                item.state = .on
                chosenItem = item
            }
            menu.addItem(item)
        }
        menu.popUp(positioning: chosenItem, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func run() { handler() }
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
