// Draws the app icon: one departure-board flap tile with an amber airplane.
// Usage: swift Tools/MakeIcon/icon.swift <output.png>   (1024 × 1024)
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Housing: the board's night slate, in the macOS icon grid (824 pt squircle, 100 pt margin).
let housing = NSRect(x: 100, y: 100, width: 824, height: 824)
let housingPath = NSBezierPath(roundedRect: housing, xRadius: 185, yRadius: 185)
NSGradient(starting: color(0x2A3747), ending: color(0x18212B))!.draw(in: housingPath, angle: -90)

// The flap tile, split by its hinge.
let tile = NSRect(x: 262, y: 222, width: 500, height: 580)
let gap: CGFloat = 10
let top = NSRect(x: tile.minX, y: tile.midY + gap / 2, width: tile.width, height: tile.height / 2 - gap / 2)
let bottom = NSRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height / 2 - gap / 2)
NSGradient(starting: color(0x3A4B62), ending: color(0x2E3D50))!
    .draw(in: NSBezierPath(roundedRect: top, xRadius: 46, yRadius: 46), angle: -90)
NSGradient(starting: color(0x2B3949), ending: color(0x243142))!
    .draw(in: NSBezierPath(roundedRect: bottom, xRadius: 46, yRadius: 46), angle: -90)

// Hinge pins on each side.
color(0x0F161E).setFill()
for x in [tile.minX - 18, tile.maxX + 2] {
    NSBezierPath(roundedRect: NSRect(x: x, y: tile.midY - 22, width: 16, height: 44), xRadius: 6, yRadius: 6).fill()
}

// The airplane, in departure amber, across the hinge like a letter on the board.
let config = NSImage.SymbolConfiguration(pointSize: 330, weight: .bold)
    .applying(NSImage.SymbolConfiguration(paletteColors: [color(0xF5B841)]))
if let plane = NSImage(systemSymbolName: "airplane", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = plane.size
    plane.draw(in: NSRect(x: tile.midX - s.width / 2, y: tile.midY - s.height / 2, width: s.width, height: s.height))
}

// Redraw the hinge line over the plane so it reads as printed on the flaps.
color(0x16202A).setFill()
NSRect(x: tile.minX, y: tile.midY - gap / 2, width: tile.width, height: gap).fill()

image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
let output = CommandLine.arguments.dropFirst().first ?? "icon_1024.png"
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
