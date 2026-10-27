import SwiftUI

// Compiled into both the app and the widget extension (shell/project.yml): a Sidekick's icon is
// the same on the home grid and in a widget folder (founder, 2026-10-11).

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
        default:
            return nil
        }
    }
}

/// What one Sidekick icon shows.
enum SidekickIconContent: Equatable {
    case artwork(SidekickArtwork)
    case symbol(name: String, backgroundHex: String)

    static func content(for sidekick: SidekickEntry) -> SidekickIconContent {
        if let artwork = SidekickArtwork.artwork(forSidekickId: sidekick.id) {
            return .artwork(artwork)
        }
        return .symbol(name: sidekick.symbolName, backgroundHex: sidekick.backgroundHex)
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

/// Colours of the Reminders "W2" icon, on a 100-unit canvas.
enum RemindersListArtwork {
    static let tileHex = "#FFFFFF"
    static let doneHex = "#2FA65A"
    static let rowHex = "#3A3A3C"
}

/// Colours and tiles of the care-reminders "Size by urgency" icon, on the mockup's 1024-unit
/// canvas. Colours are the Sidekick's list colours: Teal, Apricot, Sage, Lavender, Butter, Clay.
enum CareUrgencyArtwork {
    static let backgroundHex = "#FAF8F5"
    static let bellHex = "#FFFFFF"

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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * SidekickIconShape.cornerRatio, style: .continuous)
        Group {
            switch content {
            case .artwork(.remindersList):
                RemindersListIcon()
            case .artwork(.careUrgencyTiles):
                CareUrgencyIcon()
            case .artwork(.jessWord):
                Image(JessTileArtwork.imageName)
                    .resizable()
                    .interpolation(.high)
            case .artwork(.makeWord):
                Image(MakeTileArtwork.imageName)
                    .resizable()
                    .interpolation(.high)
            case .symbol(let symbolName, let backgroundHex):
                ZStack {
                    SidekickColor.color(fromHex: backgroundHex)
                    Image(systemName: symbolName)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        // A hairline edge, so a white icon still has a shape on a light background
        .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
    }
}

/// The W2 artwork, drawn on a 100-unit canvas scaled to the tile.
struct RemindersListIcon: View {
    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 100
            context.scaleBy(x: scale, y: scale)
            drawArtwork(in: &context)
        }
    }

    private func drawArtwork(in context: inout GraphicsContext) {
        let tileColor = SidekickColor.color(fromHex: RemindersListArtwork.tileHex)
        let doneColor = SidekickColor.color(fromHex: RemindersListArtwork.doneHex)
        let rowColor = SidekickColor.color(fromHex: RemindersListArtwork.rowHex)

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

/// The care-reminders "Size by urgency" artwork, drawn on the mockup's 1024-unit canvas.
struct CareUrgencyIcon: View {
    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 1024
            context.scaleBy(x: scale, y: scale)
            drawArtwork(in: &context)
        }
    }

    private func drawArtwork(in context: inout GraphicsContext) {
        let background = SidekickColor.color(fromHex: CareUrgencyArtwork.backgroundHex)
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
