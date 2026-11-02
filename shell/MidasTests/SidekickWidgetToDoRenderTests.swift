import JavaScriptCore
import SwiftUI
import UIKit
import XCTest
@testable import Midas

// The To-Do widget drawn (founder, 2026-11-02; docs/WIDGETS.md "Every Sidekick ships a widget",
// done check 3: renders in light and dark). The description comes from the page's own TodoWidget
// (sidekicks/todo/index.html) with the default settings ("Mine": Notebook, accent #2F6FEB, tick at
// the end, Carry Over), filled through the shell's `planned` source and drawn by the widget's own
// views. Checked on the pixels: the Notebook paper by day and its night paper, and the accent ticks.
// Renders are saved when MIDAS_WIDGET_RENDER_DIR is set (docs/mockups/todo-widget-2026-11-02-{light,dark}.png).

private let toDoRenderRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let toDoRenderCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private func toDoRenderJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func toDoRenderMoment(_ day: Int, _ hour: Int) -> Date {
    return toDoRenderCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
}

/// A rendered image's pixels, row 0 at the top.
private struct ToDoPixels {
    let width: Int
    let height: Int
    let scale: CGFloat
    let bytes: [UInt8]

    init?(_ image: UIImage) {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let pixelWidth = cgImage.width
        let pixelHeight = cgImage.height
        var buffer = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let drawn: Bool = buffer.withUnsafeMutableBytes { bufferPointer in
            guard let context = CGContext(data: bufferPointer.baseAddress, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
                                          bytesPerRow: pixelWidth * 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            return true
        }
        guard drawn else {
            return nil
        }
        width = pixelWidth
        height = pixelHeight
        scale = image.scale
        bytes = buffer
    }

    func rgb(column: Int, row: Int) -> (Int, Int, Int) {
        let offset = (row * width + column) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    /// How many pixels are within `tolerance` (per channel) of the colour.
    func count(near hex: String, tolerance: Int) -> Int {
        guard let target = SidekickColor.rgbComponents(fromHex: hex) else {
            return 0
        }
        let red = Int(target.red * 255)
        let green = Int(target.green * 255)
        let blue = Int(target.blue * 255)
        var matches = 0
        for row in 0..<height {
            for column in 0..<width {
                let pixel = rgb(column: column, row: row)
                if abs(pixel.0 - red) <= tolerance && abs(pixel.1 - green) <= tolerance && abs(pixel.2 - blue) <= tolerance {
                    matches += 1
                }
            }
        }
        return matches
    }

    func isNear(_ hex: String, atX x: CGFloat, y: CGFloat, tolerance: Int) -> Bool {
        guard let target = SidekickColor.rgbComponents(fromHex: hex) else {
            return false
        }
        let pixel = rgb(column: Int(x * scale), row: Int(y * scale))
        return abs(pixel.0 - Int(target.red * 255)) <= tolerance && abs(pixel.1 - Int(target.green * 255)) <= tolerance
            && abs(pixel.2 - Int(target.blue * 255)) <= tolerance
    }
}

@MainActor
final class SidekickWidgetToDoRenderTests: XCTestCase {
    private let noonOnMonday = toDoRenderMoment(2, 12)

    /// The widget the page writes with its default settings, from the page's own code.
    private func toDoWidgetFromItsPage() throws -> JSONValue {
        let pageSource = try String(contentsOf: toDoRenderRepoRoot.appending(path: "sidekicks/todo/index.html"), encoding: .utf8)
        let logicStart = try XCTUnwrap(pageSource.range(of: "var TodoLogic = (function createTodoLogic() {"))
        let widgetStart = try XCTUnwrap(pageSource.range(of: "var TodoWidget = (function createTodoWidget() {"))
        let blockEnd = try XCTUnwrap(pageSource.range(of: "\n})();\n", range: widgetStart.upperBound..<pageSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(pageSource[logicStart.lowerBound..<blockEnd.upperBound]))
        XCTAssertNil(context.exception)
        let script = "JSON.stringify(TodoWidget.widgetDescription(TodoLogic.DEFAULT_SETTINGS))"
        let widgetText = try XCTUnwrap(context.evaluateScript(script)?.toString())
        XCTAssertNil(context.exception)
        return toDoRenderJSON(widgetText)
    }

    private func toDo(_ id: String, _ title: String, when: String, time: String? = nil, order: Int, doneAt: Date? = nil) -> LocalRecord {
        var fields: [String: JSONValue] = [
            "$type": .string("todo.item"), "title": .string(title), "when": .string(when), "order": .number(Double(order)),
        ]
        if let time {
            fields["time"] = .string(time)
        }
        if let doneAt {
            fields["done"] = .bool(true)
            fields["completedAt"] = .string(ReminderRecord.formatDate(doneAt))
        }
        return LocalRecord(sidekickId: "todo", key: "reminder:" + id, value: .object(fields))
    }

    /// The mockup's day: 10 open, two carried over from the weekend, two with a time.
    private func typicalDay() -> [LocalRecord] {
        return [
            toDo("rent", "Pay rent", when: "2026-10-31", order: 1),
            toDo("call", "Call dad", when: "2026-11-02", time: "17:00", order: 2),
            toDo("sam", "Email Sam about the trip", when: "2026-11-02", order: 3),
            toDo("groceries", "Groceries: eggs, milk, bread", when: "2026-11-02", order: 4),
            toDo("gym", "Gym", when: "2026-11-02", order: 5),
            toDo("dentist", "Book dentist", when: "2026-11-01", order: 6),
            toDo("plants", "Water the plants", when: "2026-11-02", time: "20:00", order: 7),
            toDo("read", "Read 20 pages", when: "2026-11-02", order: 8),
            toDo("library", "Return the library books before they charge a late fee", when: "2026-11-02", order: 9),
            toDo("weekend", "Plan the weekend", when: "2026-11-02", order: 10),
        ]
    }

    private func allDoneDay() -> [LocalRecord] {
        return [toDo("rent", "Pay rent", when: "2026-11-02", order: 1, doneAt: toDoRenderMoment(2, 9))]
    }

    private func screen(widget: JSONValue, records: [LocalRecord], size: SidekickWidgetSize) -> SidekickWidgetScreen {
        let widgetRecord = LocalRecord(sidekickId: "todo", key: "widget:today", value: widget)
        let filler = SidekickWidgetFiller(calendar: toDoRenderCalendar)
        let filled = filler.fill(sidekickId: "todo", sidekickName: "To-Do", record: widgetRecord, sidekickRecords: records + [widgetRecord], now: noonOnMonday)
        let file = SharedSidekickWidgets(widgets: [filled], savedAt: noonOnMonday)
        return SidekickWidgetLayout.screen(file: file, sidekickId: "todo", widgetChoiceId: filled.choiceId, size: size, at: noonOnMonday)
    }

    private func image<Content: View>(_ content: Content, colorScheme: ColorScheme) throws -> UIImage {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        // Drawn twice, the first one thrown away (a first drawing once came back blank)
        _ = renderer.uiImage
        return try XCTUnwrap(renderer.uiImage)
    }

    private func sheet(widget: JSONValue, colorScheme: ColorScheme) -> some View {
        let wall = colorScheme == .dark ? Color(red: 0.22, green: 0.24, blue: 0.28) : Color(red: 0.86, green: 0.89, blue: 0.93)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                SidekickWidgetSnapshot(screen: screen(widget: widget, records: typicalDay(), size: .small), size: .small)
                SidekickWidgetSnapshot(screen: screen(widget: widget, records: allDoneDay(), size: .small), size: .small)
                SidekickWidgetSnapshot(screen: screen(widget: widget, records: [], size: .small), size: .small)
            }
            SidekickWidgetSnapshot(screen: screen(widget: widget, records: typicalDay(), size: .medium), size: .medium)
            SidekickWidgetSnapshot(screen: screen(widget: widget, records: typicalDay(), size: .large), size: .large)
        }
        .padding(20)
        .background(wall)
    }

    func testTheToDoWidgetIsTheNotebookPaperByDayAndItsNightPaperInDarkMode() throws {
        let widget = try toDoWidgetFromItsPage()
        XCTAssertNil(SidekickWidgetDescription.validationError(widget))
        let looks: [(scheme: ColorScheme, name: String, paper: String, accent: String)] = [
            (.light, "light", "#FCFBF7", "#2F6FEB"),
            (.dark, "dark", "#141414", "#5B8DEF"),
        ]
        for look in looks {
            for size in [SidekickWidgetSize.small, .medium, .large] {
                let drawn = try image(SidekickWidgetSnapshot(screen: screen(widget: widget, records: typicalDay(), size: size), size: size), colorScheme: look.scheme)
                let pixels = try XCTUnwrap(ToDoPixels(drawn))
                // The bottom margin is the widget's own paper
                let bottomMiddle = SidekickWidgetSnapshot.height(of: size) - 5
                XCTAssertTrue(pixels.isNear(look.paper, atX: SidekickWidgetSnapshot.width(of: size) / 2, y: bottomMiddle, tolerance: 3), "\(look.name) \(size): paper")
                // The ticks and the header are drawn in the accent
                XCTAssertGreaterThan(pixels.count(near: look.accent, tolerance: 12), 200, "\(look.name) \(size): accent")
            }
            let sheetImage = try image(sheet(widget: widget, colorScheme: look.scheme), colorScheme: look.scheme)
            if let renderFolder = ProcessInfo.processInfo.environment["MIDAS_WIDGET_RENDER_DIR"], !renderFolder.isEmpty {
                let fileURL = URL(fileURLWithPath: renderFolder).appending(path: "todo-widget-2026-11-02-\(look.name).png")
                try XCTUnwrap(sheetImage.pngData()).write(to: fileURL)
            }
        }
    }

    func testEmptyStatesDrawTheirWordsNotOpenMidas() throws {
        let widget = try toDoWidgetFromItsPage()
        for (records, word) in [(allDoneDay(), "All Done"), ([LocalRecord](), "Nothing Today")] {
            guard case .piece = screen(widget: widget, records: records, size: .small) else {
                return XCTFail("\(word): the widget showed Open Midas")
            }
            let filler = SidekickWidgetFiller(calendar: toDoRenderCalendar)
            let widgetRecord = LocalRecord(sidekickId: "todo", key: "widget:today", value: widget)
            let filled = filler.fill(sidekickId: "todo", sidekickName: "To-Do", record: widgetRecord, sidekickRecords: records + [widgetRecord], now: noonOnMonday)
            let encoded = String(data: try JSONEncoder().encode(filled.looks.first?.small), encoding: .utf8) ?? ""
            XCTAssertTrue(encoded.contains(word), word)
        }
    }
}
