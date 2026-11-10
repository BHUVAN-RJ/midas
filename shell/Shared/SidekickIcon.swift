import SwiftUI

// Compiled into both the app and the widget extension (shell/project.yml): a Sidekick's icon is
// the same on the home grid and in a widget folder (founder, 2026-10-11). Every tile has a light
// and a dark variant and follows the phone's appearance (founder, 2026-10-31; docs/ICONS.md).

/// Artwork the shell draws itself for a Sidekick, instead of an SF Symbol on a colour.
/// SF Symbols may not be used in app icons or logos (SF Symbols licence), so chosen icons are
/// drawn from scratch here.
enum SidekickArtwork: Equatable {
    /// Reminders, "W2" (founder, 2026-10-10): two reminder rows on white, the first ticked in green.
    case remindersList
    /// care-reminders, "2 · Size by urgency" (founder, 2026-10-12;
    /// docs/mockups/care-reminders-icon-2026-10-12.html): the home's tiles in miniature, the most
    /// urgent one big and teal with a white bell.
    case careUrgencyTiles
    /// jess, the written "Jess" in Caveat Bold (founder, 2026-10-22): the `JessTile` image, light and
    /// dark. jess's one icon everywhere it shows (founder, 2026-10-26), never the catalog's symbol.
    case jessWord
    /// Make, the written "Make" (K1, founder 2026-10-23): the `MakeTile` image, light and dark. Same
    /// rule as jess (founder, 2026-10-26): the tile everywhere, never the catalog's `plus`.
    case makeWord
    /// Water (hydration), "D · Glass" (founder, 2026-10-26; docs/mockups/water-icon-2026-10-26.html):
    /// an ink tumbler on sand with Water's sea inside, a slow wave on top.
    case waterGlass
    /// Money, "C · Wallet" (founder, 2026-11-09; docs/mockups/money-icon-options-2026-11-09.html): an
    /// ink wallet with a green bill standing out of it, tuned to read at 29 pt (`MoneyWalletArtwork`).
    case moneyWallet

    static func artwork(forSidekickId sidekickId: String) -> SidekickArtwork? {
        switch sidekickId {
        case "jess":
            return .jessWord
        case "make":
            return .makeWord
        case "reminders":
            return .remindersList
        case "care-reminders":
            return .careUrgencyTiles
        case "hydration":
            return .waterGlass
        case "money":
            return .moneyWallet
        default:
            return nil
        }
    }
}

/// What one Sidekick icon shows.
enum SidekickIconContent: Equatable {
    case artwork(SidekickArtwork)
    /// The catalog's symbol on its colour; `darkBackgroundHex` is the manifest's
    /// `icon.backgroundDark`, nil when it has none (then one is derived, `SymbolTileColors`).
    case symbol(name: String, backgroundHex: String, darkBackgroundHex: String? = nil)

    static func content(for sidekick: SidekickEntry) -> SidekickIconContent {
        if let artwork = SidekickArtwork.artwork(forSidekickId: sidekick.id) {
            return .artwork(artwork)
        }
        return .symbol(name: sidekick.symbolName, backgroundHex: sidekick.backgroundHex, darkBackgroundHex: sidekick.backgroundDarkHex)
    }
}

/// The background of a symbol tile in each appearance. Dark: the manifest's own dark colour, or,
/// for a manifest without one, the light colour's hue made deep (as a widget's derived fill).
enum SymbolTileColors {
    static func backgroundHex(lightHex: String, darkHex: String?, isDark: Bool) -> String {
        guard isDark else {
            return lightHex
        }
        if let darkHex, SidekickColor.rgbComponents(fromHex: darkHex) != nil {
            return darkHex
        }
        return SidekickWidgetInk.darkFillHex(fromLight: lightHex)
    }
}

enum SidekickIconShape {
    /// iOS app icons round their corners at about 22.5% of the side.
    static let cornerRatio: CGFloat = 0.225
}

/// jess's tile image, in Shared.xcassets so the widget extension has it too
/// (`shell/icon-source/jess-tile.py`, README there).
enum JessTileArtwork {
    static let imageName = "JessTile"
}

/// Make's tile image, in Shared.xcassets with jess's (`shell/icon-source/make-tile.py`).
enum MakeTileArtwork {
    static let imageName = "MakeTile"
}

/// Colours of the Reminders "W2" icon, on a 100-unit canvas: white by day; at night a dark tile
/// with light rows and iOS's dark-mode green.
enum RemindersListArtwork {
    static let tileHex = "#FFFFFF"
    static let doneHex = "#2FA65A"
    static let rowHex = "#3A3A3C"
    static let darkTileHex = "#1C1C1E"
    static let darkDoneHex = "#30D158"
    static let darkRowHex = "#E5E5EA"

    static func colors(isDark: Bool) -> (tile: String, done: String, row: String) {
        if isDark {
            return (darkTileHex, darkDoneHex, darkRowHex)
        }
        return (tileHex, doneHex, rowHex)
    }
}

/// Colours and shapes of the Water "Glass" icon, on a 100-unit canvas. Colours are Water's Tide
/// colours (sidekicks/hydration/index.html): sand, sea, ink.
enum WaterGlassArtwork {
    static let sandHex = "#F4EEE3"
    static let seaHex = "#9CCFD3"
    static let inkHex = "#24343A"
    /// Water's night Tide (the page's dark mode and its widget's dark colours)
    static let darkSandHex = "#0E1A1E"
    static let darkSeaHex = "#2A6970"
    static let darkInkHex = "#E3EEEF"

    static func colors(isDark: Bool) -> (sand: String, sea: String, ink: String) {
        if isDark {
            return (darkSandHex, darkSeaHex, darkInkHex)
        }
        return (sandHex, seaHex, inkHex)
    }
    static let outlineWidth: CGFloat = 5
    /// Where the sea stands in the glass: the wave's midline
    static let seaLevel: CGFloat = 50

    /// The tumbler: wider at the rim (y 24) than at the base (y 84), base corners rounded
    static func glassPath() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 30, y: 24))
        path.addLine(to: CGPoint(x: 70, y: 24))
        path.addLine(to: CGPoint(x: 65, y: 80))
        path.addQuadCurve(to: CGPoint(x: 60, y: 84), control: CGPoint(x: 64.5, y: 84))
        path.addLine(to: CGPoint(x: 40, y: 84))
        path.addQuadCurve(to: CGPoint(x: 35, y: 80), control: CGPoint(x: 35.5, y: 84))
        path.closeSubpath()
        return path
    }

    /// The sea from `seaLevel` down, one slow wave across its top (crest 5 up, trough 5 down)
    static func seaPath() -> Path {
        let crest = seaLevel - 5
        let trough = seaLevel + 5
        var path = Path()
        path.move(to: CGPoint(x: 0, y: seaLevel))
        path.addCurve(to: CGPoint(x: 50, y: seaLevel), control1: CGPoint(x: 17, y: crest), control2: CGPoint(x: 33, y: crest))
        // the SVG's "S" mirrors the last control point: (67, seaLevel + 5)
        path.addCurve(to: CGPoint(x: 100, y: seaLevel), control1: CGPoint(x: 67, y: trough), control2: CGPoint(x: 83, y: trough))
        path.addLine(to: CGPoint(x: 100, y: 100))
        path.addLine(to: CGPoint(x: 0, y: 100))
        path.closeSubpath()
        return path
    }
}

/// Colours and shapes of the Money "Wallet" icon, on a 100-unit canvas. Concept C from
/// docs/mockups/money-icon-options-2026-11-09.html, tuned for 29 pt (founder, 2026-11-09: "lets go
/// with C"): no ink outlines and no clasp dot, a bigger bill standing higher out of the wallet, and
/// a strip of tile colour between bill and wallet so they stay apart. Colours are Money's own
/// (sidekicks/money/index.html): its ink, and the Groceries green pair (deeper by day, brighter at
/// night, so the bill keeps at least 3:1 against the tile in both).
enum MoneyWalletArtwork {
    static let tileHex = "#F3F1EA"
    static let walletHex = "#101210"
    static let billHex = "#2E9E5B"
    /// Money at night: light ink on near-black
    static let darkTileHex = "#141614"
    static let darkWalletHex = "#F4F5F2"
    static let darkBillHex = "#4CC97A"

    static func colors(isDark: Bool) -> (tile: String, wallet: String, bill: String) {
        if isDark {
            return (darkTileHex, darkWalletHex, darkBillHex)
        }
        return (tileHex, walletHex, billHex)
    }

    /// The bill before its tilt; it stands from y 14 down behind the wallet
    static let billRect = CGRect(x: 22, y: 14, width: 56, height: 38)
    static let billCornerRadius: CGFloat = 4
    /// Tilted back a little, about its centre, as in the mockup
    static let billTiltDegrees: CGFloat = -8
    static let walletRect = CGRect(x: 14, y: 40, width: 72, height: 48)
    static let walletCornerRadius: CGFloat = 12
    /// Tile colour around the wallet, cut out of the bill where they meet
    static let gapWidth: CGFloat = 4
    /// The clasp tab, sticking out past the wallet's right side
    static let tabRect = CGRect(x: 56, y: 53, width: 36, height: 24)
    /// The tab's wallet-coloured rim; inside it the slot shows the tile colour
    static let tabRimWidth: CGFloat = 5

    static func billPath() -> Path {
        let flatBill = Path(roundedRect: billRect, cornerRadius: billCornerRadius, style: .continuous)
        let centre = CGPoint(x: billRect.midX, y: billRect.midY)
        // Rotate about the bill's centre: move the centre to the origin, turn, move it back
        let toOrigin = CGAffineTransform(translationX: -centre.x, y: -centre.y)
        let turn = CGAffineTransform(rotationAngle: billTiltDegrees * .pi / 180)
        let back = CGAffineTransform(translationX: centre.x, y: centre.y)
        let tilt = toOrigin.concatenating(turn).concatenating(back)
        return flatBill.applying(tilt)
    }

    static func gapPath() -> Path {
        let outerRect = walletRect.insetBy(dx: -gapWidth, dy: -gapWidth)
        return Path(roundedRect: outerRect, cornerRadius: walletCornerRadius + gapWidth, style: .continuous)
    }

    static func walletPath() -> Path {
        return Path(roundedRect: walletRect, cornerRadius: walletCornerRadius, style: .continuous)
    }

    static func tabPath() -> Path {
        return Path(roundedRect: tabRect, cornerRadius: tabRect.height / 2, style: .continuous)
    }

    static func slotRect() -> CGRect {
        return tabRect.insetBy(dx: tabRimWidth, dy: tabRimWidth)
    }

    static func slotPath() -> Path {
        let slot = slotRect()
        return Path(roundedRect: slot, cornerRadius: slot.height / 2, style: .continuous)
    }
}

/// Colours and tiles of the care-reminders "Size by urgency" icon, on the mockup's 1024-unit
/// canvas. Colours are the Sidekick's list colours: Teal, Apricot, Sage, Lavender, Butter, Clay.
enum CareUrgencyArtwork {
    static let backgroundHex = "#FAF8F5"
    static let bellHex = "#FFFFFF"
    /// At night the paper goes dark; the list-colour tiles and the white bell stay.
    static let darkBackgroundHex = "#1F1D1B"

    static func background(isDark: Bool) -> String {
        return isDark ? darkBackgroundHex : backgroundHex
    }

    struct Tile: Equatable {
        let rect: CGRect
        let cornerRadius: CGFloat
        let hex: String
    }

    static let tiles: [Tile] = [
        Tile(rect: CGRect(x: 140, y: 140, width: 744, height: 420), cornerRadius: 100, hex: "#0F6E6E"),
        Tile(rect: CGRect(x: 140, y: 604, width: 420, height: 280), cornerRadius: 80, hex: "#FFB86B"),
        Tile(rect: CGRect(x: 604, y: 604, width: 130, height: 130), cornerRadius: 40, hex: "#9CAF88"),
        Tile(rect: CGRect(x: 754, y: 604, width: 130, height: 130), cornerRadius: 40, hex: "#C9B3FF"),
        Tile(rect: CGRect(x: 604, y: 754, width: 130, height: 130), cornerRadius: 40, hex: "#FFE48A"),
        Tile(rect: CGRect(x: 754, y: 754, width: 130, height: 130), cornerRadius: 40, hex: "#D9805F"),
    ]

    /// Where the bell (drawn on a 256-unit grid) sits in the big tile: translate(210 210) scale(1.09375)
    static let bellOrigin = CGPoint(x: 210, y: 210)
    static let bellScale: CGFloat = 1.09375
}

struct SidekickIconView: View {
    let content: SidekickIconContent
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * SidekickIconShape.cornerRatio, style: .continuous)
        Group {
            switch content {
            case .artwork(.remindersList):
                RemindersListIcon()
            case .artwork(.careUrgencyTiles):
                CareUrgencyIcon()
            case .artwork(.waterGlass):
                WaterGlassIcon()
            case .artwork(.moneyWallet):
                MoneyWalletIcon()
            case .artwork(.jessWord):
                Image(JessTileArtwork.imageName)
                    .resizable()
                    .interpolation(.high)
            case .artwork(.makeWord):
                Image(MakeTileArtwork.imageName)
                    .resizable()
                    .interpolation(.high)
            case .symbol(let symbolName, let backgroundHex, let darkBackgroundHex):
                ZStack {
                    SidekickColor.color(fromHex: SymbolTileColors.backgroundHex(lightHex: backgroundHex, darkHex: darkBackgroundHex,
                                                                               isDark: colorScheme == .dark))
                    Image(systemName: symbolName)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        // A hairline edge, so a white icon still has a shape on a light background (a light one
        // on a dark background at night)
        .overlay(shape.strokeBorder(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08), lineWidth: 0.5))
    }
}

/// The W2 artwork, drawn on a 100-unit canvas scaled to the tile.
struct RemindersListIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 100
            context.scaleBy(x: scale, y: scale)
            drawArtwork(in: &context)
        }
    }

    private func drawArtwork(in context: inout GraphicsContext) {
        let colors = RemindersListArtwork.colors(isDark: colorScheme == .dark)
        let tileColor = SidekickColor.color(fromHex: colors.tile)
        let doneColor = SidekickColor.color(fromHex: colors.done)
        let rowColor = SidekickColor.color(fromHex: colors.row)

        context.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 100)), with: .color(tileColor))

        // First row: done (filled green circle with a white tick), its line faded
        let doneCircle = Path(ellipseIn: CGRect(x: 21.7, y: 26.9, width: 18, height: 18))
        context.fill(doneCircle, with: .color(doneColor))
        var tick = Path()
        tick.move(to: CGPoint(x: 26.3, y: 36.2))
        tick.addLine(to: CGPoint(x: 29.7, y: 39.5))
        tick.addLine(to: CGPoint(x: 35.6, y: 33.0))
        let tickStyle = StrokeStyle(lineWidth: 3.3, lineCap: .round, lineJoin: .round)
        context.stroke(tick, with: .color(.white), style: tickStyle)
        let fadedLine = Path(roundedRect: CGRect(x: 46.1, y: 32, width: 28.3, height: 7.7), cornerRadius: 3.85)
        context.fill(fadedLine, with: .color(rowColor.opacity(0.4)))

        // Second row: still to do (open circle), its line solid
        let openCircle = Path(ellipseIn: CGRect(x: 23.5, y: 56.9, width: 14.4, height: 14.4))
        context.stroke(openCircle, with: .color(rowColor), lineWidth: 3.6)
        let solidLine = Path(roundedRect: CGRect(x: 46.1, y: 60.3, width: 28.3, height: 7.7), cornerRadius: 3.85)
        context.fill(solidLine, with: .color(rowColor))
    }
}

/// The Water "Glass" artwork, drawn on a 100-unit canvas scaled to the tile.
struct WaterGlassIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 100
            context.scaleBy(x: scale, y: scale)
            drawArtwork(in: &context)
        }
    }

    private func drawArtwork(in context: inout GraphicsContext) {
        let colors = WaterGlassArtwork.colors(isDark: colorScheme == .dark)
        let sand = SidekickColor.color(fromHex: colors.sand)
        let sea = SidekickColor.color(fromHex: colors.sea)
        let ink = SidekickColor.color(fromHex: colors.ink)
        let glass = WaterGlassArtwork.glassPath()

        context.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 100)), with: .color(sand))

        // The sea only shows inside the glass
        var insideGlass = context
        insideGlass.clip(to: glass)
        insideGlass.fill(WaterGlassArtwork.seaPath(), with: .color(sea))

        let outlineStyle = StrokeStyle(lineWidth: WaterGlassArtwork.outlineWidth, lineCap: .round, lineJoin: .round)
        context.stroke(glass, with: .color(ink), style: outlineStyle)
    }
}

/// The Money "Wallet" artwork, drawn on a 100-unit canvas scaled to the tile. Flat fills only, so
/// nothing thins out at 29 pt.
struct MoneyWalletIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 100
            context.scaleBy(x: scale, y: scale)
            drawArtwork(in: &context)
        }
    }

    private func drawArtwork(in context: inout GraphicsContext) {
        let colors = MoneyWalletArtwork.colors(isDark: colorScheme == .dark)
        let tile = SidekickColor.color(fromHex: colors.tile)
        let wallet = SidekickColor.color(fromHex: colors.wallet)
        let bill = SidekickColor.color(fromHex: colors.bill)

        context.fill(Path(CGRect(x: 0, y: 0, width: 100, height: 100)), with: .color(tile))
        context.fill(MoneyWalletArtwork.billPath(), with: .color(bill))
        // Tile colour drawn over the bill's lower edge before the wallet: a clean gap between them
        context.fill(MoneyWalletArtwork.gapPath(), with: .color(tile))
        context.fill(MoneyWalletArtwork.walletPath(), with: .color(wallet))
        context.fill(MoneyWalletArtwork.tabPath(), with: .color(wallet))
        context.fill(MoneyWalletArtwork.slotPath(), with: .color(tile))
    }
}

/// The care-reminders "Size by urgency" artwork, drawn on the mockup's 1024-unit canvas.
struct CareUrgencyIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            context.scaleBy(x: scale, y: scale)
            drawArtwork(in: &context)
        }
    }

    private func drawArtwork(in context: inout GraphicsContext) {
        let background = SidekickColor.color(fromHex: CareUrgencyArtwork.background(isDark: colorScheme == .dark))
        context.fill(Path(CGRect(x: 0, y: 0, width: 1024, height: 1024)), with: .color(background))
        for tile in CareUrgencyArtwork.tiles {
            let tilePath = Path(roundedRect: tile.rect, cornerRadius: tile.cornerRadius, style: .continuous)
            context.fill(tilePath, with: .color(SidekickColor.color(fromHex: tile.hex)))
        }
        var bellContext = context
        bellContext.translateBy(x: CareUrgencyArtwork.bellOrigin.x, y: CareUrgencyArtwork.bellOrigin.y)
        bellContext.scaleBy(x: CareUrgencyArtwork.bellScale, y: CareUrgencyArtwork.bellScale)
        let bellColor = SidekickColor.color(fromHex: CareUrgencyArtwork.bellHex)
        // Even-odd leaves the gap between the bell and its clapper open, as in the mockup
        bellContext.fill(Self.bellPath(), with: .color(bellColor), style: FillStyle(eoFill: true))
    }

    /// The mockup's bell (the page's own bell icon) on a 256-unit grid. Its SVG arcs are written
    /// as relative arcs: angles are in this y-down space, so a negative delta turns towards the top.
    static func bellPath() -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 221.8, y: 175.94))
        path.addCurve(to: CGPoint(x: 208, y: 104), control1: CGPoint(x: 216.25, y: 166.38), control2: CGPoint(x: 208, y: 139.33))
        // Dome: right to left over the top
        path.addRelativeArc(center: CGPoint(x: 128, y: 104), radius: 80, startAngle: .degrees(0), delta: .degrees(-180))
        path.addCurve(to: CGPoint(x: 34.19, y: 175.94), control1: CGPoint(x: 48, y: 139.34), control2: CGPoint(x: 39.74, y: 166.38))
        // Bottom-left corner
        path.addRelativeArc(center: CGPoint(x: 48, y: 184), radius: 16, startAngle: .degrees(210.27), delta: .degrees(-120.27))
        path.addLine(to: CGPoint(x: 88.81, y: 200))
        // Clapper: a cap hanging below the rim
        path.addRelativeArc(center: CGPoint(x: 128, y: 192), radius: 40, startAngle: .degrees(168.46), delta: .degrees(-156.92))
        path.addLine(to: CGPoint(x: 208, y: 200))
        // Bottom-right corner
        path.addRelativeArc(center: CGPoint(x: 208, y: 184), radius: 16, startAngle: .degrees(90), delta: .degrees(-120.27))
        path.closeSubpath()
        // The gap inside the clapper
        path.move(to: CGPoint(x: 128, y: 216))
        path.addRelativeArc(center: CGPoint(x: 128, y: 192), radius: 24, startAngle: .degrees(90), delta: .degrees(70.53))
        path.addLine(to: CGPoint(x: 150.62, y: 200))
        path.addRelativeArc(center: CGPoint(x: 128, y: 192), radius: 24, startAngle: .degrees(19.47), delta: .degrees(70.53))
        path.closeSubpath()
        return path
    }
}
