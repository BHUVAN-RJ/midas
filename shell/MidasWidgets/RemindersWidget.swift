import SwiftUI
import WidgetKit

// The Reminders widget: Today's first three reminders on the Home Screen (brief
// docs/briefs/widget-reminders.md; mockups RemindersHome and RemindersStates on the widgets canvas,
// midas-intel docs/prototypes/widgets/). The logic is in shell/Shared/RemindersWidgetShared.swift;
// this file is WidgetKit plumbing and the views. The whole widget opens the Reminders Sidekick.

struct RemindersWidgetEntry: TimelineEntry {
    let date: Date
    let screen: RemindersWidgetScreen
    let family: RemindersWidgetFamily
}

struct RemindersWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemindersWidgetEntry {
        return entry(at: Date(), file: sharedFile(), family: Self.family(for: context.family))
    }

    func getSnapshot(in context: Context, completion: @escaping (RemindersWidgetEntry) -> Void) {
        let snapshotEntry = entry(at: Date(), file: sharedFile(), family: Self.family(for: context.family))
        completion(snapshotEntry)
    }

    // One entry now, one at each reminder's time later today (its time turns red) and one at
    // midnight (Today rolls over to tomorrow's list, which the file already holds). After midnight
    // WidgetKit asks again; a tick, a page change or a reminder changed in the app reloads it too.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RemindersWidgetEntry>) -> Void) {
        let file = sharedFile()
        let family = Self.family(for: context.family)
        let calendar = Calendar.current
        let entryDates = RemindersWidgetLayout.timelineDates(file: file, now: Date(), calendar: calendar)
        var entries: [RemindersWidgetEntry] = []
        for entryDate in entryDates {
            entries.append(entry(at: entryDate, file: file, family: family))
        }
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func entry(at date: Date, file: SharedTodayReminders?, family: RemindersWidgetFamily) -> RemindersWidgetEntry {
        let requestedPage = RemindersWidgetPagesFile.page(for: family, in: RemindersWidgetShared.pagesFileURL())
        let pendingTicks = PendingReminderTicksFile.read(from: RemindersWidgetShared.pendingTicksFileURL())
        let screen = RemindersWidgetLayout.screen(file: file, now: date, calendar: Calendar.current, family: family,
                                                  requestedPage: requestedPage, pendingTicks: pendingTicks)
        return RemindersWidgetEntry(date: date, screen: screen, family: family)
    }

    private func sharedFile() -> SharedTodayReminders? {
        return SharedTodayRemindersReader.read(from: RemindersWidgetShared.fileURL())
    }

    static func family(for widgetFamily: WidgetFamily) -> RemindersWidgetFamily {
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

struct RemindersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RemindersWidgetShared.kind, provider: RemindersWidgetProvider()) { entry in
            RemindersWidgetView(screen: entry.screen, family: entry.family)
        }
        .configurationDisplayName(RemindersWidgetCopy.displayName)
        .description(RemindersWidgetCopy.description)
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: Views

/// Sizes from the mockup (iPhone 16 Pro, 158 pt small widget).
enum RemindersWidgetStyle {
    static let smallHeaderSize: CGFloat = 15
    static let smallCircleSize: CGFloat = 14
    static let smallTitleSize: CGFloat = 13
    static let smallTimeSize: CGFloat = 11
    static let smallRowSpacing: CGFloat = 7
    static let smallRowsTopSpacing: CGFloat = 8

    static let mediumHeaderSize: CGFloat = 17
    static let mediumCircleSize: CGFloat = 16
    static let mediumTitleSize: CGFloat = 14
    static let mediumTimeSize: CGFloat = 12
    /// Three rows under the header line fill the 158 pt widget.
    static let mediumRowHeight: CGFloat = 32

    static let largeHeaderSize: CGFloat = 17
    static let largeRowHeight: CGFloat = 34

    static let circleLineWidth: CGFloat = 1.6
    /// Space between the ring and the filled dot of a ticked circle.
    static let filledDotGap: CGFloat = 1.6
    static let messageSize: CGFloat = 15
    static let arrowSize: CGFloat = 13
    static let arrowHitSize: CGFloat = 24

    /// The count pill (founder, 2026-10-12, layout D on the widgets canvas).
    static let countPillTextSize: CGFloat = 13
    static let countPillHeight: CGFloat = 22
    static let countPillHorizontalPadding: CGFloat = 7
    static let headerSpacing: CGFloat = 6
}

/// The colours the widget uses, light and dark from the system: blue header, red past time.
enum RemindersWidgetColors {
    static let header = Color(uiColor: .systemBlue)
    /// #FF3B30 light, #FF453A dark.
    static let passedTime = Color(uiColor: .systemRed)
    /// White in light mode, #1C1C1E in dark, as the mockup.
    static let background = Color(uiColor: .secondarySystemGroupedBackground)
}

struct RemindersWidgetView: View {
    let screen: RemindersWidgetScreen
    let family: RemindersWidgetFamily

    var body: some View {
        Group {
            switch family {
            case .small:
                RemindersSmallView(screen: screen)
            case .medium:
                RemindersMediumView(screen: screen)
            case .large:
                RemindersLargeView(screen: screen)
            }
        }
        .widgetURL(MidasLink.openSidekick(id: RemindersWidgetShared.sidekickId).url)
        .containerBackground(RemindersWidgetColors.background, for: .widget)
    }
}

/// The count next to "Today": everything in Today, 0 when all done, nothing without a file.
private func countText(for content: RemindersWidgetContent) -> String {
    switch content {
    case .empty:
        return ""
    case .allDone:
        return "0"
    case .reminders(let count, _):
        return String(count)
    }
}

/// "All done" or "Open Midas", or nil when there are rows to draw.
private func messageText(for content: RemindersWidgetContent) -> String? {
    switch content {
    case .empty:
        return RemindersWidgetCopy.empty
    case .allDone:
        return RemindersWidgetCopy.allDone
    case .reminders:
        return nil
    }
}

private func rows(of content: RemindersWidgetContent) -> [RemindersWidgetRow] {
    guard case .reminders(_, let rows) = content else {
        return []
    }
    return rows
}

/// "Today" in blue; in the accented (tinted, clear) mode it takes the accent colour.
struct RemindersHeaderText: View {
    let fontSize: CGFloat

    var body: some View {
        Text(RemindersWidgetCopy.header)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(RemindersWidgetColors.header)
            .widgetAccentable()
    }
}

/// The count in a blue pill with white digits. In the accented (tinted, clear) mode a filled
/// pill would lose its digits to the tint, so it becomes an accent ring around accent digits.
struct RemindersCountPill: View {
    let count: String

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let isAccented = renderingMode == .accented
        Text(count)
            .font(.system(size: RemindersWidgetStyle.countPillTextSize, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(isAccented ? RemindersWidgetColors.header : Color.white)
            .padding(.horizontal, RemindersWidgetStyle.countPillHorizontalPadding)
            .frame(minWidth: RemindersWidgetStyle.countPillHeight, minHeight: RemindersWidgetStyle.countPillHeight)
            .background {
                if isAccented {
                    Capsule().strokeBorder(RemindersWidgetColors.header, lineWidth: RemindersWidgetStyle.circleLineWidth)
                } else {
                    Capsule().fill(RemindersWidgetColors.header)
                }
            }
            .widgetAccentable()
    }
}

/// Layout D, every size: "Today" on the left, the count pill on the right, the page arrows
/// after it when today has more than one page. No pill without a file ("Open Midas").
struct RemindersHeaderLine: View {
    let screen: RemindersWidgetScreen
    let family: RemindersWidgetFamily
    let headerSize: CGFloat

    var body: some View {
        let count = countText(for: screen.content)
        HStack(alignment: .center, spacing: 4) {
            RemindersHeaderText(fontSize: headerSize)
            Spacer(minLength: 2)
            if !count.isEmpty {
                RemindersCountPill(count: count)
            }
            if screen.showsPageArrows {
                RemindersPageArrows(screen: screen, family: family, axis: .horizontal)
            }
        }
        .frame(height: RemindersWidgetStyle.arrowHitSize)
    }
}

struct RemindersMessageText: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: RemindersWidgetStyle.messageSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}

/// The completion circle in the list's colour; in the accented mode the primary colour, so the
/// rows stay readable on a tinted or clear Home Screen.
struct ReminderCircle: View {
    let colorHex: String
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Circle()
            .strokeBorder(ringColor, lineWidth: RemindersWidgetStyle.circleLineWidth)
            .frame(width: size, height: size)
    }

    private var ringColor: Color {
        if renderingMode == .accented {
            return .primary
        }
        return SidekickColor.color(fromHex: colorHex)
    }
}

/// A row as a toggle (founder, 2026-10-11: show the tick at once, do the work in the background).
/// iOS draws a widget `Toggle`'s new state the moment it is tapped, before the intent runs: the
/// circle fills in the list's colour and the title greys, as in Apple's Reminders. Meanwhile TickReminderIntent wakes Midas,
/// which queues and writes the tick and redraws the widget without the row.
struct ReminderTickToggle<RowLabel: View>: View {
    let reminder: SharedReminder
    let circleSize: CGFloat
    let alignment: VerticalAlignment
    @ViewBuilder let label: () -> RowLabel

    var body: some View {
        let tickIntent = TickReminderIntent(reminderId: reminder.id, occurrence: reminder.at)
        Toggle(isOn: false, intent: tickIntent) {
            label()
        }
        .toggleStyle(ReminderTickToggleStyle(colorHex: reminder.colorHex, circleSize: circleSize, alignment: alignment))
    }
}

/// The circle as the widget always draws it; ticked, a filled dot inside the ring and the row
/// greyed (founder, 2026-10-12: like Apple's Reminders, no cross, no strikethrough).
struct ReminderTickToggleStyle: ToggleStyle {
    let colorHex: String
    let circleSize: CGFloat
    let alignment: VerticalAlignment

    func makeBody(configuration: Configuration) -> some View {
        let isTicked = configuration.isOn
        HStack(alignment: alignment, spacing: 8) {
            ReminderCircle(colorHex: colorHex, size: circleSize)
                .overlay {
                    if isTicked {
                        ReminderFilledDot(colorHex: colorHex, size: circleSize)
                    }
                }
                .padding(.top, alignment == .top ? 1 : 0)
            configuration.label
                .opacity(isTicked ? 0.5 : 1)
        }
        .contentShape(Rectangle())
    }
}

/// The dot that fills a ticked circle, in the circle's colour, with a thin gap inside the ring
/// (the Sidekick's `.circle.filled`).
struct ReminderFilledDot: View {
    let colorHex: String
    let size: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let ringAndGap = RemindersWidgetStyle.circleLineWidth + RemindersWidgetStyle.filledDotGap
        Circle()
            .fill(dotColor)
            .frame(width: size - ringAndGap * 2, height: size - ringAndGap * 2)
    }

    private var dotColor: Color {
        if renderingMode == .accented {
            return .primary
        }
        return SidekickColor.color(fromHex: colorHex)
    }
}

/// Up and down arrows when today has more than one page (brief step 5; widgets cannot scroll).
struct RemindersPageArrows: View {
    let screen: RemindersWidgetScreen
    let family: RemindersWidgetFamily
    let axis: Axis

    var body: some View {
        let upIntent = PageRemindersIntent(family: family, step: -1, pageCount: screen.pageCount)
        let downIntent = PageRemindersIntent(family: family, step: 1, pageCount: screen.pageCount)
        let layout = axis == .vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 2))
        layout {
            RemindersArrowButton(intent: upIntent, symbolName: "chevron.up", isEnabled: screen.canPageUp)
            RemindersArrowButton(intent: downIntent, symbolName: "chevron.down", isEnabled: screen.canPageDown)
        }
    }
}

struct RemindersArrowButton: View {
    let intent: PageRemindersIntent
    let symbolName: String
    let isEnabled: Bool

    var body: some View {
        Button(intent: intent) {
            Image(systemName: symbolName)
                .font(.system(size: RemindersWidgetStyle.arrowSize, weight: .semibold))
                .foregroundStyle(isEnabled ? RemindersWidgetColors.header : Color.secondary.opacity(0.4))
                .frame(width: RemindersWidgetStyle.arrowHitSize, height: RemindersWidgetStyle.arrowHitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .widgetAccentable()
    }
}

/// A row's time: grey, red once passed (not in the accented mode, where colour is gone).
struct ReminderTimeText: View {
    let row: RemindersWidgetRow
    let fontSize: CGFloat

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(RemindersWidgetLayout.timeText(for: row.reminder, calendar: Calendar.current))
            .font(.system(size: fontSize))
            .monospacedDigit()
            .foregroundStyle(timeStyle)
    }

    private var timeStyle: AnyShapeStyle {
        let showsRed = row.hasPassed && renderingMode != .accented
        if showsRed {
            return AnyShapeStyle(RemindersWidgetColors.passedTime)
        }
        return AnyShapeStyle(.secondary)
    }
}

// MARK: Small

/// The header line on top; up to three rows: circle, title, the time under it.
struct RemindersSmallView: View {
    let screen: RemindersWidgetScreen

    var body: some View {
        let content = screen.content
        VStack(alignment: .leading, spacing: 0) {
            RemindersHeaderLine(screen: screen, family: .small, headerSize: RemindersWidgetStyle.smallHeaderSize)
            if let message = messageText(for: content) {
                Spacer(minLength: 0)
                RemindersMessageText(message: message)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: RemindersWidgetStyle.smallRowSpacing) {
                    ForEach(rows(of: content), id: \.reminder.id) { row in
                        RemindersSmallRow(row: row)
                    }
                }
                .padding(.top, RemindersWidgetStyle.smallRowsTopSpacing)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct RemindersSmallRow: View {
    let row: RemindersWidgetRow

    var body: some View {
        ReminderTickToggle(reminder: row.reminder, circleSize: RemindersWidgetStyle.smallCircleSize, alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(row.reminder.title)
                    .font(.system(size: RemindersWidgetStyle.smallTitleSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !row.reminder.allDay {
                    ReminderTimeText(row: row, fontSize: RemindersWidgetStyle.smallTimeSize)
                }
            }
        }
    }
}

// MARK: Medium

/// The header line on top; up to three rows full width under it, title then time.
struct RemindersMediumView: View {
    let screen: RemindersWidgetScreen

    var body: some View {
        let content = screen.content
        VStack(alignment: .leading, spacing: 2) {
            RemindersHeaderLine(screen: screen, family: .medium, headerSize: RemindersWidgetStyle.mediumHeaderSize)
            if let message = messageText(for: content) {
                RemindersMessageText(message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Pinned to the top (founder, 2026-10-11: one row floated in the middle).
                RemindersLineRows(rows: rows(of: content), rowHeight: RemindersWidgetStyle.mediumRowHeight)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Rows of circle, title and time on one line, with hairlines between them (medium and large).
struct RemindersLineRows: View {
    let rows: [RemindersWidgetRow]
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.reminder.id) { rowIndex, row in
                RemindersLineRow(row: row, rowHeight: rowHeight)
                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
    }
}

struct RemindersLineRow: View {
    let row: RemindersWidgetRow
    let rowHeight: CGFloat

    var body: some View {
        ReminderTickToggle(reminder: row.reminder, circleSize: RemindersWidgetStyle.mediumCircleSize, alignment: .center) {
            HStack(spacing: 9) {
                Text(row.reminder.title)
                    .font(.system(size: RemindersWidgetStyle.mediumTitleSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !row.reminder.allDay {
                    ReminderTimeText(row: row, fontSize: RemindersWidgetStyle.mediumTimeSize)
                        .fixedSize()
                }
            }
        }
        .frame(height: rowHeight)
    }
}

// MARK: Large

/// The header line on top; up to eight rows, title then time on one line.
struct RemindersLargeView: View {
    let screen: RemindersWidgetScreen

    var body: some View {
        let content = screen.content
        VStack(alignment: .leading, spacing: RemindersWidgetStyle.headerSpacing) {
            RemindersHeaderLine(screen: screen, family: .large, headerSize: RemindersWidgetStyle.largeHeaderSize)
            if let message = messageText(for: content) {
                RemindersMessageText(message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RemindersLineRows(rows: rows(of: content), rowHeight: RemindersWidgetStyle.largeRowHeight)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
