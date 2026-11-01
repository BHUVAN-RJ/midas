import Foundation
import SwiftUI

// Compiled into both the app and the widget extension (shell/project.yml), so the widget
// describes and draws a Sidekick exactly as the home grid does.

/// One Sidekick in the folder, from its manifest (id, name, SF Symbol, background color, and the
/// background in dark mode when the manifest gives one: `icon.backgroundDark`, founder 2026-10-31).
struct SidekickEntry: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let symbolName: String
    let backgroundHex: String
    let version: String
    /// Absent in a manifest from before build 22 and in lists saved by older builds.
    var backgroundDarkHex: String? = nil

    var backgroundColor: Color {
        SidekickColor.color(fromHex: backgroundHex)
    }
}

enum SidekickColor {
    /// "#FF9500" to a Color; anything else is gray rather than a crash.
    static func color(fromHex hex: String) -> Color {
        guard let components = rgbComponents(fromHex: hex) else {
            return .gray
        }
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func rgbComponents(fromHex hex: String) -> (red: Double, green: Double, blue: Double)? {
        guard hex.count == 7, hex.hasPrefix("#") else {
            return nil
        }
        let digits = hex.dropFirst()
        guard let packed = UInt32(digits, radix: 16) else {
            return nil
        }
        let red = Double((packed >> 16) & 0xFF) / 255
        let green = Double((packed >> 8) & 0xFF) / 255
        let blue = Double(packed & 0xFF) / 255
        return (red, green, blue)
    }
}
