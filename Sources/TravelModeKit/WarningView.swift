import SwiftUI

/// The "you're about to pack a Mac that won't sleep" warning, shown in its own small panel under
/// the menu bar when the charger is unplugged At Desk. Needs no notification permission.
public struct UnplugWarningView: View {
    let deviceName: String
    let onSwitch: () -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var scheme

    public init(deviceName: String, onSwitch: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.deviceName = deviceName
        self.onSwitch = onSwitch
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "powerplug.portrait")
                    .font(.title2)
                    .foregroundStyle(Mode.desk.color(in: scheme))
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Still At Desk")
                        .font(.headline)
                    Text("Your \(deviceName) won't sleep, even in a bag. Switch to Travelling before you pack it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Spacer()
                Button("Not now", action: onDismiss)
                    .buttonStyle(QuietButtonStyle())
                    .focusRing(cornerRadius: 4)
                    .keyboardShortcut(.cancelAction)
                Button(action: onSwitch) {
                    Label("Switch to Travelling", systemImage: Mode.travelling.symbol)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(SwitchButtonStyle())
                .focusRing(cornerRadius: 8)
                .fixedSize()
            }
        }
        .padding(16)
        .frame(width: 340)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Still At Desk. Your \(deviceName) won't sleep, even in a bag.")
    }
}
