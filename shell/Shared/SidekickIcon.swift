import SwiftUI

// Compiled into both the app and the widget extension (shell/project.yml): a Sidekick's icon is
// the same on the home grid and in a widget folder (founder, 2026-10-11).

/// Artwork the shell draws itself for a Sidekick, instead of an SF Symbol on a colour.
/// SF Symbols may not be used in app icons or logos (SF Symbols licence), so chosen icons are
/// drawn from scratch here.
enum SidekickArtwork: Equatable {
    /// Reminders, "W2" (founder, 2026-10-10): two reminder rows on white, the first ticked in green.
    case remindersList

    static func artwork(forSidekickId sidekickId: String) -> SidekickArtwork? {
        switch sidekickId {
        case "reminders":
            return .remindersList
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

/// Colours of the Reminders "W2" icon, on a 100-unit canvas.
enum RemindersListArtwork {
    static let tileHex = "#FFFFFF"
    static let doneHex = "#2FA65A"
    static let rowHex = "#3A3A3C"
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
