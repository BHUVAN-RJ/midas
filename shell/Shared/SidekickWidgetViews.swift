import AppIntents
import SwiftUI
import WidgetKit

// How the Sidekick widget draws its filled pieces (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html). The widget extension shows these views
// (shell/MidasWidgets/SidekickWidget.swift); they live in Shared so the app's tests can draw a
// widget too (the fill renders, hydration plan W4). Nothing here reads records: the app has
// already filled every piece (shell/Midas/SidekickWidgetFiller.swift).

enum SidekickWidgetColors {
    /// White in light mode, #1C1C1E in dark, as Apple's Reminders widget.
    static let background = Color(uiColor: .secondarySystemGroupedBackground)
    static let defaultTint = Color(uiColor: .systemBlue)

    static func color(hex: String?) -> Color? {
        guard let hex else {
            return nil
        }
        return SidekickColor.color(fromHex: hex)
    }

    /// The light colour, or in dark mode the dark one when there is one.
    static func color(lightHex: String?, darkHex: String?, colorScheme: ColorScheme) -> Color? {
        if colorScheme == .dark, let darkHex {
            return color(hex: darkHex)
        }
        return color(hex: lightHex)
    }

    /// A widget's own background in this mode; in dark mode without a dark colour, one derived
    /// from the light colour (founder, 2026-10-27: a single colour from an older page still draws).
    static func backgroundHex(_ background: WidgetBackgroundPiece, colorScheme: ColorScheme) -> String {
        guard colorScheme == .dark else {
            return background.colorHex
        }
        return background.darkColorHex ?? SidekickWidgetInk.darkBackgroundHex(fromLight: background.colorHex)
    }

    /// A fill's sea in this mode, "#RRGGBB"; nil for a fill in the tint without a tint colour.
    static func fillHex(_ fill: WidgetFillPiece, tintHex: String?, colorScheme: ColorScheme) -> String? {
        guard let lightHex = fill.colorHex ?? tintHex else {
            return nil
        }
        guard colorScheme == .dark else {
            return lightHex
        }
        if let darkHex = fill.darkColorHex {
            return darkHex
        }
        return SidekickWidgetInk.darkFillHex(fromLight: lightHex)
    }

    /// What is behind a whole look's foreground: its background (the system one when it has
    /// none) and its edge fill. The system background alone is no custom surface.
    static func surface(of piece: WidgetPiece, tintHex: String?, colorScheme: ColorScheme) -> WidgetSurfaceColors {
        let isDark = colorScheme == .dark
        var hexes: [String] = []
        if let background = SidekickWidgetSurface.background(of: piece) {
            hexes.append(backgroundHex(background, colorScheme: colorScheme))
        }
        if let fill = SidekickWidgetSurface.edgeFill(of: piece) {
            if hexes.isEmpty {
                hexes.append(isDark ? SidekickWidgetInk.systemDarkBackgroundHex : SidekickWidgetInk.systemLightBackgroundHex)
            }
            hexes.append(fillHex(fill, tintHex: tintHex, colorScheme: colorScheme) ?? SidekickWidgetInk.defaultTintHex)
        }
        return WidgetSurfaceColors(hexes: hexes)
    }

    /// The tint in this mode: the description's, kept readable over the surfaces in dark mode.
    static func tintColor(tintHex: String?, surface: WidgetSurfaceColors, colorScheme: ColorScheme) -> Color {
        let isDark = colorScheme == .dark
        let tintInMode = surface.foregroundHex(lightHex: tintHex, darkHex: nil, isDark: isDark, minimumContrast: SidekickWidgetInk.markContrast)
        return color(hex: tintInMode) ?? defaultTint
    }
}

/// The surface the pieces are drawn over (SidekickWidgetInk): set around a look with its own
/// background or fill, and inside an inline fill or background.
private struct WidgetSurfaceColorsKey: EnvironmentKey {
    static let defaultValue = WidgetSurfaceColors.system
}

extension EnvironmentValues {
    var widgetSurfaceColors: WidgetSurfaceColors {
        get { self[WidgetSurfaceColorsKey.self] }
        set { self[WidgetSurfaceColorsKey.self] = newValue }
    }
}

/// A piece's own colour in the current mode, read over the current surface.
struct WidgetPieceColors {
    let surface: WidgetSurfaceColors
    let colorScheme: ColorScheme

    /// The colour for `lightHex` / `darkHex` (text needs body contrast, marks less); nil without
    /// a colour of its own.
    func color(lightHex: String?, darkHex: String?, minimumContrast: Double) -> Color? {
        let hex = surface.foregroundHex(lightHex: lightHex, darkHex: darkHex, isDark: colorScheme == .dark, minimumContrast: minimumContrast)
        return SidekickWidgetColors.color(hex: hex)
    }

    func markColor(lightHex: String?, darkHex: String?) -> Color {
        return color(lightHex: lightHex, darkHex: darkHex, minimumContrast: SidekickWidgetInk.markContrast) ?? Color.accentColor
    }

    /// The widget's ink over its own background; nil over the system background.
    func ink(_ level: WidgetInkLevel) -> Color? {
        guard let inkHex = surface.inkHex else {
            return nil
        }
        let inkColor = SidekickWidgetColors.color(hex: inkHex) ?? Color.primary
        guard level == .secondary else {
            return inkColor
        }
        let opacity = SidekickWidgetInk.secondaryOpacity(inkHex: inkHex, over: surface.hexes)
        return inkColor.opacity(opacity)
    }
}

/// What a widget's look draws behind everything and in front (hydration plan W4). A description's
/// `background` wraps the whole look; a `fill` that is the whole look fills the widget edge to
/// edge, behind the system's margins, with its content in front.
enum SidekickWidgetSurface {
    /// The widget's own background colours, or nil for the system's.
    static func background(of piece: WidgetPiece) -> WidgetBackgroundPiece? {
        guard case .background(let background) = piece else {
            return nil
        }
        return background
    }

    /// The fill drawn edge to edge: the look itself, inside its background.
    static func edgeFill(of piece: WidgetPiece) -> WidgetFillPiece? {
        let lookPiece = background(of: piece)?.content ?? piece
        guard case .fill(let fill) = lookPiece else {
            return nil
        }
        return fill
    }

    /// What is drawn inside the margins: the look without its background and edge fill.
    static func foreground(of piece: WidgetPiece) -> WidgetPiece? {
        let lookPiece = background(of: piece)?.content ?? piece
        if case .fill(let fill) = lookPiece {
            return fill.content
        }
        return lookPiece
    }
}

struct SidekickWidgetView: View {
    let screen: SidekickWidgetScreen

    var body: some View {
        SidekickWidgetContent(screen: screen)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(openURL)
            .containerBackground(for: .widget) {
                SidekickWidgetBackdrop(screen: screen)
            }
    }

    /// The whole widget opens its Sidekick; without one, the Midas home.
    private var openURL: URL {
        switch screen {
        case .pickSidekick:
            return MidasLink.home.url
        case .empty(let sidekickId):
            guard let sidekickId else {
                return MidasLink.home.url
            }
            return MidasLink.openSidekick(id: sidekickId).url
        case .piece(_, let sidekickId, _):
            return MidasLink.openSidekick(id: sidekickId).url
        }
    }
}

/// Everything inside the widget's margins.
struct SidekickWidgetContent: View {
    let screen: SidekickWidgetScreen

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        switch screen {
        case .pickSidekick:
            SidekickWidgetMessage(text: SidekickWidgetCopy.pickSidekick)
        case .empty:
            SidekickWidgetMessage(text: SidekickWidgetCopy.empty)
        case .piece(let piece, _, let tintHex):
            if let foreground = SidekickWidgetSurface.foreground(of: piece) {
                let surface = SidekickWidgetColors.surface(of: piece, tintHex: tintHex, colorScheme: colorScheme)
                WidgetPieceView(piece: foreground)
                    .modifier(WidgetInkModifier(surface: surface))
                    .tint(SidekickWidgetColors.tintColor(tintHex: tintHex, surface: surface, colorScheme: colorScheme))
            }
        }
    }
}

/// Over a surface of the widget's own, everything without a colour of its own (a ring's label,
/// a timer) is drawn in the ink chosen for it; over the system background nothing changes.
struct WidgetInkModifier: ViewModifier {
    let surface: WidgetSurfaceColors

    func body(content: Content) -> some View {
        if let inkHex = surface.inkHex {
            content
                .foregroundStyle(SidekickWidgetColors.color(hex: inkHex) ?? Color.primary)
                .environment(\.widgetSurfaceColors, surface)
        } else {
            content
                .environment(\.widgetSurfaceColors, surface)
        }
    }
}

/// Behind the margins, edge to edge: the widget's background colour and an edge fill.
struct SidekickWidgetBackdrop: View {
    let screen: SidekickWidgetScreen

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            backgroundColor
            if case .piece(let piece, _, let tintHex) = screen, let fill = SidekickWidgetSurface.edgeFill(of: piece) {
                WidgetFillLayer(fill: fill)
                    .tint(SidekickWidgetColors.color(hex: tintHex) ?? SidekickWidgetColors.defaultTint)
            }
        }
    }

    private var backgroundColor: Color {
        guard case .piece(let piece, _, _) = screen, let background = SidekickWidgetSurface.background(of: piece) else {
            return SidekickWidgetColors.background
        }
        let ownHex = SidekickWidgetColors.backgroundHex(background, colorScheme: colorScheme)
        return SidekickWidgetColors.color(hex: ownHex) ?? SidekickWidgetColors.background
    }
}

/// A widget as it sits on the Home Screen, margins and corners included, for drawing outside
/// WidgetKit (the fill renders in docs/mockups).
struct SidekickWidgetSnapshot: View {
    let screen: SidekickWidgetScreen
    let size: SidekickWidgetSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            SidekickWidgetBackdrop(screen: screen)
            SidekickWidgetContent(screen: screen)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: Self.width(of: size), height: Self.height(of: size))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    /// iPhone 16 Pro widget sizes in points.
    static func width(of size: SidekickWidgetSize) -> CGFloat {
        return size == .small ? 170 : 364
    }

    static func height(of size: SidekickWidgetSize) -> CGFloat {
        return size == .large ? 382 : 170
    }
}

struct SidekickWidgetMessage: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Draws one filled piece and, through itself, everything inside it.
struct WidgetPieceView: View {
    let piece: WidgetPiece

    var body: some View {
        switch piece {
        case .vstack(let stack):
            VStack(alignment: Self.horizontalAlignment(stack.alignment), spacing: Self.spacing(stack.spacing, default: 6)) {
                WidgetPieceChildren(children: stack.children)
            }
        case .hstack(let stack):
            HStack(alignment: Self.verticalAlignment(stack.alignment), spacing: Self.spacing(stack.spacing, default: 8)) {
                WidgetPieceChildren(children: stack.children)
            }
        case .grid(let grid):
            WidgetGridView(grid: grid)
        case .spacer:
            Spacer(minLength: 0)
        case .divider:
            Divider()
        case .text(let text):
            WidgetTextView(text: text)
        case .symbol(let symbol):
            WidgetSymbolView(symbol: symbol)
        case .bar(let meter):
            WidgetBarView(meter: meter)
        case .ring(let meter):
            WidgetRingView(meter: meter)
        case .dots(let meter):
            WidgetDotsView(meter: meter)
        case .chart(let chart):
            WidgetChartView(chart: chart)
        case .timer(let timer):
            WidgetTimerView(timer: timer)
        case .tick(let tick):
            WidgetTickView(tick: tick)
        case .button(let button):
            WidgetButtonView(button: button)
        case .fill(let fill):
            WidgetInlineFillView(fill: fill)
        case .background(let background):
            WidgetInlineBackgroundView(background: background)
        }
    }

    static func spacing(_ spacing: Double?, default defaultSpacing: CGFloat) -> CGFloat {
        guard let spacing else {
            return defaultSpacing
        }
        return CGFloat(spacing)
    }

    static func horizontalAlignment(_ alignment: WidgetAlignment?) -> HorizontalAlignment {
        switch alignment {
        case .center:
            return .center
        case .trailing:
            return .trailing
        default:
            return .leading
        }
    }

    static func verticalAlignment(_ alignment: WidgetAlignment?) -> VerticalAlignment {
        switch alignment {
        case .top:
            return .top
        case .bottom:
            return .bottom
        default:
            return .center
        }
    }
}

struct WidgetPieceChildren: View {
    let children: [WidgetPiece]

    var body: some View {
        ForEach(Array(children.enumerated()), id: \.offset) { _, child in
            WidgetPieceView(piece: child)
        }
    }
}

/// Rows of `columns` pieces each.
struct WidgetGridView: View {
    let grid: WidgetGridPiece

    var body: some View {
        let spacing = WidgetPieceView.spacing(grid.spacing, default: 6)
        let rows = Self.rows(of: grid.children, columns: max(grid.columns, 1))
        Grid(alignment: .leading, horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    WidgetPieceChildren(children: row)
                }
            }
        }
    }

    static func rows(of children: [WidgetPiece], columns: Int) -> [[WidgetPiece]] {
        var rows: [[WidgetPiece]] = []
        var currentRow: [WidgetPiece] = []
        for child in children {
            currentRow.append(child)
            if currentRow.count == columns {
                rows.append(currentRow)
                currentRow = []
            }
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }
        return rows
    }
}

enum WidgetFonts {
    static func font(for style: WidgetTextStyle) -> Font {
        switch style {
        case .title:
            return .system(size: 17, weight: .bold)
        case .headline:
            return .system(size: 15, weight: .semibold)
        case .body:
            return .system(size: 14)
        case .caption:
            return .system(size: 12)
        case .number:
            return .system(size: 34, weight: .bold, design: .rounded)
        }
    }
}

struct WidgetTextView: View {
    let text: WidgetTextPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text.text)
            .font(WidgetFonts.font(for: text.style))
            .foregroundStyle(textStyle)
            .lineLimit(text.lineLimit)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
    }

    private var textStyle: AnyShapeStyle {
        let pieceColors = WidgetPieceColors(surface: surface, colorScheme: colorScheme)
        if let color = pieceColors.color(lightHex: text.colorHex, darkHex: text.darkColorHex, minimumContrast: SidekickWidgetInk.textContrast) {
            return AnyShapeStyle(color)
        }
        // Over the widget's own background, its ink; never the system colour (white on light).
        let level: WidgetInkLevel = text.isSecondary ? .secondary : .primary
        if let inkColor = pieceColors.ink(level) {
            return AnyShapeStyle(inkColor)
        }
        if text.isSecondary {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle(.primary)
    }
}

struct WidgetSymbolView: View {
    let symbol: WidgetSymbolPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: symbol.name)
            .font(.system(size: symbol.size, weight: .semibold))
            .foregroundStyle(symbolStyle)
            .widgetAccentable()
    }

    private var symbolStyle: AnyShapeStyle {
        let pieceColors = WidgetPieceColors(surface: surface, colorScheme: colorScheme)
        if let level = symbol.ink {
            if let inkColor = pieceColors.ink(level) {
                return AnyShapeStyle(inkColor)
            }
            return level == .secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
        }
        return AnyShapeStyle(pieceColors.markColor(lightHex: symbol.colorHex, darkHex: symbol.darkColorHex))
    }
}

struct WidgetBarView: View {
    let meter: WidgetMeterPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let barColor = WidgetPieceColors(surface: surface, colorScheme: colorScheme).markColor(lightHex: meter.colorHex, darkHex: meter.darkColorHex)
        HStack(spacing: 6) {
            // Drawn, not ProgressView: a track and a filled part, so every look draws the same.
            Capsule()
                .fill(barColor.opacity(0.2))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { geometry in
                        Capsule()
                            .fill(barColor)
                            .frame(width: geometry.size.width * meter.fraction)
                            .widgetAccentable()
                    }
                }
            if let label = meter.label {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }
}

struct WidgetRingView: View {
    let meter: WidgetMeterPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let ringColor = WidgetPieceColors(surface: surface, colorScheme: colorScheme).markColor(lightHex: meter.colorHex, darkHex: meter.darkColorHex)
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.2), lineWidth: 5)
            Circle()
                .trim(from: 0, to: meter.fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            if let label = meter.label {
                Text(label)
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .padding(6)
            }
        }
        .frame(width: 44, height: 44)
    }
}

/// One dot per step, filled for each done; at most 12.
struct WidgetDotsView: View {
    let meter: WidgetMeterPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dotColor = WidgetPieceColors(surface: surface, colorScheme: colorScheme).markColor(lightHex: meter.colorHex, darkHex: meter.darkColorHex)
        let dotCount = min(max(Int(meter.total), 0), 12)
        let filledCount = min(max(Int(meter.value), 0), dotCount)
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { dotIndex in
                Circle()
                    .fill(dotIndex < filledCount ? dotColor : dotColor.opacity(0.2))
                    .frame(width: 9, height: 9)
                    .widgetAccentable()
            }
        }
    }
}

/// Bars, tallest value full height.
struct WidgetChartView: View {
    let chart: WidgetChartPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let barColor = WidgetPieceColors(surface: surface, colorScheme: colorScheme).markColor(lightHex: chart.colorHex, darkHex: chart.darkColorHex)
        let highest = max(chart.values.max() ?? 1, 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(chart.values.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: max(CGFloat(value / highest) * 40, 2))
                    .widgetAccentable()
            }
        }
        .frame(height: 40, alignment: .bottom)
    }
}

/// Counts on its own, without the widget redrawing.
struct WidgetTimerView: View {
    let timer: WidgetTimerPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let pieceColors = WidgetPieceColors(surface: surface, colorScheme: colorScheme)
        let ownColor = pieceColors.color(lightHex: timer.colorHex, darkHex: timer.darkColorHex, minimumContrast: SidekickWidgetInk.textContrast)
        timerText
            .font(WidgetFonts.font(for: timer.textStyle))
            .foregroundStyle(ownColor ?? pieceColors.ink(.primary) ?? Color.primary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var timerText: Text {
        switch timer.style {
        case .countdown:
            let now = Date()
            let start = min(now, timer.target)
            return Text(timerInterval: start...timer.target, countsDown: true)
        case .relative:
            return Text(timer.target, style: .relative)
        case .time:
            return Text(timer.target, style: .time)
        }
    }
}

/// A tick circle. iOS draws the toggle's new state the moment it is tapped (the dot fills), then
/// the intent writes the record in the app and the widget redraws.
struct WidgetTickView: View {
    let tick: WidgetTickPiece

    var body: some View {
        let tickIntent = SidekickWidgetActionIntent(action: tick.action)
        Toggle(isOn: false, intent: tickIntent) {
            EmptyView()
        }
        .toggleStyle(WidgetTickToggleStyle(colorHex: tick.colorHex, darkColorHex: tick.darkColorHex, size: tick.size))
    }
}

struct WidgetTickToggleStyle: ToggleStyle {
    let colorHex: String?
    var darkColorHex: String? = nil
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        let ownColor = WidgetPieceColors(surface: surface, colorScheme: colorScheme).markColor(lightHex: colorHex, darkHex: darkColorHex)
        let circleColor = renderingMode == .accented ? Color.primary : ownColor
        Circle()
            .strokeBorder(circleColor, lineWidth: 1.6)
            .frame(width: size, height: size)
            .overlay {
                if configuration.isOn {
                    Circle()
                        .fill(circleColor)
                        .frame(width: size - 6.4, height: size - 6.4)
                }
            }
            .contentShape(Rectangle())
    }
}

struct WidgetButtonView: View {
    let button: WidgetButtonPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if button.action.kind == .open {
            Link(destination: MidasLink.openSidekick(id: button.action.sidekickId).url) {
                buttonLabel
            }
        } else {
            Button(intent: SidekickWidgetActionIntent(action: button.action)) {
                buttonLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var buttonLabel: some View {
        let buttonHex = surface.foregroundHex(lightHex: button.colorHex, darkHex: button.darkColorHex, isDark: colorScheme == .dark,
                                              minimumContrast: SidekickWidgetInk.markContrast)
        let buttonColor = SidekickWidgetColors.color(hex: buttonHex) ?? Color.accentColor
        return HStack(spacing: 4) {
            if let symbolName = button.symbolName {
                Image(systemName: symbolName)
            }
            Text(button.title)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Self.labelColor(onButtonHex: buttonHex))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(buttonColor))
        .widgetAccentable()
    }

    /// White on the capsule, or dark ink on a light one (a night accent such as Water's #5FB3BA),
    /// whichever reads better; white on the system tint.
    static func labelColor(onButtonHex buttonHex: String?) -> Color {
        guard let buttonHex else {
            return Color.white
        }
        let whiteContrast = SidekickWidgetInk.contrast("#FFFFFF", buttonHex)
        let inkContrast = SidekickWidgetInk.contrast(SidekickWidgetInk.darkInkHex, buttonHex)
        let labelHex = whiteContrast >= inkContrast ? "#FFFFFF" : SidekickWidgetInk.darkInkHex
        return SidekickWidgetColors.color(hex: labelHex) ?? Color.white
    }
}

// MARK: Fill (hydration plan W4)

/// The water line: everything below `fraction` of the height, with a still wave on top.
struct WidgetFillShape: Shape {
    let fraction: Double
    let edge: WidgetFillEdge

    /// The Tide mockup's wave: 3 points high, a crest every 90 points.
    static let waveHeight: CGFloat = 3
    static let waveLength: CGFloat = 90

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0 else {
            return path
        }
        let surfaceY = rect.maxY - rect.height * CGFloat(fraction)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: surfaceY))
        if edge == .wave {
            // A sine along the surface, sampled every 2 points.
            var x = rect.minX
            while x <= rect.maxX {
                let phase = (x - rect.minX) / Self.waveLength * 2 * .pi
                path.addLine(to: CGPoint(x: x, y: surfaceY + Self.waveHeight * sin(phase)))
                x += 2
            }
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: surfaceY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The fill's colour, rising to its fraction, in the space it is given.
struct WidgetFillLayer: View {
    let fill: WidgetFillPiece

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Without a colour of its own the fill is the tint, drawn as Color.accentColor.
        let ownHex = fill.colorHex == nil ? nil : SidekickWidgetColors.fillHex(fill, tintHex: nil, colorScheme: colorScheme)
        let fillColor = SidekickWidgetColors.color(hex: ownHex) ?? Color.accentColor
        WidgetFillShape(fraction: fill.fraction, edge: fill.edge)
            .fill(fillColor)
            .widgetAccentable()
    }
}

/// A fill inside a stack: a rounded panel with the fill behind its content.
struct WidgetInlineFillView: View {
    let fill: WidgetFillPiece

    @Environment(\.widgetSurfaceColors) private var surface
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topLeading) {
            WidgetFillLayer(fill: fill)
            if let content = fill.content {
                WidgetPieceView(piece: content)
                    .padding(8)
                    .modifier(WidgetInkModifier(surface: panelSurface))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// The panel's content is over what is around it and over the sea.
    private var panelSurface: WidgetSurfaceColors {
        let isDark = colorScheme == .dark
        let aroundHexes = surface.readableOver(isDark: isDark)
        let seaHex = SidekickWidgetColors.fillHex(fill, tintHex: nil, colorScheme: colorScheme) ?? SidekickWidgetInk.defaultTintHex
        return WidgetSurfaceColors(hexes: aroundHexes + [seaHex])
    }
}

/// A background met inside a look (the filler only puts one around a whole look).
struct WidgetInlineBackgroundView: View {
    let background: WidgetBackgroundPiece

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let backgroundHex = SidekickWidgetColors.backgroundHex(background, colorScheme: colorScheme)
        WidgetPieceView(piece: background.content)
            .modifier(WidgetInkModifier(surface: WidgetSurfaceColors(hexes: [backgroundHex])))
            .background(SidekickWidgetColors.color(hex: backgroundHex) ?? SidekickWidgetColors.background)
    }
}
