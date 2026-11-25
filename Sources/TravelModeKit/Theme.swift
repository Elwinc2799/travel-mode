import SwiftUI

/// The departure-board palette. Only the board is custom; the panel itself uses the system material.
public enum Theme {
    public static let nightSlate = Color(hex: 0x1F2A36)
    public static let flap = Color(hex: 0x2B3949)
    public static let flapLight = Color(hex: 0x34445A)
    public static let hinge = Color(hex: 0x16202A)
    public static let paper = Color(hex: 0xF3EDE2)
    public static let departureAmber = Color(hex: 0xF5B841)
    public static let platformGreen = Color(hex: 0x6CC3A0)

    public static let tileSize = CGSize(width: 24, height: 34)
    public static let panelWidth: CGFloat = 320
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}
