import JavaScriptCore
import XCTest
@testable import Midas

// Hydration plan step 8 (founder, 2026-10-25; docs/briefs/hydration-sidekick.md section 3): the
// widget records the Water Sidekick really writes, made by its own code (WaterLogic in tools.js,
// copied verbatim from index.html), pass the shell's widget checker and fill correctly. The two
// halves were built on separate branches; this is the check that they fit after the merge.

private let crossCheckRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let crossCheckCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func octoberInLosAngeles(_ day: Int, _ hour: Int) -> Date {
    let components = DateComponents(year: 2026, month: 10, day: day, hour: hour)
    return crossCheckCalendar.date(from: components)!
}

private func decodedJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@MainActor
final class HydrationWidgetCrossCheckTests: XCTestCase {
    private struct PageWidget {
        let key: String
        let tide: JSONValue
        let plain: JSONValue
    }

    // Runs the Sidekick's own widgetRecords(settings) in JavaScriptCore.
    private func pageWidgets(unit: String) throws -> [PageWidget] {
        let toolsURL = crossCheckRepoRoot.appending(path: "sidekicks/hydration/tools.js")
        let toolsSource = try String(contentsOf: toolsURL, encoding: .utf8)
        // WaterLogic lives inside the tools' wrapper; its first copied block is the page's own
        // code, so that block alone makes WaterLogic a global.
        let beginMarker = "/* copied from index.html: begin */"
        let endMarker = "/* copied from index.html: end */"
        let beginRange = try XCTUnwrap(toolsSource.range(of: beginMarker))
        let endRange = try XCTUnwrap(toolsSource.range(of: endMarker, range: beginRange.upperBound..<toolsSource.endIndex))
        let pageLogicSource = String(toolsSource[beginRange.upperBound..<endRange.lowerBound])
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(pageLogicSource)
        XCTAssertNil(context.exception, "tools.js did not load: \(String(describing: context.exception))")
        let settingsScript = "WaterLogic.settingsFrom({ goalMl: 2500, unit: '\(unit)' })"
        let recordsScript = "JSON.stringify(WaterLogic.widgetRecords(\(settingsScript)))"
        let recordsText = try XCTUnwrap(context.evaluateScript(recordsScript)?.toString())
        let recordsData = Data(recordsText.utf8)
        guard case .array(let entries) = try JSONDecoder().decode(JSONValue.self, from: recordsData) else {
            throw XCTSkip("widgetRecords did not return a list")
        }
        var widgets: [PageWidget] = []
        for entry in entries {
            guard case .string(let key)? = entry["key"], let tide = entry["value"], let plain = entry["plain"] else {
                XCTFail("widget entry without key, value or plain")
                continue
            }
            widgets.append(PageWidget(key: key, tide: tide, plain: plain))
        }
        return widgets
    }

    private func widget(_ key: String, unit: String) throws -> PageWidget {
        let widgets = try pageWidgets(unit: unit)
        for pageWidget in widgets where pageWidget.key == key {
            return pageWidget
        }
        throw XCTSkip("no \(key) from the page")
    }

    // Today (Oct 25) at `todayMl`, plus `pastDays` earlier days each at the goal.
    private func records(widget: JSONValue, widgetKey: String, todayMl: Int, pastDays: Int) -> [LocalRecord] {
        var all = [
            LocalRecord(sidekickId: "hydration", key: widgetKey, value: widget),
            LocalRecord(sidekickId: "hydration", key: "settings:main", value: decodedJSON(#"{ "goalMl": 2500, "unit": "l" }"#)),
            LocalRecord(sidekickId: "hydration", key: "water:2026-10-25", value: decodedJSON(#"{ "ml": \#(todayMl) }"#)),
        ]
        if pastDays > 0 {
            for daysBack in 1...pastDays {
                let day = String(format: "%02d", 25 - daysBack)
                all.append(LocalRecord(sidekickId: "hydration", key: "water:2026-10-\(day)", value: decodedJSON(#"{ "ml": 2500, "goalMl": 2500 }"#)))
            }
        }
        return all
    }

    private func filledLook(widgetKey: String, unit: String, todayMl: Int, pastDays: Int) throws -> FilledWidgetLook {
        let tide = try widget(widgetKey, unit: unit).tide
        let allRecords = records(widget: tide, widgetKey: widgetKey, todayMl: todayMl, pastDays: pastDays)
        let filler = SidekickWidgetFiller(calendar: crossCheckCalendar)
        let filled = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: allRecords[0], sidekickRecords: allRecords, now: octoberInLosAngeles(25, 15))
        return try XCTUnwrap(filled.looks.first)
    }

    private func encodedText(_ piece: WidgetPiece?) throws -> String {
        let data = try JSONEncoder().encode(piece)
        return String(decoding: data, as: UTF8.self)
    }

    // Every "values" list anywhere in a filled piece (the chart's bars).
    private func chartValueLists(in piece: WidgetPiece?) throws -> [[Double]] {
        let data = try JSONEncoder().encode(piece)
        let tree = try JSONSerialization.jsonObject(with: data)
        var found: [[Double]] = []
        collectValueLists(tree, into: &found)
        return found
    }

    private func collectValueLists(_ node: Any, into found: inout [[Double]]) {
        if let dictionary = node as? [String: Any] {
            if let values = dictionary["values"] as? [Double] {
                found.append(values)
            }
            for child in dictionary.values {
                collectValueLists(child, into: &found)
            }
        } else if let array = node as? [Any] {
            for child in array {
                collectValueLists(child, into: &found)
            }
        }
    }

    func testEveryWidgetThePageWritesPassesTheShellChecker() throws {
        for unit in ["ml", "l", "oz"] {
            let widgets = try pageWidgets(unit: unit)
            // One Water widget (founder, 2026-10-27, docs/PRODUCT.md "One Water widget")
            XCTAssertEqual(widgets.map(\.key).sorted(), ["widget:today"])
            for pageWidget in widgets {
                XCTAssertNil(SidekickWidgetDescription.validationError(pageWidget.tide), "\(pageWidget.key) Tide, \(unit)")
                XCTAssertNil(SidekickWidgetDescription.validationError(pageWidget.plain), "\(pageWidget.key) plain, \(unit)")
            }
        }
    }

    func testTheTodayWidgetSeaIsTheDaysShareOfTheGoal() throws {
        let empty = try filledLook(widgetKey: "widget:today", unit: "l", todayMl: 0, pastDays: 0)
        let half = try filledLook(widgetKey: "widget:today", unit: "l", todayMl: 1250, pastDays: 0)
        let over = try filledLook(widgetKey: "widget:today", unit: "l", todayMl: 2750, pastDays: 0)
        let emptySmall = try XCTUnwrap(empty.small)
        let halfSmall = try XCTUnwrap(half.small)
        let overSmall = try XCTUnwrap(over.small)
        XCTAssertEqual(SidekickWidgetSurface.edgeFill(of: emptySmall)?.fraction, 0)
        XCTAssertEqual(SidekickWidgetSurface.edgeFill(of: halfSmall)?.fraction, 0.5)
        XCTAssertEqual(SidekickWidgetSurface.edgeFill(of: overSmall)?.fraction, 1)
        XCTAssertNotNil(SidekickWidgetSurface.background(of: halfSmall), "the sand background is drawn")
    }

    func testTheTodayWidgetShowsThePersonsUnit() throws {
        let litres = try filledLook(widgetKey: "widget:today", unit: "l", todayMl: 1250, pastDays: 0)
        XCTAssertTrue(try encodedText(litres.medium).contains("1.25 L"), "litres shown as 1.25 L")
        let ounces = try filledLook(widgetKey: "widget:today", unit: "oz", todayMl: 1250, pastDays: 0)
        XCTAssertTrue(try encodedText(ounces.medium).contains("42 oz"), "1,250 ml shown as 42 oz")
        XCTAssertFalse(try encodedText(ounces.medium).contains("1250"), "no raw ml when the unit is oz")
    }

    func testTheTodayWidgetButtonsAddToTodaysRecord() throws {
        let look = try filledLook(widgetKey: "widget:today", unit: "ml", todayMl: 0, pastDays: 0)
        let medium = try encodedText(look.medium)
        XCTAssertTrue(medium.contains("water:{today}") || medium.contains("water:2026-10-25"), "taps write today's day record")
        XCTAssertFalse(medium.contains("reminder:"), "a widget tap never writes a reminder")
    }

    func testTheStreakCountsTheDaysAtTheGoal() throws {
        let look = try filledLook(widgetKey: "widget:today", unit: "ml", todayMl: 2500, pastDays: 3)
        XCTAssertTrue(try encodedText(look.medium).contains("4 day"), "3 earlier days at the goal plus today")
    }

    // The week chart is on widget:today's large size since the one Water widget (founder, 2026-10-27)
    func testTheWeekChartHasTheLastSevenDays() throws {
        let look = try filledLook(widgetKey: "widget:today", unit: "ml", todayMl: 1000, pastDays: 10)
        let lists = try chartValueLists(in: look.large)
        let chartValues = try XCTUnwrap(lists.first, "the large size has the week chart")
        XCTAssertEqual(chartValues.count, 7)
        XCTAssertEqual(chartValues.last, 1000, "today is the last bar")
    }
}
