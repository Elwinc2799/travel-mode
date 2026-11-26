import AppKit
import SwiftUI
import TravelModeKit

struct TravelModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PanelView(controller: appDelegate.controller)
        } label: {
            MenuBarIcon(controller: appDelegate.controller)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarIcon: View {
    @ObservedObject var controller: SleepController

    var body: some View {
        Image(nsImage: Self.icon(for: controller.mode))
            .accessibilityLabel("Travel Mode: \(controller.mode.title)")
            .help("Travel Mode: \(controller.mode.title)")
    }

    /// Both symbols drawn centred on the same fixed canvas, so the menu bar item keeps one width.
    /// (The laptop is wider than the suitcase; a changing width made the open panel shift sideways.)
    static func icon(for mode: Mode) -> NSImage {
        let canvas = NSSize(width: 22, height: 16)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let symbol = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: mode.title)?
            .withSymbolConfiguration(config) else { return NSImage(size: canvas) }
        let image = NSImage(size: canvas, flipped: false) { rect in
            let scale = min(1, rect.width / symbol.size.width, rect.height / symbol.size.height)
            let size = NSSize(width: symbol.size.width * scale, height: symbol.size.height * scale)
            symbol.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2,
                                   width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = SleepController()
    private let warning = WarningPanel()
    private let countdown = CountdownPanel()
    private var escapeMonitor: Any?

    private static let launchedBeforeKey = "launchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Launched: mode \(self.controller.mode.rawValue, privacy: .public), device \(self.controller.device.name, privacy: .public)")
        controller.onUnpluggedAtDesk = { [weak self] in self?.showUnplugWarning() }
        controller.onPluggedIn = { [weak self] in self?.warning.close() }
        controller.onSleepCountdown = { [weak self] endsAt in self?.showCountdown(until: endsAt) }

        // `open -a "Travel Mode" --args --preview-countdown` shows the countdown without sleeping.
        if ProcessInfo.processInfo.arguments.contains("--preview-countdown") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showCountdown(until: Date().addingTimeInterval(SleepController.sleepCountdown))
                DispatchQueue.main.asyncAfter(deadline: .now() + SleepController.sleepCountdown) {
                    self?.showCountdown(until: nil)
                }
            }
        }

        // `open -a "Travel Mode" --args --preview-warning` shows the warning, for testing.
        if ProcessInfo.processInfo.arguments.contains("--preview-warning") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.showUnplugWarning() }
        }

        // On the very first launch, open the panel so people see where the app lives.
        if !UserDefaults.standard.bool(forKey: Self.launchedBeforeKey) {
            UserDefaults.standard.set(true, forKey: Self.launchedBeforeKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                if !StatusItem.openPanel() { log.error("Couldn't find the menu bar button to open the panel") }
            }
        }
    }

    /// Any quit, including logout and restart: never leave the screen dimmed. (Turning sleep back
    /// on happens only for Quit in the panel; see `SleepController.prepareToQuit`.)
    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreBrightness(reason: "app quitting")
    }

    /// The countdown before sleep, in the middle of the screen. Esc cancels it while the panel is open.
    private func showCountdown(until endsAt: Date?) {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
        guard let endsAt else {
            countdown.close()
            return
        }
        countdown.show(endsAt: endsAt, duration: controller.countdownLength,
                       onCancel: { [weak self] in self?.controller.cancelSleep() })
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.controller.sleepingAt != nil else { return event }
            self.controller.cancelSleep()
            return nil
        }
    }

    /// Opening the app again (Spotlight, Finder, Dock) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItem.openPanel()
        return false
    }

    /// The moment that matters: unplugged while the Mac can't sleep, probably about to be packed.
    private func showUnplugWarning() {
        log.info("Showing the unplugged-at-desk warning")
        warning.show(deviceName: controller.device.name,
                     onSwitch: { [weak self] in
                         guard let self else { return }
                         if self.controller.mode == .desk { self.controller.switchMode() }
                         self.warning.close()
                     },
                     onDismiss: { [weak self] in self?.warning.close() })
    }
}

/// A small floating panel under the menu bar, top right, like a system alert. Shown without
/// taking focus from the app you're using, with the system alert sound.
@MainActor
final class WarningPanel {
    private var panel: NSPanel?

    func show(deviceName: String, onSwitch: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        close()
        let content = UnplugWarningView(deviceName: deviceName, onSwitch: onSwitch, onDismiss: onDismiss)
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                            backing: .buffered, defer: false)
        let background = NSVisualEffectView()
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        background.addSubview(hosting)
        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true

        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let size = hosting.fittingSize
            panel.setFrameOrigin(NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 8))
        }
        panel.orderFrontRegardless()
        NSSound(named: "Funk")?.play()
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The sleep countdown, centred on the screen with the pointer, like the volume overlay.
/// Doesn't take focus from the app you're using.
@MainActor
final class CountdownPanel {
    private var panel: NSPanel?

    func show(endsAt: Date, duration: TimeInterval, onCancel: @escaping () -> Void) {
        close()
        let hosting = NSHostingView(rootView: SleepCountdownView(endsAt: endsAt, duration: duration,
                                                                 onCancel: onCancel))
        let size = hosting.fittingSize
        hosting.frame.size = size

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                            backing: .buffered, defer: false)
        let background = NSVisualEffectView()
        background.material = .hudWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.masksToBounds = true
        background.addSubview(hosting)
        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            let frame = screen.frame
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.15; panel.animator().alphaValue = 1 }
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Finds the app's menu bar button and clicks it, which opens the panel.
@MainActor
enum StatusItem {
    @discardableResult
    static func openPanel() -> Bool {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let button = findButton(in: window.contentView) {
                button.performClick(nil)
                return true
            }
        }
        return false
    }

    private static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}
