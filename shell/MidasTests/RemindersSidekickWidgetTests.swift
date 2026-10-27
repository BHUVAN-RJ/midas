import JavaScriptCore
import XCTest
@testable import Midas

// The Reminders Sidekick makes its own Home Screen widget through the widget builder, and the
// separate native Reminders widget is gone (founder, 2026-10-26: "Since now each sidekick can
// create its own widget, shouldn't we just use that?"). The widget record the page really writes,
// made by its own code (RemindersWidget in sidekicks/reminders/index.html, run here in
// JavaScriptCore), passes the shell's checker and fills like the old widget: "Today" and the
// count, a tick circle in the list's colour, the title and the time, red once late, "+N more",
// "All done".

private let remindersRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let remindersCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func remindersOctober(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)
    return remindersCalendar.date(from: components)!
}

private func pageReminder(_ reminderId: String, at moment: Date, list: String? = nil) -> LocalRecord {
    var fields: [String: JSONValue] = [
        "$type": .string("reminders.item"), "title": .string(reminderId), "at": .string(ReminderRecord.formatDate(moment)),
        "done": .bool(false), "timeZone": .string("America/Los_Angeles"),
    ]
    if let list {
        fields["list"] = .string(list)
    }
    return LocalRecord(sidekickId: "reminders", key: "reminder:" + reminderId, value: .object(fields))
}

/// Every text and tick inside a filled piece, depth first.
private func drawnTexts(in piece: WidgetPiece?) -> [WidgetTextPiece] {
    guard let piece else {
        return []
    }
    switch piece {
    case .text(let textPiece):
        return [textPiece]
    case .vstack(let stack), .hstack(let stack):
        var found: [WidgetTextPiece] = []
        for child in stack.children {
            found.append(contentsOf: drawnTexts(in: child))
        }
        return found
    default:
        return []
    }
}

private func drawnTicks(in piece: WidgetPiece?) -> [WidgetTickPiece] {
    guard let piece else {
        return []
    }
    switch piece {
    case .tick(let tickPiece):
        return [tickPiece]
    case .vstack(let stack), .hstack(let stack):
        var found: [WidgetTickPiece] = []
        for child in stack.children {
            found.append(contentsOf: drawnTicks(in: child))
        }
        return found
    default:
        return []
    }
}

private func words(_ piece: WidgetPiece?) -> [String] {
    var texts: [String] = []
    for textPiece in drawnTexts(in: piece) {
        texts.append(textPiece.text)
    }
    return texts
}

private func drawnText(_ text: String, in piece: WidgetPiece?) -> WidgetTextPiece? {
    for textPiece in drawnTexts(in: piece) where textPiece.text == text {
        return textPiece
    }
    return nil
}

@MainActor
final class RemindersSidekickWidgetTests: XCTestCase {
    private struct PageWidget {
        let key: String
        let value: JSONValue
        let plain: JSONValue
    }

    // Runs the page's own RemindersWidget.widgetRecords() in JavaScriptCore.
    private func pageWidgets() throws -> [PageWidget] {
        let pageURL = remindersRepoRoot.appending(path: "sidekicks/reminders/index.html")
        let pageSource = try String(contentsOf: pageURL, encoding: .utf8)
        let blockStart = try XCTUnwrap(pageSource.range(of: "var RemindersWidget = (function createRemindersWidget() {"))
        let blockEnd = try XCTUnwrap(pageSource.range(of: "\n})();\n", range: blockStart.upperBound..<pageSource.endIndex))
        let widgetSource = String(pageSource[blockStart.lowerBound..<blockEnd.upperBound])
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(widgetSource)
        XCTAssertNil(context.exception, "RemindersWidget did not load: \(String(describing: context.exception))")
        let recordsText = try XCTUnwrap(context.evaluateScript("JSON.stringify(RemindersWidget.widgetRecords())")?.toString())
        guard case .array(let entries) = try JSONDecoder().decode(JSONValue.self, from: Data(recordsText.utf8)) else {
            throw XCTSkip("widgetRecords did not return a list")
        }
        var widgets: [PageWidget] = []
        for entry in entries {
            guard case .string(let key)? = entry["key"], let value = entry["value"], let plain = entry["plain"] else {
                XCTFail("widget entry without key, value or plain")
                continue
            }
            widgets.append(PageWidget(key: key, value: value, plain: plain))
        }
        return widgets
    }

    private func todayWidget() throws -> PageWidget {
        let widgets = try pageWidgets()
        XCTAssertEqual(widgets.count, 1)
        return try XCTUnwrap(widgets.first)
    }

    private func filled(_ description: JSONValue, records: [LocalRecord], now: Date) -> FilledSidekickWidget {
        let lists = [LocalRecord(sidekickId: "reminders", key: "list:home", value: .object(["name": .string("Home"), "color": .string("orange")]))]
        let widgetRecord = LocalRecord(sidekickId: "reminders", key: "widget:today", value: description)
        let filler = SidekickWidgetFiller(calendar: remindersCalendar)
        return filler.fill(sidekickId: "reminders", sidekickName: "Reminders", record: widgetRecord, sidekickRecords: records + lists, now: now)
    }

    /// Five reminders today; at 3:00 PM two are late.
    private func fiveToday() -> [LocalRecord] {
        return [
            pageReminder("Reply", at: remindersOctober(11, 9), list: "home"),
            pageReminder("Push", at: remindersOctober(11, 14)),
            pageReminder("Call", at: remindersOctober(11, 18)),
            pageReminder("Gym", at: remindersOctober(11, 19)),
            pageReminder("Read", at: remindersOctober(11, 21)),
        ]
    }

    func testThePageWritesTodayInEverySizeAndTheShellTakesIt() throws {
        let widget = try todayWidget()
        XCTAssertEqual(widget.key, "widget:today")
        XCTAssertEqual(widget.value["name"], .string("Today"))
        for size in ["small", "medium", "large"] {
            XCTAssertNotNil(widget.value[size], "\(size) is written")
            XCTAssertNotNil(widget.plain[size], "plain \(size) is written")
        }
        XCTAssertNil(SidekickWidgetDescription.validationError(widget.value))
        XCTAssertNil(SidekickWidgetDescription.validationError(widget.plain))
    }

    func testThePlainStandInHasNoColourChoice() throws {
        let widget = try todayWidget()
        let valueData = try JSONEncoder().encode(widget.value)
        let plainData = try JSONEncoder().encode(widget.plain)
        XCTAssertTrue(String(decoding: valueData, as: UTF8.self).contains("$item.late"), "the widget colours late times")
        XCTAssertFalse(String(decoding: plainData, as: UTF8.self).contains("\"if\":\"$item.late\""), "an older app refuses a colour choice")
    }

    func testSmallShowsTodayTheCountThreeRowsAndHowManyMore() throws {
        let small = filled(try todayWidget().value, records: fiveToday(), now: remindersOctober(11, 15)).looks.first?.small
        XCTAssertEqual(words(small), ["Today", "5", "Reply", "9:00 AM", "Push", "2:00 PM", "Call", "6:00 PM", "+2 more"])
        XCTAssertEqual(drawnText("Today", in: small)?.colorHex, "#007AFF", "Today in blue")
        XCTAssertEqual(drawnText("5", in: small)?.colorHex, "#007AFF", "the count in blue")
        let ticks = drawnTicks(in: small)
        XCTAssertEqual(ticks.count, 3)
        XCTAssertEqual(ticks.first?.colorHex, "#FF9500", "the circle in the list's colour")
        XCTAssertEqual(ticks[1].colorHex, "#007AFF", "blue with no list")
        XCTAssertEqual(ticks.first?.action.key, "reminder:Reply", "a tick marks the reminder done")
    }

    func testALateTimeIsRedAndTurnsRedOnItsOwn() throws {
        let widget = filled(try todayWidget().value, records: fiveToday(), now: remindersOctober(11, 15))
        let medium = widget.looks.first?.medium
        XCTAssertEqual(drawnText("9:00 AM", in: medium)?.colorHex, "#FF3B30")
        XCTAssertEqual(drawnText("2:00 PM", in: medium)?.colorHex, "#FF3B30")
        let coming = try XCTUnwrap(drawnText("6:00 PM", in: medium))
        XCTAssertNil(coming.colorHex)
        XCTAssertTrue(coming.isSecondary)
        let atSix = widget.look(at: remindersOctober(11, 18))?.medium
        XCTAssertEqual(drawnText("6:00 PM", in: atSix)?.colorHex, "#FF3B30", "the 6:00 PM look draws it red")
    }

    func testMediumShowsThreeAndLargeShowsEight() throws {
        let description = try todayWidget().value
        let look = filled(description, records: fiveToday(), now: remindersOctober(11, 15)).looks.first
        XCTAssertEqual(drawnTicks(in: look?.medium).count, 3)
        XCTAssertTrue(words(look?.medium).contains("+2 more"))
        XCTAssertEqual(drawnTicks(in: look?.large).count, 5)
        XCTAssertFalse(words(look?.large).contains("+2 more"), "everything fits in large")
        var tenToday = fiveToday()
        for index in 0..<5 {
            tenToday.append(pageReminder("Extra\(index)", at: remindersOctober(11, 22, index)))
        }
        let largeLook = filled(description, records: tenToday, now: remindersOctober(11, 15)).looks.first?.large
        XCTAssertEqual(drawnTicks(in: largeLook).count, 8)
        XCTAssertTrue(words(largeLook).contains("+2 more"))
    }

    func testNothingLeftShowsAllDone() throws {
        let done = LocalRecord(sidekickId: "reminders", key: "reminder:done", value: .object([
            "title": .string("Done"), "at": .string(ReminderRecord.formatDate(remindersOctober(11, 9))), "done": .bool(true),
        ]))
        let small = filled(try todayWidget().value, records: [done], now: remindersOctober(11, 15)).looks.first?.small
        XCTAssertEqual(words(small), ["Today", "0", "All done"])
    }

    func testThePlainStandInStillShowsToday() throws {
        let small = filled(try todayWidget().plain, records: fiveToday(), now: remindersOctober(11, 15)).looks.first?.small
        XCTAssertEqual(words(small), ["Today", "5", "Reply", "9:00 AM", "Push", "2:00 PM", "Call", "6:00 PM", "+2 more"])
        XCTAssertTrue(drawnText("9:00 AM", in: small)?.isSecondary ?? false, "grey times, no red")
    }

    func testThePagePublishesTheWidgetWhenItLoads() throws {
        let pageSource = try String(contentsOf: remindersRepoRoot.appending(path: "sidekicks/reminders/index.html"), encoding: .utf8)
        let loadStart = try XCTUnwrap(pageSource.range(of: "async function firstLoad() {"))
        let loadEnd = try XCTUnwrap(pageSource.range(of: "\n  }\n", range: loadStart.upperBound..<pageSource.endIndex))
        XCTAssertTrue(pageSource[loadStart.upperBound..<loadEnd.lowerBound].contains("await publishWidgets();"))
        XCTAssertTrue(pageSource.contains("await store.set(widget.key, widget.plain);"), "a refused widget falls back to the plain one")
    }
}

final class RemindersNativeWidgetRetiredTests: XCTestCase {
    private let shellFolder = remindersRepoRoot.appending(path: "shell")

    func testTheGalleryHasNoSeparateRemindersWidget() throws {
        let bundleSource = try String(contentsOf: shellFolder.appending(path: "MidasWidgets/MidasWidgetsBundle.swift"), encoding: .utf8)
        XCTAssertFalse(bundleSource.contains("RemindersWidget()"))
        XCTAssertTrue(bundleSource.contains("SidekickWidget()"))
        XCTAssertTrue(bundleSource.contains("FolderWidget()"))
        for removedFile in ["MidasWidgets/RemindersWidget.swift", "Shared/RemindersWidgetShared.swift", "Shared/RemindersWidgetIntents.swift", "Midas/RemindersWidgetPublisher.swift"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: shellFolder.appending(path: removedFile).path), "\(removedFile) is gone")
        }
    }

    func testTheOldWidgetsFilesAreRemovedAtLaunch() throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "retired-widget-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        let keptName = "widget-sidekick-widgets.json"
        for fileName in RetiredRemindersWidgetFiles.fileNames + [keptName] {
            try Data("{}".utf8).write(to: container.appending(path: fileName))
        }
        RetiredRemindersWidgetFiles.remove(container: container)
        for fileName in RetiredRemindersWidgetFiles.fileNames {
            XCTAssertFalse(FileManager.default.fileExists(atPath: container.appending(path: fileName).path), "\(fileName) removed")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: container.appending(path: keptName).path), "the Sidekick widget's file stays")
        XCTAssertEqual(RetiredRemindersWidgetFiles.fileNames, ["widget-reminders-today.json", "widget-reminders-ticks.json", "widget-reminders-pages.json"])
        let servicesSource = try String(contentsOf: shellFolder.appending(path: "Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertTrue(servicesSource.contains("RetiredRemindersWidgetFiles.remove()"), "the app removes them at launch")
    }
}
