import Foundation

// Light and dark for every widget (founder, 2026-10-27, docs/PRODUCT.md "Widget builder: light and
// dark for every widget"): seen on build 20 in dark mode, Water's widget kept its light sand and
// sea while its text turned white (the system colour), white on light. Every explicit colour of a
// description may be `{ light, dark }`; for a single colour the builder derives the dark one here,
// and text without a colour of its own gets an ink chosen for the widget's own background in each
// mode. Pure colour sums on "#RRGGBB", so tests can check them without drawing.

enum SidekickWidgetInk {
    /// Dark ink, for light backgrounds.
    static let darkInkHex = "#1C1C1E"
    /// Light ink, for dark backgrounds.
    static let lightInkHex = "#F5F5F7"
    /// The system widget background (`secondarySystemGroupedBackground`) in each mode.
    static let systemLightBackgroundHex = "#FFFFFF"
    static let systemDarkBackgroundHex = "#1C1C1E"
    /// systemBlue, the tint when a description gives none.
    static let defaultTintHex = "#007AFF"

    /// WCAG contrast for body text, and for marks that are not text (bars, rings, ticks).
    static let textContrast = 4.5
    static let markContrast = 3.0
    /// The faintest secondary ink: the ink at this opacity, more when that is not readable.
    static let secondaryInkOpacity = 0.6

    /// The lightness a derived dark background and a derived dark fill get (HSL, 0 to 1): a night
    /// background, and a fill that still shows above it.
    static let darkBackgroundLightness = 0.10
    static let darkFillLightness = 0.30

    // MARK: Contrast

    /// WCAG relative luminance, 0 (black) to 1 (white); nil for anything but "#RRGGBB".
    static func luminance(_ hex: String) -> Double? {
        guard let components = SidekickColor.rgbComponents(fromHex: hex) else {
            return nil
        }
        let red = linearLight(components.red)
        let green = linearLight(components.green)
        let blue = linearLight(components.blue)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func linearLight(_ channel: Double) -> Double {
        if channel <= 0.04045 {
            return channel / 12.92
        }
        return pow((channel + 0.055) / 1.055, 2.4)
    }

    /// WCAG contrast ratio, 1 to 21; 1 when either is not "#RRGGBB".
    static func contrast(_ firstHex: String, _ secondHex: String) -> Double {
        guard let first = luminance(firstHex), let second = luminance(secondHex) else {
            return 1
        }
        let lighter = max(first, second)
        let darker = min(first, second)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The lowest contrast of a colour against any of the surfaces behind it.
    static func lowestContrast(_ hex: String, over surfaceHexes: [String]) -> Double {
        var lowest = Double.infinity
        for surfaceHex in surfaceHexes {
            lowest = min(lowest, contrast(hex, surfaceHex))
        }
        return lowest == .infinity ? 21 : lowest
    }

    // MARK: Ink

    /// Dark ink or light ink, whichever reads better over every surface (by luminance: dark on
    /// light, light on dark). The surfaces are the widget's own background and any fill's sea.
    static func inkHex(over surfaceHexes: [String]) -> String {
        let darkContrast = lowestContrast(darkInkHex, over: surfaceHexes)
        let lightContrast = lowestContrast(lightInkHex, over: surfaceHexes)
        return darkContrast >= lightContrast ? darkInkHex : lightInkHex
    }

    /// The opacity of the secondary ink: `secondaryInkOpacity`, raised in steps until the ink,
    /// blended over each surface, reads as body text (1 when nothing less does).
    static func secondaryOpacity(inkHex: String, over surfaceHexes: [String]) -> Double {
        var opacity = secondaryInkOpacity
        while opacity < 1 {
            if isReadable(inkHex: inkHex, opacity: opacity, over: surfaceHexes) {
                return opacity
            }
            opacity += 0.05
        }
        return 1
    }

    private static func isReadable(inkHex: String, opacity: Double, over surfaceHexes: [String]) -> Bool {
        for surfaceHex in surfaceHexes {
            let blendedHex = blend(inkHex, opacity: opacity, over: surfaceHex)
            if contrast(blendedHex, surfaceHex) < textContrast {
                return false
            }
        }
        return true
    }

    /// A colour at an opacity over another, as the solid colour it draws.
    static func blend(_ hex: String, opacity: Double, over backgroundHex: String) -> String {
        guard let front = SidekickColor.rgbComponents(fromHex: hex),
              let back = SidekickColor.rgbComponents(fromHex: backgroundHex) else {
            return hex
        }
        let red = front.red * opacity + back.red * (1 - opacity)
        let green = front.green * opacity + back.green * (1 - opacity)
        let blue = front.blue * opacity + back.blue * (1 - opacity)
        return hexString(red: red, green: green, blue: blue)
    }

    // MARK: Derived dark colours (a single colour from an older page)

    /// A widget background for dark mode from its light one: the same hue, at night lightness.
    /// The hue never moves, so a derived colour is never purple unless the page's own was.
    static func darkBackgroundHex(fromLight lightHex: String) -> String {
        return withLightness(lightHex, lightness: darkBackgroundLightness, saturationScale: 0.6)
    }

    /// A fill (the sea) for dark mode from its light one: the same hue, deep, still above a
    /// derived night background.
    static func darkFillHex(fromLight lightHex: String) -> String {
        return withLightness(lightHex, lightness: darkFillLightness, saturationScale: 0.6)
    }

    /// A foreground colour (text, symbol, button, chart, tick) kept as it is when it reads over
    /// the surfaces, else made lighter or darker, same hue, until it does (or as far as it goes).
    static func readableHex(_ hex: String, over surfaceHexes: [String], minimumContrast: Double) -> String {
        guard let hsl = hsl(hex), lowestContrast(hex, over: surfaceHexes) < minimumContrast else {
            return hex
        }
        let surfacesAreDark = inkHex(over: surfaceHexes) == lightInkHex
        var lightness = hsl.lightness
        var candidateHex = hex
        // Lighter over dark surfaces, darker over light ones, 2% at a time.
        while lowestContrast(candidateHex, over: surfaceHexes) < minimumContrast {
            lightness += surfacesAreDark ? 0.02 : -0.02
            guard lightness > 0, lightness < 1 else {
                break
            }
            candidateHex = fromHSL(hue: hsl.hue, saturation: hsl.saturation, lightness: lightness)
        }
        return candidateHex
    }

    private static func withLightness(_ hex: String, lightness: Double, saturationScale: Double) -> String {
        guard let hsl = hsl(hex) else {
            return hex
        }
        let targetLightness = min(hsl.lightness, lightness)
        return fromHSL(hue: hsl.hue, saturation: hsl.saturation * saturationScale, lightness: targetLightness)
    }

    // MARK: HSL

    /// Hue in degrees (0 to 360), saturation and lightness 0 to 1.
    static func hsl(_ hex: String) -> (hue: Double, saturation: Double, lightness: Double)? {
        guard let components = SidekickColor.rgbComponents(fromHex: hex) else {
            return nil
        }
        let highest = max(components.red, components.green, components.blue)
        let lowest = min(components.red, components.green, components.blue)
        let lightness = (highest + lowest) / 2
        let spread = highest - lowest
        guard spread > 0 else {
            return (hue: 0, saturation: 0, lightness: lightness)
        }
        let saturation = spread / (1 - abs(2 * lightness - 1))
        var hue: Double
        if highest == components.red {
            hue = ((components.green - components.blue) / spread).truncatingRemainder(dividingBy: 6)
        } else if highest == components.green {
            hue = (components.blue - components.red) / spread + 2
        } else {
            hue = (components.red - components.green) / spread + 4
        }
        hue *= 60
        if hue < 0 {
            hue += 360
        }
        return (hue: hue, saturation: min(saturation, 1), lightness: lightness)
    }

    static func fromHSL(hue: Double, saturation: Double, lightness: Double) -> String {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let huePart = hue / 60
        let second = chroma * (1 - abs(huePart.truncatingRemainder(dividingBy: 2) - 1))
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        switch huePart {
        case 0..<1:
            (red, green, blue) = (chroma, second, 0)
        case 1..<2:
            (red, green, blue) = (second, chroma, 0)
        case 2..<3:
            (red, green, blue) = (0, chroma, second)
        case 3..<4:
            (red, green, blue) = (0, second, chroma)
        case 4..<5:
            (red, green, blue) = (second, 0, chroma)
        default:
            (red, green, blue) = (chroma, 0, second)
        }
        let lift = lightness - chroma / 2
        return hexString(red: red + lift, green: green + lift, blue: blue + lift)
    }

    static func hexString(red: Double, green: Double, blue: Double) -> String {
        let redByte = Int((min(max(red, 0), 1) * 255).rounded())
        let greenByte = Int((min(max(green, 0), 1) * 255).rounded())
        let blueByte = Int((min(max(blue, 0), 1) * 255).rounded())
        return String(format: "#%02X%02X%02X", redByte, greenByte, blueByte)
    }
}

/// What is behind a widget's foreground in one mode: the widget's own background and any fill's
/// sea, as "#RRGGBB". Empty for the system background, where system colours stay.
struct WidgetSurfaceColors: Equatable, Sendable {
    let hexes: [String]

    static let system = WidgetSurfaceColors(hexes: [])

    var isCustom: Bool {
        return !hexes.isEmpty
    }

    /// The ink for text and symbols without a colour of their own; nil over the system
    /// background.
    var inkHex: String? {
        guard isCustom else {
            return nil
        }
        return SidekickWidgetInk.inkHex(over: hexes)
    }

    /// The surfaces a derived foreground must read over: these, or the system background.
    func readableOver(isDark: Bool) -> [String] {
        if isCustom {
            return hexes
        }
        return [isDark ? SidekickWidgetInk.systemDarkBackgroundHex : SidekickWidgetInk.systemLightBackgroundHex]
    }

    /// A foreground colour in this mode: the light one; in dark mode the dark one given, else the
    /// light one made readable over these surfaces. Nil without a light colour.
    func foregroundHex(lightHex: String?, darkHex: String?, isDark: Bool, minimumContrast: Double) -> String? {
        guard let lightHex else {
            return nil
        }
        guard isDark else {
            return lightHex
        }
        if let darkHex {
            return darkHex
        }
        return SidekickWidgetInk.readableHex(lightHex, over: readableOver(isDark: true), minimumContrast: minimumContrast)
    }
}
