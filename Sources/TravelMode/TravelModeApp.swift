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

    private static let launchedBeforeKey = "launchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.info("Launched: mode \(self.controller.mode.rawValue, privacy: .public), device \(self.controller.device.name, privacy: .public)")
        controller.onUnpluggedAtDesk = { [weak self] in self?.showUnplugWarning() }
        controller.onPluggedIn = { [weak self] in self?.warning.close() }

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
