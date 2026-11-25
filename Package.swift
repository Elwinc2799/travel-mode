// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TravelMode",
    platforms: [.macOS(.v14)],
    targets: [
        // Views, the split-flap board and the sleep switch. Shared by the app and the preview renderer.
        .target(name: "TravelModeKit"),
        // The menu bar app (and its small command-line interface).
        .executableTarget(name: "TravelMode", dependencies: ["TravelModeKit"]),
        // Renders the README screenshots and the flip animation without touching real sleep settings.
        .executableTarget(name: "RenderPreview", dependencies: ["TravelModeKit"], path: "Tools/RenderPreview"),
    ]
)
