import AppKit
import SwiftUI
import TravelModeKit

// Renders the README images into the folder given as the first argument (default: docs):
//   panel-desk-light.png, panel-travelling-dark.png, ..., panel-setup-light.png
//   frames/flip-NNN.png  (turned into flip.gif by scripts/preview.sh)
// Uses demo controllers, so it never reads or changes the real sleep setting.

let outputDir = CommandLine.arguments.dropFirst().first ?? "docs"

/// A stand-in for the menu bar panel's window: rounded, with the system's light or dark surface.
struct PanelChrome<Content: View>: View {
    let scheme: ColorScheme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(scheme == .dark ? Color(hex: 0x2C2C2E) : Color(hex: 0xF5F5F7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(scheme == .dark ? 0.15 : 0.08), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
            )
            .padding(28)
            .environment(\.colorScheme, scheme)
    }
}

@MainActor
func save<V: View>(_ view: V, _ name: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Couldn't render \(name)")
    }
    let url = URL(fileURLWithPath: outputDir).appendingPathComponent(name)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    do { try png.write(to: url) } catch { fatalError("Couldn't write \(url.path): \(error)") }
}

MainActor.assumeIsolated {
    for scheme in [ColorScheme.light, .dark] {
        let schemeName = scheme == .dark ? "dark" : "light"
        for mode in Mode.allCases {
            let controller = SleepController(demo: mode)
            save(PanelChrome(scheme: scheme) { PanelView(controller: controller, openAtLogin: true) },
                 "panel-\(mode.rawValue)-\(schemeName).png")
        }
    }
    let firstRun = SleepController(demo: .travelling, setUp: false)
    save(PanelChrome(scheme: .light) { PanelView(controller: firstRun, openAtLogin: false) },
         "panel-setup-light.png")
    let desktop = SleepController(demo: .travelling, device: Device(name: "Mac mini", hasLid: false))
    save(PanelChrome(scheme: .light) { PanelView(controller: desktop, openAtLogin: false) },
         "panel-desktop-light.png")
    save(PanelChrome(scheme: .light) {
        UnplugWarningView(deviceName: "MacBook Air", onSwitch: {}, onDismiss: {})
    }, "unplug-warning-light.png")

    // The flip animation: rest, At Desk → Travelling, rest, Travelling → At Desk, rest. 30 fps.
    let fps = 30
    let segments: [(from: Mode, to: Mode, seconds: Double)] = [
        (.desk, .desk, 0.8),
        (.desk, .travelling, SplitFlapTiming.duration + 1.4),
        (.travelling, .desk, SplitFlapTiming.duration + 1.2),
    ]
    var index = 0
    for segment in segments {
        for frame in 0..<Int(segment.seconds * Double(fps)) {
            let time = Double(frame) / Double(fps)
            let tiles = SplitFlapTiming.frames(from: segment.from.title, to: segment.to.title, at: time)
            // The status line changes partway through the flip, as in the app.
            let shown = time < SplitFlapTiming.duration * 0.6 ? segment.from : segment.to
            let controller = SleepController(demo: shown)
            save(PanelChrome(scheme: .light) {
                PanelView(controller: controller, boardFrames: tiles, openAtLogin: true)
            }, String(format: "frames/flip-%03d.png", index))
            index += 1
        }
    }
}
