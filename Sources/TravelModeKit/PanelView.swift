import AppKit
import SwiftUI

/// The panel that opens from the menu bar.
public struct PanelView: View {
    @ObservedObject var controller: SleepController
    let boardFrames: [TileFrame]?
    @State private var openAtLogin: Bool
    @State private var syncingLoginSwitch = false
    @Environment(\.colorScheme) private var scheme

    /// - Parameters:
    ///   - boardFrames: draw the board at one fixed moment (for previews) instead of animating.
    ///   - openAtLogin: the starting value of the login switch (previews pass their own).
    public init(controller: SleepController, boardFrames: [TileFrame]? = nil, openAtLogin: Bool? = nil) {
        self.controller = controller
        self.boardFrames = boardFrames
        _openAtLogin = State(initialValue: openAtLogin ?? LoginItem.isEnabled)
    }

    public var body: some View {
        let mode = controller.mode
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                SplitFlapBoard(text: mode.title, frames: boardFrames)
                HStack(spacing: 7) {
                    Circle()
                        .fill(mode.color(in: scheme))
                        .frame(width: 8, height: 8)
                    Text(mode.detail(on: controller.device))
                        .font(.body)
                        .foregroundStyle(.primary)
                        .contentTransition(.opacity)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current mode: \(mode.title). \(mode.detail(on: controller.device))")
            .animation(.easeInOut(duration: 0.3), value: mode)

            if !controller.device.hasLid {
                desktopNote.padding(.top, 14)
            }

            if !controller.isSetUp && !controller.setupDismissed {
                setupCard.padding(.top, 14)
            }

            Button {
                controller.switchMode()
            } label: {
                Label("Switch to \(mode.other.title)", systemImage: mode.other.symbol)
            }
            .buttonStyle(SwitchButtonStyle())
            .focusRing(cornerRadius: 8)
            .padding(.top, 16)

            // The packing shortcut. At Desk the Mac can't sleep at all, so this switches first.
            Button {
                controller.switchToTravellingAndSleep()
            } label: {
                Label(mode == .desk ? "Switch to Travelling and sleep" : "Sleep now", systemImage: "moon.zzz")
            }
            .buttonStyle(QuietButtonStyle(prominent: true))
            .focusRing(cornerRadius: 4)
            .padding(.top, 10)

            if let message = controller.message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 12)

            if controller.device.hasLid {
                VStack(alignment: .leading, spacing: 3) {
                    Toggle("Screen off when the lid closes", isOn: $controller.screenOffOnLidClose)
                        .toggleStyle(PillToggleStyle())
                    Text("At Desk only. Also locks the Mac if a password is required after sleep.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .opacity(mode == .desk ? 1 : 0.6)
                .padding(.bottom, 10)
            }

            Toggle("Open at login", isOn: $openAtLogin)
                .toggleStyle(PillToggleStyle())
                .onChange(of: openAtLogin) { _, enabled in
                    guard !syncingLoginSwitch else { return }
                    do {
                        try LoginItem.set(enabled)
                    } catch {
                        controller.message = "Couldn't change Open at login: \(error.localizedDescription)"
                    }
                    syncLoginSwitch()
                }

            if controller.hasOwnRule {
                Button { controller.removePermission() } label: {
                    Label("Require password to switch…", systemImage: "lock")
                }
                    .buttonStyle(QuietButtonStyle())
                    .focusRing(cornerRadius: 4)
                    .help("Removes Travel Mode's sudo rule. macOS will ask for your password each time you switch.")
                    .padding(.top, 12)
            }

            HStack {
                Spacer()
                Button("Quit Travel Mode") { NSApp.terminate(nil) }
                    .buttonStyle(QuietButtonStyle())
                    .focusRing(cornerRadius: 4)
                    .keyboardShortcut("q")
            }
            .padding(.top, controller.hasOwnRule ? 6 : 12)
        }
        .padding(16)
        .frame(width: Theme.panelWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            // Menu bar windows don't shrink by themselves when content goes away (the setup card,
            // an error), which leaves a blank strip. Keep the window fitted to the content.
            if !controller.isDemo {
                GeometryReader { proxy in WindowFitter(contentHeight: proxy.size.height) }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: controller.mode)
        .onAppear {
            controller.message = nil
            controller.refresh()
            if boardFrames == nil { syncLoginSwitch() }
        }
    }

    /// Shows the real login-item state (it can fail, or need approval in System Settings).
    private func syncLoginSwitch() {
        let actual = LoginItem.isEnabled
        guard actual != openAtLogin else { return }
        syncingLoginSwitch = true
        openAtLogin = actual
        DispatchQueue.main.async { syncingLoginSwitch = false }
    }

    /// On a Mac without a lid, macOS's own Energy setting already keeps it running, more gently.
    private var desktopNote: some View {
        card(title: "Made for MacBooks",
             body: "A \(controller.device.name) has no lid, so you probably don't need this. To keep it running as a server, turn on \"Prevent automatic sleeping when the display is off\" in System Settings › Energy. That still lets you sleep it from the Apple menu.") {
            Button("Open Energy settings") { openEnergySettings() }
                .buttonStyle(OutlineButtonStyle())
                .focusRing(cornerRadius: 6)
        }
    }

    private var setupCard: some View {
        card(title: "Switch without a password",
             body: "Travel Mode can change modes without asking for your password each time. macOS asks for it once now. You can undo this any time.") {
            HStack(spacing: 8) {
                Button("Set up") { controller.setUp() }
                    .buttonStyle(OutlineButtonStyle())
                    .focusRing(cornerRadius: 6)
                Button("Not now") { controller.setupDismissed = true }
                    .buttonStyle(QuietButtonStyle())
                    .focusRing(cornerRadius: 4)
            }
        }
    }

    private func card<Actions: View>(title: String, body: String,
                                     @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            actions()
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func openEnergySettings() {
        let energy = URL(string: "x-apple.systempreferences:com.apple.Energy-Settings.extension")!
        if !NSWorkspace.shared.open(energy) {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }
}
