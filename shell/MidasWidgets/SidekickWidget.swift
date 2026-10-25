import AppIntents
import SwiftUI
import WidgetKit

// The Sidekick widget: one gallery entry any Sidekick fills (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html). The person picks a Sidekick and one of its
// widgets; the app has already filled that widget's pieces (shell/Midas/SidekickWidgetFiller.swift)
// and this file only draws them. The logic is in shell/Shared/SidekickWidgetShared.swift.

struct SidekickWidgetEntry: TimelineEntry {
    let date: Date
    let screen: SidekickWidgetScreen
}

struct SidekickWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SidekickWidgetEntry {
        return SidekickWidgetEntry(date: Date(), screen: .pickSidekick)
    }

    func snapshot(for configuration: SidekickWidgetIntent, in context: Context) async -> SidekickWidgetEntry {
        let file = SharedSidekickWidgets.read(from: SidekickWidgetShared.fileURL())
        return entry(at: Date(), file: file, configuration: configuration, context: context)
    }

    // One entry now and one at the next midnight (today's look rolls over, which the file already
    // holds). A record changed in the app or a tap reloads it sooner.
    func timeline(for configuration: SidekickWidgetIntent, in context: Context) async -> Timeline<SidekickWidgetEntry> {
        let file = SharedSidekickWidgets.read(from: SidekickWidgetShared.fileURL())
        let now = Date()
        let chosenWidget = SidekickWidgetLayout.chosenWidget(file: file, sidekickId: configuration.sidekick?.id,
                                                             widgetChoiceId: configuration.widget?.id)
        var entries: [SidekickWidgetEntry] = []
        for entryDate in SidekickWidgetLayout.timelineDates(widget: chosenWidget, now: now) {
            entries.append(entry(at: entryDate, file: file, configuration: configuration, context: context))
        }
        // The calendar the app fills the looks with, so this reload lands on the same midnight.
        let dayCalendar = SidekickWidgetDayKey.calendar()
        let startOfToday = dayCalendar.startOfDay(for: now)
        let nextMidnight = dayCalendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(86_400)
        return Timeline(entries: entries, policy: .after(nextMidnight.addingTimeInterval(60)))
    }

    private func entry(at date: Date, file: SharedSidekickWidgets?, configuration: SidekickWidgetIntent, context: Context) -> SidekickWidgetEntry {
        let size = Self.size(for: context.family)
        let screen = SidekickWidgetLayout.screen(file: file, sidekickId: configuration.sidekick?.id,
                                                 widgetChoiceId: configuration.widget?.id, size: size, at: date)
        return SidekickWidgetEntry(date: date, screen: screen)
    }

    static func size(for widgetFamily: WidgetFamily) -> SidekickWidgetSize {
        switch widgetFamily {
        case .systemMedium:
            return .medium
        case .systemLarge:
            return .large
        default:
            return .small
        }
    }
}

struct SidekickWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: SidekickWidgetShared.kind, intent: SidekickWidgetIntent.self, provider: SidekickWidgetProvider()) { entry in
            SidekickWidgetView(screen: entry.screen)
        }
        .configurationDisplayName(SidekickWidgetCopy.displayName)
        .description(SidekickWidgetCopy.description)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Views

enum SidekickWidgetColors {
    /// White in light mode, #1C1C1E in dark, as the Reminders widget.
    static let background = Color(uiColor: .secondarySystemGroupedBackground)
    static let defaultTint = Color(uiColor: .systemBlue)

    static func color(hex: String?) -> Color? {
        guard let hex else {
            return nil
        }
        return SidekickColor.color(fromHex: hex)
    }
}

struct SidekickWidgetView: View {
    let screen: SidekickWidgetScreen

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(openURL)
            .containerBackground(SidekickWidgetColors.background, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .pickSidekick:
            SidekickWidgetMessage(text: SidekickWidgetCopy.pickSidekick)
        case .empty:
            SidekickWidgetMessage(text: SidekickWidgetCopy.empty)
        case .piece(let piece, _, let tintHex):
            WidgetPieceView(piece: piece)
                .tint(SidekickWidgetColors.color(hex: tintHex) ?? SidekickWidgetColors.defaultTint)
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
            Image(systemName: symbol.name)
                .font(.system(size: symbol.size, weight: .semibold))
                .foregroundStyle(SidekickWidgetColors.color(hex: symbol.colorHex) ?? Color.accentColor)
                .widgetAccentable()
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

    var body: some View {
        Text(text.text)
            .font(WidgetFonts.font(for: text.style))
            .foregroundStyle(textStyle)
            .lineLimit(text.lineLimit)
            .minimumScaleFactor(0.7)
            .monospacedDigit()
    }

    private var textStyle: AnyShapeStyle {
        if let color = SidekickWidgetColors.color(hex: text.colorHex) {
            return AnyShapeStyle(color)
        }
        if text.isSecondary {
            return AnyShapeStyle(.secondary)
        }
        return AnyShapeStyle(.primary)
    }
}

struct WidgetBarView: View {
    let meter: WidgetMeterPiece

    var body: some View {
        let barColor = SidekickWidgetColors.color(hex: meter.colorHex) ?? Color.accentColor
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

    var body: some View {
        let ringColor = SidekickWidgetColors.color(hex: meter.colorHex) ?? Color.accentColor
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

    var body: some View {
        let dotColor = SidekickWidgetColors.color(hex: meter.colorHex) ?? Color.accentColor
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

    var body: some View {
        let barColor = SidekickWidgetColors.color(hex: chart.colorHex) ?? Color.accentColor
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

    var body: some View {
        timerText
            .font(WidgetFonts.font(for: timer.textStyle))
            .foregroundStyle(SidekickWidgetColors.color(hex: timer.colorHex) ?? Color.primary)
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
        .toggleStyle(WidgetTickToggleStyle(colorHex: tick.colorHex, size: tick.size))
    }
}

struct WidgetTickToggleStyle: ToggleStyle {
    let colorHex: String?
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    func makeBody(configuration: Configuration) -> some View {
        let circleColor = renderingMode == .accented ? Color.primary : (SidekickWidgetColors.color(hex: colorHex) ?? Color.accentColor)
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
        let buttonColor = SidekickWidgetColors.color(hex: button.colorHex) ?? Color.accentColor
        return HStack(spacing: 4) {
            if let symbolName = button.symbolName {
                Image(systemName: symbolName)
            }
            Text(button.title)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(Capsule().fill(buttonColor))
        .widgetAccentable()
    }
}
