import SwiftUI
import WidgetKit

// The Reminders widget: Today's first three reminders on the Home Screen (brief
// docs/briefs/widget-reminders.md; mockups RemindersHome and RemindersStates on the widgets canvas,
// midas-intel docs/prototypes/widgets/). The logic is in shell/Shared/RemindersWidgetShared.swift;
// this file is WidgetKit plumbing and the views. The whole widget opens the Reminders Sidekick.

struct RemindersWidgetEntry: TimelineEntry {
    let date: Date
    let content: RemindersWidgetContent
}

struct RemindersWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RemindersWidgetEntry {
        return entry(at: Date(), file: sharedFile())
    }

    func getSnapshot(in context: Context, completion: @escaping (RemindersWidgetEntry) -> Void) {
        let snapshotEntry = entry(at: Date(), file: sharedFile())
        completion(snapshotEntry)
    }

    // One entry now, one at each reminder's time later today (its time turns red) and one at
    // midnight (Today rolls over to tomorrow's list, which the file already holds). After midnight
    // WidgetKit asks again; otherwise the app reloads the widget when a reminder changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<RemindersWidgetEntry>) -> Void) {
        let file = sharedFile()
        let calendar = Calendar.current
        let entryDates = RemindersWidgetLayout.timelineDates(file: file, now: Date(), calendar: calendar)
        var entries: [RemindersWidgetEntry] = []
        for entryDate in entryDates {
            entries.append(entry(at: entryDate, file: file))
        }
        let timeline = Timeline(entries: entries, policy: .atEnd)
        completion(timeline)
    }

    private func entry(at date: Date, file: SharedTodayReminders?) -> RemindersWidgetEntry {
        let content = RemindersWidgetLayout.content(file: file, now: date, calendar: Calendar.current)
        return RemindersWidgetEntry(date: date, content: content)
    }

    private func sharedFile() -> SharedTodayReminders? {
        return SharedTodayRemindersReader.read(from: RemindersWidgetShared.fileURL())
    }
}

struct RemindersWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: RemindersWidgetShared.kind, provider: RemindersWidgetProvider()) { entry in
            RemindersWidgetView(content: entry.content)
        }
        .configurationDisplayName(RemindersWidgetCopy.displayName)
        .description(RemindersWidgetCopy.description)
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: Views

/// Sizes from the mockup (iPhone 16 Pro, 158 pt small widget).
enum RemindersWidgetStyle {
    static let smallHeaderSize: CGFloat = 15
    static let smallCountSize: CGFloat = 20
    static let smallCircleSize: CGFloat = 14
    static let smallTitleSize: CGFloat = 13
    static let smallTimeSize: CGFloat = 11
    static let smallRowSpacing: CGFloat = 7
    static let smallRowsTopSpacing: CGFloat = 8

    static let mediumHeaderSize: CGFloat = 17
    static let mediumCountSize: CGFloat = 40
    static let mediumLeftWidth: CGFloat = 92
    static let mediumCircleSize: CGFloat = 16
    static let mediumTitleSize: CGFloat = 14
    static let mediumTimeSize: CGFloat = 12
    static let mediumRowHeight: CGFloat = 40

    static let circleLineWidth: CGFloat = 1.6
    static let messageSize: CGFloat = 15
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
    let content: RemindersWidgetContent

    @Environment(\.widgetFamily) private var widgetFamily

    var body: some View {
        Group {
            switch widgetFamily {
            case .systemMedium:
                RemindersMediumView(content: content)
            default:
                RemindersSmallView(content: content)
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

/// "Today" and the count on top; up to three rows: circle, title, the time under it.
struct RemindersSmallView: View {
    let content: RemindersWidgetContent

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                RemindersHeaderText(fontSize: RemindersWidgetStyle.smallHeaderSize)
                Spacer(minLength: 4)
                Text(countText(for: content))
                    .font(.system(size: RemindersWidgetStyle.smallCountSize, weight: .bold))
                    .foregroundStyle(.primary)
            }
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
        HStack(alignment: .top, spacing: 8) {
            ReminderCircle(colorHex: row.reminder.colorHex, size: RemindersWidgetStyle.smallCircleSize)
                .padding(.top, 1)
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

/// "Today" and a large count on the left; up to three rows on the right, title then time.
struct RemindersMediumView: View {
    let content: RemindersWidgetContent

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                RemindersHeaderText(fontSize: RemindersWidgetStyle.mediumHeaderSize)
                Spacer(minLength: 0)
                Text(countText(for: content))
                    .font(.system(size: RemindersWidgetStyle.mediumCountSize, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(width: RemindersWidgetStyle.mediumLeftWidth, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .leading)

            if let message = messageText(for: content) {
                RemindersMessageText(message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                RemindersMediumRows(rows: rows(of: content))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct RemindersMediumRows: View {
    let rows: [RemindersWidgetRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.reminder.id) { rowIndex, row in
                RemindersMediumRow(row: row)
                if rowIndex < rows.count - 1 {
                    Divider()
                }
            }
        }
    }
}

struct RemindersMediumRow: View {
    let row: RemindersWidgetRow

    var body: some View {
        HStack(spacing: 9) {
            ReminderCircle(colorHex: row.reminder.colorHex, size: RemindersWidgetStyle.mediumCircleSize)
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
        .frame(height: RemindersWidgetStyle.mediumRowHeight)
    }
}
