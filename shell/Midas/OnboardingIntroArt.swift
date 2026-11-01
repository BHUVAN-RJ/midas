import SwiftUI

// The intro's icons (founder, 2026-10-31; docs/briefs/onboarding-build.md sections 2 and 6), ported
// from the mockup's canvas code. Before: grey, flat, chunky clip-art. After: each app's Midas tile
// colour with its mark in two layers (WWDC25 "Say hello to the new look of app icons": bold,
// rounded, layered). These icons exist only in the intro.

/// The grey of "before", per appearance: one dull tile, one dull mark.
struct OnboardingGrey {
    let tile: Color
    let mark: Color

    static func forScheme(_ scheme: ColorScheme) -> OnboardingGrey {
        if scheme == .dark {
            return OnboardingGrey(tile: SidekickColor.color(fromHex: "#2A2A2A"), mark: SidekickColor.color(fromHex: "#6A6A6A"))
        }
        return OnboardingGrey(tile: SidekickColor.color(fromHex: "#E4E4E4"), mark: SidekickColor.color(fromHex: "#9A9A9A"))
    }
}

enum OnboardingIconArt {
    /// The second layer of each mark: the mark colour at this opacity.
    static let glassOpacity: CGFloat = 0.42
    /// Drawn images are this much bigger than the tile, so the shadow fits.
    static let polishedSpan: CGFloat = 1.5

    // MARK: Before

    /// A plain rounded square (corner 16%) with a chunky filled glyph, centred on (0, 0).
    static func drawPlain(_ glyph: OnboardingGlyph, in context: GraphicsContext, unit: CGFloat, grey: OnboardingGrey) {
        let tile = Path(roundedRect: CGRect(x: -unit / 2, y: -unit / 2, width: unit, height: unit), cornerRadius: unit * 0.16)
        context.fill(tile, with: .color(grey.tile))
        let shading = GraphicsContext.Shading.color(grey.mark)
        let thick = StrokeStyle(lineWidth: unit * 0.075, lineCap: .round, lineJoin: .round)
        switch glyph {
        case .bell:
            var bell = Path()
            bell.move(to: CGPoint(x: -0.25 * unit, y: 0.14 * unit))
            bell.addQuadCurve(to: CGPoint(x: -0.19 * unit, y: -0.03 * unit), control: CGPoint(x: -0.19 * unit, y: 0.08 * unit))
            bell.addArc(center: CGPoint(x: 0, y: -0.03 * unit), radius: 0.19 * unit, startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
            bell.addQuadCurve(to: CGPoint(x: 0.25 * unit, y: 0.14 * unit), control: CGPoint(x: 0.19 * unit, y: 0.08 * unit))
            bell.closeSubpath()
            context.fill(bell, with: shading)
            context.fill(circle(x: 0, y: 0.2 * unit, radius: 0.055 * unit), with: shading)
        case .drop:
            context.fill(dropPath(unit: unit, tip: -0.28, radius: 0.2, centreY: 0.07, shoulder: 0.08, side: -0.04, top: -0.15), with: shading)
        case .ring:
            context.stroke(circle(x: 0, y: 0, radius: 0.21 * unit), with: shading, lineWidth: unit * 0.1)
        case .card:
            let dollar = Text("$").font(.system(size: 0.42 * unit, weight: .heavy)).foregroundStyle(grey.mark)
            context.draw(dollar, at: CGPoint(x: 0, y: 0.02 * unit))
        case .check:
            let box = Path(roundedRect: CGRect(x: -0.22 * unit, y: -0.22 * unit, width: 0.44 * unit, height: 0.44 * unit), cornerRadius: 0.09 * unit)
            context.stroke(box, with: shading, style: thick)
            var tick = Path()
            tick.move(to: CGPoint(x: -0.1 * unit, y: 0))
            tick.addLine(to: CGPoint(x: -0.02 * unit, y: 0.08 * unit))
            tick.addLine(to: CGPoint(x: 0.12 * unit, y: -0.08 * unit))
            context.stroke(tick, with: shading, style: thick)
        case .book:
            let book = Path(roundedRect: CGRect(x: -0.2 * unit, y: -0.24 * unit, width: 0.4 * unit, height: 0.48 * unit), cornerRadius: 0.04 * unit)
            context.fill(book, with: shading)
        case .pill:
            let capsule = Path(roundedRect: CGRect(x: -0.27 * unit, y: -0.11 * unit, width: 0.54 * unit, height: 0.22 * unit), cornerRadius: 0.11 * unit)
            let tilt = CGAffineTransform(rotationAngle: -.pi / 4)
            context.fill(capsule.applying(tilt), with: shading)
        case .moon:
            context.fill(circle(x: 0, y: 0, radius: 0.24 * unit), with: shading)
            context.fill(circle(x: 0.11 * unit, y: -0.09 * unit, radius: 0.2 * unit), with: .color(grey.tile))
        }
    }

    // MARK: After

    /// iOS continuous-corner tile (corner 22.5%): a superellipse with exponent 5 matches it closely.
    static func superellipse(half: CGFloat) -> Path {
        let exponent: CGFloat = 5
        let segments = 120
        var path = Path()
        for segment in 0...segments {
            let angle = CGFloat(segment) / CGFloat(segments) * 2 * .pi
            let cosine = cos(angle)
            let sine = sin(angle)
            let x = half * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / exponent)
            let y = half * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / exponent)
            if segment == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        path.closeSubpath()
        return path
    }

    /// A Midas tile with its two-layer mark, centred on (0, 0), `unit` wide.
    static func drawPolished(_ glyph: OnboardingGlyph, in context: GraphicsContext, unit: CGFloat, tile: Color, mark: Color, isWhiteTile: Bool) {
        let half = unit / 2
        let tileShape = superellipse(half: half)

        // Background layer: flat colour (DESIGN.md rejects gradients), a soft shadow under it
        context.drawLayer { shadowed in
            shadowed.addFilter(.shadow(color: .black.opacity(0.2), radius: unit * 0.06, x: 0, y: unit * 0.04))
            shadowed.fill(tileShape, with: .color(tile))
        }

        // Foreground layer floats a little above the background: it casts a small shadow onto it
        context.drawLayer { clipped in
            clipped.clip(to: tileShape)
            clipped.addFilter(.shadow(color: .black.opacity(0.22), radius: unit * 0.025, x: 0, y: unit * 0.022))
            clipped.drawLayer { markLayer in
                drawMark(glyph, in: markLayer, unit: unit, mark: mark)
            }
        }

        strokeGlassEdge(in: context, half: half, unit: unit)
        if isWhiteTile {
            // A hairline so a white tile still has a shape on white (SidekickIconView does the same)
            context.stroke(superellipse(half: half - unit * 0.002), with: .color(.black.opacity(0.1)), lineWidth: unit * 0.008)
        }
    }

    /// The mark: glass layer, solid layer, strokes and cut-outs, then a sheen across the top.
    private static func drawMark(_ glyph: OnboardingGlyph, in context: GraphicsContext, unit: CGFloat, mark: Color) {
        let layers = markLayers(glyph, unit: unit)
        context.fill(layers.glass, with: .color(mark.opacity(glassOpacity)))
        context.fill(layers.solid, with: .color(mark))
        drawMarkExtras(glyph, in: context, unit: unit, mark: mark)

        // Glass light on the mark: a sheen across the top of every shape, lit from above
        var sheenContext = context
        sheenContext.blendMode = .sourceAtop
        let sheen = Gradient(colors: [.white.opacity(0.38), .white.opacity(0)])
        let area = Path(CGRect(x: -unit / 2, y: -unit / 2, width: unit, height: unit))
        sheenContext.fill(area, with: .linearGradient(sheen, startPoint: CGPoint(x: 0, y: -0.3 * unit), endPoint: CGPoint(x: 0, y: 0.1 * unit)))
    }

    /// The tile's glass edge: light caught at the top-left and, weaker, at the bottom-right.
    private static func strokeGlassEdge(in context: GraphicsContext, half: CGFloat, unit: CGFloat) {
        var edgeContext = context
        edgeContext.clip(to: superellipse(half: half))
        let edge = Gradient(stops: [
            Gradient.Stop(color: .white.opacity(0.85), location: 0),
            Gradient.Stop(color: .white.opacity(0.10), location: 0.32),
            Gradient.Stop(color: .white.opacity(0), location: 0.68),
            Gradient.Stop(color: .white.opacity(0.45), location: 1),
        ])
        let shading = GraphicsContext.Shading.linearGradient(edge, startPoint: CGPoint(x: -half, y: -half), endPoint: CGPoint(x: half, y: half))
        edgeContext.stroke(superellipse(half: half - unit * 0.006), with: shading, lineWidth: unit * 0.022)
    }

    /// Each mark's solid shape and its glass second layer.
    static func markLayers(_ glyph: OnboardingGlyph, unit: CGFloat) -> (solid: Path, glass: Path) {
        var solid = Path()
        var glass = Path()
        switch glyph {
        case .bell:
            // Bell, with the notification badge as the glass layer
            solid.move(to: CGPoint(x: -0.21 * unit, y: 0.13 * unit))
            solid.addQuadCurve(to: CGPoint(x: -0.16 * unit, y: -0.02 * unit), control: CGPoint(x: -0.16 * unit, y: 0.08 * unit))
            solid.addArc(center: CGPoint(x: 0, y: -0.03 * unit), radius: 0.16 * unit, startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
            solid.addQuadCurve(to: CGPoint(x: 0.21 * unit, y: 0.13 * unit), control: CGPoint(x: 0.16 * unit, y: 0.08 * unit))
            solid.addQuadCurve(to: CGPoint(x: 0.18 * unit, y: 0.17 * unit), control: CGPoint(x: 0.225 * unit, y: 0.17 * unit))
            solid.addLine(to: CGPoint(x: -0.18 * unit, y: 0.17 * unit))
            solid.addQuadCurve(to: CGPoint(x: -0.21 * unit, y: 0.13 * unit), control: CGPoint(x: -0.225 * unit, y: 0.17 * unit))
            solid.closeSubpath()
            solid.move(to: CGPoint(x: 0.06 * unit, y: 0.205 * unit))
            solid.addArc(center: CGPoint(x: 0, y: 0.205 * unit), radius: 0.06 * unit, startAngle: .radians(0), endAngle: .radians(.pi), clockwise: false)
            solid.closeSubpath()
            glass.addPath(circle(x: 0.17 * unit, y: -0.17 * unit, radius: 0.085 * unit))
        case .drop:
            // A drop of glass with water standing in its lower half
            glass = dropPath(unit: unit, tip: -0.27, radius: 0.21, centreY: 0.07, shoulder: 0.09, side: -0.03, top: -0.15)
            solid.move(to: CGPoint(x: -0.205 * unit, y: 0.05 * unit))
            solid.addCurve(to: CGPoint(x: 0.205 * unit, y: 0.03 * unit), control1: CGPoint(x: -0.1 * unit, y: 0), control2: CGPoint(x: 0.1 * unit, y: 0.1 * unit))
            solid.addLine(to: CGPoint(x: 0.21 * unit, y: 0.07 * unit))
            solid.addArc(center: CGPoint(x: 0, y: 0.07 * unit), radius: 0.21 * unit, startAngle: .radians(0), endAngle: .radians(.pi), clockwise: false)
            solid.closeSubpath()
        case .ring:
            // A streak ring: the track in glass, three quarters of it done with round ends
            glass.addArc(center: .zero, radius: 0.23 * unit, startAngle: .radians(0), endAngle: .radians(2 * .pi), clockwise: false)
            glass.addArc(center: .zero, radius: 0.13 * unit, startAngle: .radians(2 * .pi), endAngle: .radians(0), clockwise: true)
            glass.closeSubpath()
            solid.addArc(center: .zero, radius: 0.23 * unit, startAngle: .radians(-.pi / 2), endAngle: .radians(.pi), clockwise: false)
            solid.addArc(center: CGPoint(x: -0.18 * unit, y: 0), radius: 0.05 * unit, startAngle: .radians(.pi), endAngle: .radians(0), clockwise: false)
            solid.addArc(center: .zero, radius: 0.13 * unit, startAngle: .radians(.pi), endAngle: .radians(-.pi / 2), clockwise: true)
            solid.addArc(center: CGPoint(x: 0, y: -0.18 * unit), radius: 0.05 * unit, startAngle: .radians(.pi / 2), endAngle: .radians(-.pi / 2), clockwise: false)
            solid.closeSubpath()
        case .card:
            // Two cards: the back one tilted, in glass
            let back = Path(roundedRect: CGRect(x: -0.22 * unit, y: -0.2 * unit, width: 0.42 * unit, height: 0.27 * unit), cornerRadius: 0.06 * unit)
            glass = back.applying(CGAffineTransform(rotationAngle: -14 * .pi / 180))
            solid = Path(roundedRect: CGRect(x: -0.21 * unit, y: -0.06 * unit, width: 0.44 * unit, height: 0.28 * unit), cornerRadius: 0.06 * unit)
        case .check:
            // A checkbox in glass; the bold tick is a stroke (drawMarkExtras)
            glass = Path(roundedRect: CGRect(x: -0.21 * unit, y: -0.21 * unit, width: 0.42 * unit, height: 0.42 * unit), cornerRadius: 0.11 * unit)
        case .book:
            // An open book: the left page solid, the right page glass
            solid = pagePath(unit: unit, side: -1)
            glass = pagePath(unit: unit, side: 1)
        case .pill:
            // A capsule: one half solid, the other glass
            let tilt = CGAffineTransform(rotationAngle: -.pi / 4)
            var left = Path()
            left.move(to: CGPoint(x: 0, y: -0.105 * unit))
            left.addLine(to: CGPoint(x: -0.17 * unit, y: -0.105 * unit))
            left.addArc(center: CGPoint(x: -0.17 * unit, y: 0), radius: 0.105 * unit, startAngle: .radians(-.pi / 2), endAngle: .radians(.pi / 2), clockwise: true)
            left.addLine(to: CGPoint(x: 0, y: 0.105 * unit))
            left.closeSubpath()
            var right = Path()
            right.move(to: CGPoint(x: 0.01 * unit, y: -0.105 * unit))
            right.addLine(to: CGPoint(x: 0.17 * unit, y: -0.105 * unit))
            right.addArc(center: CGPoint(x: 0.17 * unit, y: 0), radius: 0.105 * unit, startAngle: .radians(-.pi / 2), endAngle: .radians(.pi / 2), clockwise: false)
            right.addLine(to: CGPoint(x: 0.01 * unit, y: 0.105 * unit))
            right.closeSubpath()
            solid = left.applying(tilt)
            glass = right.applying(tilt)
        case .moon:
            // A crescent (cut in drawMarkExtras), two small stars in glass
            solid = circle(x: -0.03 * unit, y: 0.02 * unit, radius: 0.21 * unit)
            glass = moonStars(unit: unit)
        }
        return (solid, glass)
    }

    /// The parts that are strokes or cut-outs, not fills.
    private static func drawMarkExtras(_ glyph: OnboardingGlyph, in context: GraphicsContext, unit: CGFloat, mark: Color) {
        switch glyph {
        case .check:
            var tick = Path()
            tick.move(to: CGPoint(x: -0.1 * unit, y: 0))
            tick.addLine(to: CGPoint(x: -0.025 * unit, y: 0.075 * unit))
            tick.addLine(to: CGPoint(x: 0.12 * unit, y: -0.085 * unit))
            context.stroke(tick, with: .color(mark), style: StrokeStyle(lineWidth: unit * 0.075, lineCap: .round, lineJoin: .round))
        case .moon:
            var cutter = context
            cutter.blendMode = .destinationOut
            cutter.fill(circle(x: 0.07 * unit, y: -0.07 * unit, radius: 0.17 * unit), with: .color(.black))
            // The cut also bit the stars: put them back
            context.fill(moonStars(unit: unit), with: .color(mark.opacity(glassOpacity)))
        case .card:
            // The magnetic stripe, cut out of the front card
            var cutter = context
            cutter.blendMode = .destinationOut
            cutter.fill(Path(CGRect(x: -0.21 * unit, y: 0, width: 0.44 * unit, height: 0.055 * unit)), with: .color(.black))
        default:
            break
        }
    }

    // MARK: Shared shapes

    private static func circle(x: CGFloat, y: CGFloat, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    private static func moonStars(unit: CGFloat) -> Path {
        var stars = Path()
        stars.addPath(circle(x: 0.17 * unit, y: -0.16 * unit, radius: 0.035 * unit))
        stars.addPath(circle(x: 0.215 * unit, y: 0.03 * unit, radius: 0.025 * unit))
        return stars
    }

    /// A drop: tip at `tip`, round bottom of `radius` centred at `centreY` (all in units).
    private static func dropPath(unit: CGFloat, tip: CGFloat, radius: CGFloat, centreY: CGFloat, shoulder: CGFloat, side: CGFloat, top: CGFloat) -> Path {
        var drop = Path()
        drop.move(to: CGPoint(x: 0, y: tip * unit))
        drop.addCurve(to: CGPoint(x: radius * unit, y: centreY * unit), control1: CGPoint(x: shoulder * unit, y: top * unit), control2: CGPoint(x: radius * unit, y: side * unit))
        drop.addArc(center: CGPoint(x: 0, y: centreY * unit), radius: radius * unit, startAngle: .radians(0), endAngle: .radians(.pi), clockwise: false)
        drop.addCurve(to: CGPoint(x: 0, y: tip * unit), control1: CGPoint(x: -radius * unit, y: side * unit), control2: CGPoint(x: -shoulder * unit, y: top * unit))
        drop.closeSubpath()
        return drop
    }

    /// One page of the open book; side -1 is left, 1 is right.
    private static func pagePath(unit: CGFloat, side: CGFloat) -> Path {
        var page = Path()
        page.move(to: CGPoint(x: side * 0.02 * unit, y: -0.14 * unit))
        page.addQuadCurve(to: CGPoint(x: side * 0.24 * unit, y: -0.18 * unit), control: CGPoint(x: side * 0.12 * unit, y: -0.21 * unit))
        page.addQuadCurve(to: CGPoint(x: side * 0.26 * unit, y: -0.15 * unit), control: CGPoint(x: side * 0.26 * unit, y: -0.175 * unit))
        page.addLine(to: CGPoint(x: side * 0.26 * unit, y: 0.15 * unit))
        page.addQuadCurve(to: CGPoint(x: side * 0.02 * unit, y: 0.2 * unit), control: CGPoint(x: side * 0.13 * unit, y: 0.13 * unit))
        page.closeSubpath()
        return page
    }
}

/// The three looks of each icon, drawn once into images and reused every frame.
struct OnboardingIconImages {
    var plain: [Image] = []
    var greyGlass: [Image] = []
    var colour: [Image] = []

    var isReady: Bool {
        plain.count == OnboardingIntroSpec.apps.count
    }

    @MainActor
    static func render(for scheme: ColorScheme, displayScale: CGFloat) -> OnboardingIconImages {
        var images = OnboardingIconImages()
        let grey = OnboardingGrey.forScheme(scheme)
        for app in OnboardingIntroSpec.apps {
            images.plain.append(renderPlain(app, grey: grey, displayScale: displayScale))
            images.greyGlass.append(renderPolished(app, tile: grey.tile, mark: grey.mark, isWhiteTile: false, displayScale: displayScale))
            let tile = SidekickColor.color(fromHex: app.tileHex)
            let mark = SidekickColor.color(fromHex: app.markHex)
            images.colour.append(renderPolished(app, tile: tile, mark: mark, isWhiteTile: app.tileHex == "#FFFFFF", displayScale: displayScale))
        }
        return images
    }

    @MainActor
    private static func renderPlain(_ app: OnboardingIntroApp, grey: OnboardingGrey, displayScale: CGFloat) -> Image {
        let unit = OnboardingIntroSpec.iconSize
        func drawPlainIcon(_ context: inout GraphicsContext, _ size: CGSize) {
            context.translateBy(x: size.width / 2, y: size.height / 2)
            OnboardingIconArt.drawPlain(app.glyph, in: context, unit: unit, grey: grey)
        }
        let canvas = Canvas(renderer: drawPlainIcon).frame(width: unit, height: unit)
        return snapshot(canvas, displayScale: displayScale)
    }

    @MainActor
    private static func renderPolished(_ app: OnboardingIntroApp, tile: Color, mark: Color, isWhiteTile: Bool, displayScale: CGFloat) -> Image {
        let unit = OnboardingIntroSpec.iconSize
        let span = unit * OnboardingIconArt.polishedSpan
        func drawPolishedIcon(_ context: inout GraphicsContext, _ size: CGSize) {
            context.translateBy(x: size.width / 2, y: size.height / 2)
            OnboardingIconArt.drawPolished(app.glyph, in: context, unit: unit, tile: tile, mark: mark, isWhiteTile: isWhiteTile)
        }
        let canvas = Canvas(renderer: drawPolishedIcon).frame(width: span, height: span)
        return snapshot(canvas, displayScale: displayScale)
    }

    @MainActor
    private static func snapshot(_ view: some View, displayScale: CGFloat) -> Image {
        let renderer = ImageRenderer(content: view)
        renderer.scale = displayScale
        guard let image = renderer.uiImage else {
            return Image(systemName: "square")
        }
        return Image(uiImage: image)
    }
}
