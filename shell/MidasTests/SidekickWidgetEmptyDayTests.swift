import XCTest
@testable import Midas

// Founder, 2026-10-27: "even though I choose the widget then choose Water... it just says Open
// Midas". Water's widget is one fill (the sea) with its text and buttons on top. On a day with
// nothing logged yet there is no water:{today} record, the fill's value resolved to nothing, and
// the filler dropped the whole look, so the widget showed "Open Midas" until the person logged
// water in the app. The widget and records below are copied from the founder's phone (Midas
// Test build 18, 2026-10-26 22:17 PT: no record for the 26th).

private let phoneCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func phoneJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private let phoneWaterWidget = phoneJSON(##"{"$type":"midas.widget","background":"#F4EEE3","medium":{"color":"#9CCFD3","content":{"align":"leading","spacing":2,"vstack":[{"format":"l","if":"$day.ml","style":"title","text":"$day.ml"},{"style":"title","text":"0 L","unless":"$day.ml"},{"color":"secondary","format":"l","style":"caption","text":"of $settings.goalMl"},{"color":"secondary","if":"$streak.days","style":"caption","text":"$streak.days day streak"},{"spacer":true},{"hstack":[{"action":{"by":250,"field":"ml","increment":"water:{today}"},"button":"+0.25 L"},{"action":{"by":500,"field":"ml","increment":"water:{today}"},"button":"+0.5 L"},{"action":{"by":750,"field":"ml","increment":"water:{today}"},"button":"+0.75 L"}],"spacing":6}]},"edge":"wave","fill":{"of":"$settings.goalMl","value":"$day.ml"}},"name":"Water today","small":{"color":"#9CCFD3","content":{"align":"leading","spacing":2,"vstack":[{"format":"l","if":"$day.ml","style":"title","text":"$day.ml"},{"style":"title","text":"0 L","unless":"$day.ml"},{"color":"secondary","format":"l","style":"caption","text":"of $settings.goalMl"},{"color":"secondary","if":"$streak.days","style":"caption","text":"$streak.days day streak"},{"spacer":true},{"action":{"by":250,"field":"ml","increment":"water:{today}"},"button":"+0.25 L"}]},"edge":"wave","fill":{"of":"$settings.goalMl","value":"$day.ml"}},"sources":{"day":{"record":"water:{today}"},"settings":{"record":"settings:main"},"streak":{"records":"water:","streak":{"dayGoalField":"goalMl","field":"ml","goal":"$settings.goalMl"}}},"tint":"#2F7E87","version":1}"##)
private let phoneWaterSettings = phoneJSON(##"{"$type":"hydration.settings","createdAt":"2026-10-25T22:00:26.541Z","everyHours":2,"goalMl":2500,"presetsMl":[250,500,750],"remindEnd":"21:00","remindStart":"09:00","remindersOn":true,"unit":"l"}"##)
private let phoneWaterYesterday = phoneJSON(##"{"$type":"hydration.day","entries":[{"at":"2026-10-25T22:00:28.391Z","ml":500},{"at":"2026-10-26T00:37:20.216Z","ml":750}],"goalMl":2500,"ml":4000}"##)

@MainActor
final class SidekickWidgetEmptyDayTests: XCTestCase {
    private let lateOnThe26th = phoneCalendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 22, minute: 17))!

    private func filledOnAnEmptyDay() -> FilledSidekickWidget {
        let widgetRecord = LocalRecord(sidekickId: "hydration", key: "widget:today", value: phoneWaterWidget)
        let records = [
            widgetRecord,
            LocalRecord(sidekickId: "hydration", key: "settings:main", value: phoneWaterSettings),
            LocalRecord(sidekickId: "hydration", key: "water:2026-10-25", value: phoneWaterYesterday),
        ]
        let filler = SidekickWidgetFiller(calendar: phoneCalendar)
        return filler.fill(sidekickId: "hydration", sidekickName: "Water", record: widgetRecord, sidekickRecords: records, now: lateOnThe26th)
    }

    private func texts(in piece: WidgetPiece?) -> [String] {
        var found: [String] = []
        switch piece {
        case .text(let textPiece)?:
            found.append(textPiece.text)
        case .button(let buttonPiece)?:
            found.append(buttonPiece.title)
        case .vstack(let stack)?, .hstack(let stack)?:
            for child in stack.children {
                found += texts(in: child)
            }
        default:
            break
        }
        return found
    }

    func testAnEmptyDayDrawsTheWidgetNotOpenMidas() {
        let filled = filledOnAnEmptyDay()
        let file = SharedSidekickWidgets(widgets: [filled], savedAt: lateOnThe26th)
        for size in [SidekickWidgetSize.small, .medium] {
            let screen = SidekickWidgetLayout.screen(file: file, sidekickId: "hydration", widgetChoiceId: filled.choiceId, size: size, at: lateOnThe26th)
            guard case .piece = screen else {
                return XCTFail("\(size): \(screen), the widget showed Open Midas")
            }
        }
    }

    func testAnEmptyDayIsAnEmptySeaWithZeroAndTheButton() throws {
        let small = try XCTUnwrap(filledOnAnEmptyDay().looks.first?.small)
        XCTAssertEqual(SidekickWidgetSurface.edgeFill(of: small)?.fraction, 0)
        let shown = texts(in: SidekickWidgetSurface.foreground(of: small))
        // The 25th met the goal (4 L of 2.5 L), so yesterday's streak still shows
        XCTAssertEqual(shown, ["0 L", "of 2.5 L", "1 day streak", "+0.25 L"])
    }

    func testAFillWithoutAGoalStillDrawsNothing() {
        // Only a missing value means "nothing yet"; a fill whose total resolves to nothing is broken
        let noGoal = phoneJSON(##"{ "name": "W", "small": { "fill": { "value": "$day.ml", "of": "$settings.goalMl" } }, "sources": { "day": { "record": "water:{today}" }, "settings": { "record": "settings:none" } } }"##)
        let widgetRecord = LocalRecord(sidekickId: "hydration", key: "widget:today", value: noGoal)
        let filler = SidekickWidgetFiller(calendar: phoneCalendar)
        let filled = filler.fill(sidekickId: "hydration", sidekickName: "Water", record: widgetRecord, sidekickRecords: [widgetRecord], now: lateOnThe26th)
        XCTAssertNil(filled.looks.first?.small)
    }
}
