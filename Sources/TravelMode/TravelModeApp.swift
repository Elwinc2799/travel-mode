import AppKit
import SwiftUI
import TravelModeKit

struct TravelModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = SleepController()

    var body: some Scene {
        MenuBarExtra {
            PanelView(controller: controller)
        } label: {
            Image(systemName: controller.mode.symbol)
                .accessibilityLabel("Travel Mode: \(controller.mode.title)")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let launchedBeforeKey = "launchedBefore"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // On the very first launch, open the panel so people see where the app lives.
        if !UserDefaults.standard.bool(forKey: Self.launchedBeforeKey) {
            UserDefaults.standard.set(true, forKey: Self.launchedBeforeKey)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { StatusItem.openPanel() }
        }
    }

    /// Opening the app again (Spotlight, Finder, Dock) shows the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        StatusItem.openPanel()
        return false
    }
}

/// Finds the app's menu bar button and clicks it, which opens the panel.
enum StatusItem {
    static func openPanel() {
        for window in NSApp.windows where String(describing: type(of: window)).contains("StatusBar") {
            if let button = findButton(in: window.contentView) {
                button.performClick(nil)
                return
            }
        }
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
