import AppIntents
import SwiftUI
import WidgetKit

// The Sidekick widget: one gallery entry any Sidekick fills (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html). The person picks a Sidekick and one of its
// widgets; the app has already filled that widget's pieces (shell/Midas/SidekickWidgetFiller.swift)
// and this extension only draws them. The logic is in shell/Shared/SidekickWidgetShared.swift, the
// views in shell/Shared/SidekickWidgetViews.swift.

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
