import Foundation

// The Sidekick widget's contract (founder, 2026-10-13: "Approve. You can start building"; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html). One widget in the gallery, "Sidekick". A
// Sidekick describes its widgets in `widget:<name>` records built from a fixed set of pieces; the
// app fills the description's `$` bindings from the Sidekick's records and writes the filled
// pieces into the App Group; the widget only draws them. Taps run actions built into the shell.
// Free of WidgetKit so MidasTests can test it through the app module; the views live in
// shell/MidasWidgets/SidekickWidget.swift.

/// The words the Sidekick widget shows. Only these; docs/WRITING.md rules.
enum SidekickWidgetCopy {
    static let displayName = "Sidekick"
    static let description = "A Sidekick on your Home Screen."
    static let pickSidekick = "Pick a Sidekick"
    static let empty = "Open Midas"
}

enum SidekickWidgetShared {
    /// WidgetKit `kind` of the Sidekick widget.
    static let kind = "com.bhuvanrj.midas.sidekick"

    /// The record key prefix a Sidekick describes a widget under: `widget:<name>`.
    static let recordPrefix = "widget:"

    /// Where the filled widgets of every Sidekick live; nil when the App Group is not available.
    static func fileURL(fileManager: FileManager = .default) -> URL? {
        return appGroupFileURL(named: "widget-sidekick-widgets.json", fileManager: fileManager)
    }

    /// Taps made on the widget that the app has not yet written to the records (only used when the
    /// tap could not run in the app's process).
    static func pendingActionsFileURL(fileManager: FileManager = .default) -> URL? {
        return appGroupFileURL(named: "widget-sidekick-actions.json", fileManager: fileManager)
    }

    /// The records of every Sidekick with a widget, as the app last published them, so the widget
    /// can show a tap at once when the tap had to wait for the app (SidekickWidgetTapPreview).
    static func recordsFileURL(fileManager: FileManager = .default) -> URL? {
        return appGroupFileURL(named: "widget-sidekick-records.json", fileManager: fileManager)
    }

    private static func appGroupFileURL(named fileName: String, fileManager: FileManager) -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: WidgetShared.appGroupIdentifier) else {
            return nil
        }
        return container.appending(path: fileName)
    }
}

/// Day keys (hydration plan W1, founder 2026-10-25): `{today}` in a source's `record` key or a
/// tap's key stands for the local date, "YYYY-MM-DD", so `water:{today}` is one record per day.
/// The filler resolves it for each look (the midnight look reads the new day); a tap resolves it
/// when it was tapped (`PendingWidgetAction.tappedAt`), so a 23:59 tap the app writes at 00:05
/// still lands on the day it was made. Filler, publisher and widget use this one calendar.
enum SidekickWidgetDayKey {
    static let todayToken = "{today}"

    /// Gregorian in the phone's zone, weeks from Sunday: the same calendar as the reminders
    /// (ReminderSchedule.phoneCalendar), whatever calendar the phone is set to show.
    static func calendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 1
        return calendar
    }

    /// "2026-10-25": the day `moment` falls on in the calendar's zone.
    static func dayText(_ moment: Date, calendar: Calendar) -> String {
        let fields = calendar.dateComponents([.year, .month, .day], from: moment)
        return String(format: "%04d-%02d-%02d", fields.year ?? 0, fields.month ?? 0, fields.day ?? 0)
    }

    /// The key with every `{today}` replaced by the day of `moment`; other keys as they are.
    static func resolve(_ key: String, at moment: Date, calendar: Calendar) -> String {
        guard key.contains(todayToken) else {
            return key
        }
        return key.replacingOccurrences(of: todayToken, with: dayText(moment, calendar: calendar))
    }
}

/// The three Home Screen sizes (Lock Screen sizes come in a later round).
enum SidekickWidgetSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large
}

// MARK: Filled pieces, as the widget draws them

/// How children line up in a stack.
enum WidgetAlignment: String, Codable, Sendable {
    case leading
    case center
    case trailing
    case top
    case bottom
}

/// Text sizes a description can ask for. "number" is a large rounded figure.
enum WidgetTextStyle: String, Codable, Sendable {
    case title
    case headline
    case body
    case caption
    case number
}

/// How a timer counts: down to the moment ("12:04"), as words ("in 2 hr"), or the clock time.
enum WidgetTimerStyle: String, Codable, Sendable {
    case countdown
    case relative
    case time
}

struct WidgetStackPiece: Codable, Equatable, Sendable {
    let children: [WidgetPiece]
    let spacing: Double?
    let alignment: WidgetAlignment?
}

struct WidgetGridPiece: Codable, Equatable, Sendable {
    let children: [WidgetPiece]
    let columns: Int
    let spacing: Double?
}

struct WidgetTextPiece: Codable, Equatable, Sendable {
    let text: String
    let style: WidgetTextStyle
    /// "#RRGGBB", or nil for the primary colour.
    let colorHex: String?
    /// True for "secondary": the grey the system uses for less important text.
    let isSecondary: Bool
    let lineLimit: Int
}

struct WidgetSymbolPiece: Codable, Equatable, Sendable {
    /// An SF Symbol name.
    let name: String
    let colorHex: String?
    let size: Double
}

/// A bar, ring or row of dots: how much of `total` is done.
struct WidgetMeterPiece: Codable, Equatable, Sendable {
    let value: Double
    let total: Double
    let colorHex: String?
    /// Words inside a ring or after a bar; nil for none.
    let label: String?

    /// 0 to 1; 0 when the total is 0.
    var fraction: Double {
        guard total > 0 else {
            return 0
        }
        return min(max(value / total, 0), 1)
    }
}

struct WidgetChartPiece: Codable, Equatable, Sendable {
    let values: [Double]
    let colorHex: String?
}

struct WidgetTimerPiece: Codable, Equatable, Sendable {
    let target: Date
    let style: WidgetTimerStyle
    let colorHex: String?
    let textStyle: WidgetTextStyle
}

/// A tick circle for one item: ticking it runs `action`.
struct WidgetTickPiece: Codable, Equatable, Sendable {
    let action: WidgetTapAction
    let colorHex: String?
    let size: Double
}

struct WidgetButtonPiece: Codable, Equatable, Sendable {
    let title: String
    let symbolName: String?
    let colorHex: String?
    let action: WidgetTapAction
}

/// The top of a fill: straight, or a still wave (widgets do not animate on iOS).
enum WidgetFillEdge: String, Codable, Sendable {
    case flat
    case wave
}

/// A colour that rises from the bottom to `fraction` of the height, with `content` drawn on top
/// (hydration plan W4, founder 2026-10-25: the Tide sea). As a widget's whole look it fills the
/// widget edge to edge.
struct WidgetFillPiece: Codable, Equatable, Sendable {
    /// 0 to 1, already clamped.
    let fraction: Double
    /// "#RRGGBB"; nil for the tint.
    let colorHex: String?
    /// The colour in dark mode; nil for the same as light.
    let darkColorHex: String?
    let edge: WidgetFillEdge
    let content: WidgetPiece?
}

/// A widget's own background colour (`background` on the description), around its whole look.
struct WidgetBackgroundPiece: Codable, Equatable, Sendable {
    let colorHex: String
    /// The colour in dark mode; nil for the same as light.
    let darkColorHex: String?
    let content: WidgetPiece
}

/// One filled piece. Bindings are already replaced by values; nothing here is evaluated by the
/// widget.
indirect enum WidgetPiece: Codable, Equatable, Sendable {
    case vstack(WidgetStackPiece)
    case hstack(WidgetStackPiece)
    case grid(WidgetGridPiece)
    case spacer
    case divider
    case text(WidgetTextPiece)
    case symbol(WidgetSymbolPiece)
    case bar(WidgetMeterPiece)
    case ring(WidgetMeterPiece)
    case dots(WidgetMeterPiece)
    case chart(WidgetChartPiece)
    case timer(WidgetTimerPiece)
    case tick(WidgetTickPiece)
    case button(WidgetButtonPiece)
    case fill(WidgetFillPiece)
    case background(WidgetBackgroundPiece)
}

// MARK: Taps

/// What a tap on the widget does. Only these, all built into the shell; each changes one record
/// of the Sidekick that owns the widget.
enum WidgetTapKind: String, Codable, Sendable {
    /// Opens the Sidekick.
    case open
    /// Marks an item done: a `reminder:` record as the notification's Done does, any other record
    /// gets `done: true`.
    case tick
    /// Adds `amount` to a number field.
    case increment
    /// Flips a true/false field.
    case toggle
    /// Writes a fixed value into a field.
    case set
}

struct WidgetTapAction: Codable, Equatable, Hashable, Sendable {
    let kind: WidgetTapKind
    let sidekickId: String
    /// The record changed; nil for `open`.
    let key: String?
    /// The field changed by increment, toggle and set.
    let field: String?
    /// The step of an increment.
    let amount: Double?
    /// The value `set` writes, as JSON text.
    let valueJSON: String?
    /// The occurrence a tick is for (a repeat's today).
    let occurrence: Date?

    static func open(sidekickId: String) -> WidgetTapAction {
        return WidgetTapAction(kind: .open, sidekickId: sidekickId, key: nil, field: nil, amount: nil, valueJSON: nil, occurrence: nil)
    }

    /// The action as text, so an App Intent can carry it as one parameter.
    func encodedText() -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else {
            return ""
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func decoded(fromText text: String) -> WidgetTapAction? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetTapAction.self, from: Data(text.utf8))
    }
}

// MARK: The file the app writes

/// One look of a widget from a moment on: the app fills each widget for now and for the next
/// midnight, so "today" rolls over without the app running.
struct FilledWidgetLook: Codable, Equatable, Sendable {
    let from: Date
    let small: WidgetPiece?
    let medium: WidgetPiece?
    let large: WidgetPiece?

    func piece(for size: SidekickWidgetSize) -> WidgetPiece? {
        switch size {
        case .small:
            return small
        case .medium:
            return medium
        case .large:
            return large
        }
    }
}

/// One `widget:<name>` record of one Sidekick, filled.
struct FilledSidekickWidget: Codable, Equatable, Sendable {
    let sidekickId: String
    let sidekickName: String
    /// The record key without `widget:`.
    let widgetId: String
    /// The name the picker shows.
    let name: String
    /// The accent colour of the description, "#RRGGBB"; nil for the system blue.
    let tintHex: String?
    /// False when the description could not be filled: the widget shows "Open Midas".
    let isUsable: Bool
    let looks: [FilledWidgetLook]

    /// "<sidekickId>/<widgetId>": what a placed widget remembers.
    var choiceId: String {
        return Self.choiceId(sidekickId: sidekickId, widgetId: widgetId)
    }

    static func choiceId(sidekickId: String, widgetId: String) -> String {
        return "\(sidekickId)/\(widgetId)"
    }

    /// The look that applies at `date`: the latest one starting at or before it.
    func look(at date: Date) -> FilledWidgetLook? {
        var current: FilledWidgetLook?
        for look in looks where look.from <= date {
            current = look
        }
        return current ?? looks.first
    }
}

struct SharedSidekickWidgets: Codable, Equatable, Sendable {
    /// Bumped when the file's shape changes; a reader ignores a version it does not know.
    static let currentFormatVersion = 1

    let formatVersion: Int
    let savedAt: Date
    let widgets: [FilledSidekickWidget]

    init(widgets: [FilledSidekickWidget], savedAt: Date) {
        self.formatVersion = Self.currentFormatVersion
        self.savedAt = savedAt
        self.widgets = widgets
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Nil for unreadable data or an unknown format version.
    static func decoded(from data: Data) -> SharedSidekickWidgets? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(SharedSidekickWidgets.self, from: data) else {
            return nil
        }
        guard file.formatVersion == currentFormatVersion else {
            return nil
        }
        return file
    }

    static func read(from fileURL: URL?) -> SharedSidekickWidgets? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return decoded(from: data)
    }

    func widget(choiceId: String) -> FilledSidekickWidget? {
        for widget in widgets where widget.choiceId == choiceId {
            return widget
        }
        return nil
    }

    /// The Sidekicks that have at least one widget, in file order, each once.
    func sidekicks() -> [(id: String, name: String)] {
        var seenIds: Set<String> = []
        var sidekicksWithWidgets: [(id: String, name: String)] = []
        for widget in widgets where !seenIds.contains(widget.sidekickId) {
            seenIds.insert(widget.sidekickId)
            sidekicksWithWidgets.append((id: widget.sidekickId, name: widget.sidekickName))
        }
        return sidekicksWithWidgets
    }

    func widgets(ofSidekick sidekickId: String) -> [FilledSidekickWidget] {
        var sidekickWidgets: [FilledSidekickWidget] = []
        for widget in widgets where widget.sidekickId == sidekickId {
            sidekickWidgets.append(widget)
        }
        return sidekickWidgets
    }
}

// MARK: What a placed widget draws

/// What one placed widget draws at one moment.
enum SidekickWidgetScreen: Equatable, Sendable {
    /// Nothing picked yet, and no widget to fall back to.
    case pickSidekick
    /// No file, the widget is gone, or its description could not be filled: "Open Midas".
    case empty(sidekickId: String?)
    case piece(WidgetPiece, sidekickId: String, tintHex: String?)
}

enum SidekickWidgetLayout {
    /// The placed widget's choice: what was picked; with a Sidekick picked but no widget (or a
    /// widget gone), that Sidekick's first widget; with nothing picked, nil.
    static func chosenWidget(file: SharedSidekickWidgets?, sidekickId: String?, widgetChoiceId: String?) -> FilledSidekickWidget? {
        guard let file else {
            return nil
        }
        if let widgetChoiceId, let pickedWidget = file.widget(choiceId: widgetChoiceId) {
            let matchesSidekick = sidekickId == nil || pickedWidget.sidekickId == sidekickId
            if matchesSidekick {
                return pickedWidget
            }
        }
        guard let sidekickId else {
            return nil
        }
        return file.widgets(ofSidekick: sidekickId).first
    }

    static func screen(file: SharedSidekickWidgets?, sidekickId: String?, widgetChoiceId: String?,
                       size: SidekickWidgetSize, at date: Date) -> SidekickWidgetScreen {
        guard sidekickId != nil || widgetChoiceId != nil else {
            return .pickSidekick
        }
        guard let widget = chosenWidget(file: file, sidekickId: sidekickId, widgetChoiceId: widgetChoiceId) else {
            return .empty(sidekickId: sidekickId)
        }
        guard widget.isUsable, let look = widget.look(at: date), let piece = look.piece(for: size) ?? fallbackPiece(look, for: size) else {
            return .empty(sidekickId: widget.sidekickId)
        }
        return .piece(piece, sidekickId: widget.sidekickId, tintHex: widget.tintHex)
    }

    /// A size the description leaves out draws the nearest size it has: medium falls back to
    /// small, large to medium then small, small to medium then large.
    static func fallbackPiece(_ look: FilledWidgetLook, for size: SidekickWidgetSize) -> WidgetPiece? {
        switch size {
        case .small:
            return look.medium ?? look.large
        case .medium:
            return look.small ?? look.large
        case .large:
            return look.medium ?? look.small
        }
    }

    /// When the widget redraws on its own: now and each look's start after now.
    static func timelineDates(widget: FilledSidekickWidget?, now: Date) -> [Date] {
        var dates = [now]
        for look in widget?.looks ?? [] where look.from > now {
            dates.append(look.from)
        }
        return dates
    }
}

// MARK: Taps waiting for the app

struct PendingWidgetAction: Codable, Equatable, Sendable {
    let action: WidgetTapAction
    let tappedAt: Date
}

/// Taps waiting for the app, in an App Group file. Used only when the tap's intent could not run
/// in the app's process; the app applies them at its next launch or return to the front.
enum PendingWidgetActionsFile {
    private struct Contents: Codable {
        let formatVersion: Int
        let actions: [PendingWidgetAction]
    }

    private static let formatVersion = 1

    static func read(from fileURL: URL?) -> [PendingWidgetAction] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let contents = try? decoder.decode(Contents.self, from: data), contents.formatVersion == formatVersion else {
            return []
        }
        return contents.actions
    }

    static func append(_ pendingAction: PendingWidgetAction, to fileURL: URL?) {
        guard let fileURL else {
            return
        }
        var actions = read(from: fileURL)
        actions.append(pendingAction)
        write(actions, to: fileURL)
    }

    static func write(_ actions: [PendingWidgetAction], to fileURL: URL?) {
        guard let fileURL else {
            return
        }
        guard !actions.isEmpty else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let contents = Contents(formatVersion: formatVersion, actions: actions)
        guard let data = try? encoder.encode(contents) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
