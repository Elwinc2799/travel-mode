import AppKit
import SwiftUI

/// The panel that opens from the menu bar.
public struct PanelView: View {
    @ObservedObject var controller: SleepController
    let boardFrames: [TileFrame]?
    @State private var openAtLogin: Bool

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
            SplitFlapBoard(text: mode.title, frames: boardFrames)

            HStack(spacing: 7) {
                Circle()
                    .fill(mode.color)
                    .frame(width: 7, height: 7)
                Text(mode.detail(on: controller.device))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .padding(.top, 10)
            .animation(.easeInOut(duration: 0.3), value: mode)

            if !controller.device.hasLid {
                desktopNote.padding(.top, 14)
            }

            if !controller.isSetUp {
                setupCard.padding(.top, 14)
            }

            Button {
                controller.switchMode()
            } label: {
                Label("Switch to \(mode.other.title)", systemImage: mode.other.symbol)
            }
            .buttonStyle(SwitchButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.top, 16)

            // Always laid out, so the panel keeps its size when the mode changes; shown only while Travelling.
            Button("Sleep now") { controller.sleepNow() }
                .buttonStyle(QuietButtonStyle(weight: .medium))
                .padding(.top, 10)
                .opacity(mode == .travelling ? 1 : 0)
                .disabled(mode != .travelling)
                .accessibilityHidden(mode != .travelling)

            if let message = controller.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 12)

            if controller.device.hasLid {
                Toggle("Screen off when the lid closes", isOn: $controller.screenOffOnLidClose)
                    .toggleStyle(PillToggleStyle())
                    .help("At Desk, macOS keeps the screen lit inside a closed lid. This turns it off, and locks the Mac if your password is required after the display sleeps.")
                    .padding(.bottom, 8)
            }

            Toggle("Open at login", isOn: $openAtLogin)
                .toggleStyle(PillToggleStyle())
                .onChange(of: openAtLogin) { _, enabled in
                    do { try LoginItem.set(enabled) } catch {
                        controller.message = "Couldn't change Open at login: \(error.localizedDescription)"
                    }
                }

            HStack {
                if controller.hasOwnRule {
                    Button("Remove permission") { controller.removePermission() }
                        .buttonStyle(QuietButtonStyle())
                }
                Spacer()
                Button("Quit Travel Mode") { NSApp.terminate(nil) }
                    .buttonStyle(QuietButtonStyle())
                    .keyboardShortcut("q")
            }
            .padding(.top, 10)
        }
        .padding(16)
        .frame(width: Theme.panelWidth)
        .animation(.easeInOut(duration: 0.25), value: controller.mode)
        .onAppear { controller.refresh() }
    }

    /// On a Mac without a lid, macOS's own Energy setting already keeps it running, more gently.
    private var desktopNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Made for MacBooks")
                .font(.system(size: 12, weight: .semibold))
            Text("A \(controller.device.name) has no lid, so you probably don't need this. To keep it running as a server, turn on \"Prevent automatic sleeping when the display is off\" in System Settings › Energy. That still lets you sleep it from the Apple menu.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Energy settings") { openEnergySettings() }
                .buttonStyle(OutlineButtonStyle())
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

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One-time setup")
                .font(.system(size: 12, weight: .semibold))
            Text("Let Travel Mode switch sleep without asking for your password each time. macOS asks for it once now.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set up") { controller.setUp() }
                .buttonStyle(OutlineButtonStyle())
                .padding(.top, 2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
