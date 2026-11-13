#if MIDAS_TEST_BUILD
// Dictation Sidekick wiring (TEST BUILD, founder 2026-11-13; docs/briefs/dictation-sidekick-test.md).
// Compiled only against a Test build: run with the "Midas Test" scheme's test action.
//
// The page's "test.dictation" request reaches DictationTestCenter (not the Reminders import, which
// would refuse it), the screen opens, every run is saved as a `run:` record plus `summary:main`
// that pass the Sidekick's real manifest types through the store's write gate, the request ends
// "done" with the runs it saved, and the shell tells the page it can open the screen. The widget
// from the page's own code passes the shell's checker and fills from summary:main; light and dark
// renders are saved when MIDAS_WIDGET_RENDER_DIR is set (docs/mockups/dictation-widget-*.png).
import JavaScriptCore
import SwiftUI
import UIKit
import XCTest
@testable import Midas

private let dictationRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func dictationJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// Never asked: a dictation request must not reach the Reminders import.
@MainActor
private final class UnusedRemindersSource: PhoneRemindersSource {
    private(set) var asked = false

    func requestAccess() async -> Bool {
        asked = true
        return false
    }

    func readAll() async throws -> (lists: [PhoneReminderList], reminders: [PhoneReminder]) {
        asked = true
        return ([], [])
    }
}

@MainActor
final class DictationSidekickWiringTests: XCTestCase {
    private var storeURL: URL!
    private let device = DictationDeviceInfo(device: "iPhone17,1", ios: "26.1", build: "25")
    private let fixedNow = Date(timeIntervalSince1970: 1_763_070_000)

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory.appending(path: "dictation-wiring-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func manifestTypes() throws -> JSONValue {
        let manifestURL = dictationRepoRoot.appending(path: "sidekicks/dictation/manifest.json")
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        return try XCTUnwrap(manifest["types"])
    }

    /// A store whose write gate checks the Dictation Sidekick's real manifest types.
    private func gatedStore() throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: storeURL)
        let types = try manifestTypes()
        func typesFor(_ sidekickId: String) -> JSONValue? {
            sidekickId == DictationRunRecord.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: try RecordSchemaEngine(), typesProvider: typesFor)
        return store
    }

    private func clock() -> Date {
        fixedNow
    }

    private func pendingRequest() -> JSONValue {
        dictationJSON(#"{ "kind": "test.dictation", "status": "pending", "createdAt": "2026-11-13T21:00:00Z" }"#)
    }

    private func phraseRun(cleanupMs: Int, secondsAfter: Double, firstCall: Bool = false) -> DictationRun {
        DictationRun(at: fixedNow.addingTimeInterval(secondsAfter), source: .phrase, raw: "uh tell mom im on my way", cleaned: "Tell Mom I'm on my way.",
                     cleanupMs: cleanupMs, releaseToRawMs: nil, totalMs: nil, firstCall: firstCall, modelStatus: "Available")
    }

    // MARK: Request → screen → done

    func testTheRequestOpensTheScreenNotTheRemindersImport() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        let source = UnusedRemindersSource()
        let remindersImport = AppleRemindersImportCenter(store: store, source: source)
        var dispatch = ShellRequestDispatch(homeScreen: HomeScreenWidgetCenter(store: store), remindersImport: remindersImport)
        dispatch.dictationTest = center
        try store.set(sidekickId: "dictation", key: "request:d1", value: pendingRequest())

        dispatch.handleRequestWritten(sidekickId: "dictation", key: "request:d1", value: pendingRequest())

        XCTAssertEqual(center.shownSession, DictationTestSession(sidekickId: "dictation", requestKey: "request:d1"))
        XCTAssertNil(remindersImport.shownRequest)
        XCTAssertEqual(store.get(sidekickId: "dictation", key: "request:d1")?["status"]?.stringValue, "open")
    }

    func testWithoutTheCenterTheKindIsRefusedAsBefore() throws {
        let store = try gatedStore()
        let remindersImport = AppleRemindersImportCenter(store: store, source: UnusedRemindersSource())
        let dispatch = ShellRequestDispatch(homeScreen: HomeScreenWidgetCenter(store: store), remindersImport: remindersImport)
        try store.set(sidekickId: "dictation", key: "request:d1", value: pendingRequest())

        dispatch.handleRequestWritten(sidekickId: "dictation", key: "request:d1", value: pendingRequest())

        let request = store.get(sidekickId: "dictation", key: "request:d1")
        XCTAssertEqual(request?["status"]?.stringValue, "failed")
        XCTAssertEqual(request?["error"]?.stringValue, "unknown request")
    }

    func testClosingTheScreenMarksTheRequestDoneWithTheRunsSaved() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        try store.set(sidekickId: "dictation", key: "request:d1", value: pendingRequest())
        center.handleRequestWritten(sidekickId: "dictation", key: "request:d1", value: pendingRequest())

        center.save(phraseRun(cleanupMs: 400, secondsAfter: 1))
        center.save(phraseRun(cleanupMs: 500, secondsAfter: 2))
        center.dismiss()

        let request = try XCTUnwrap(store.get(sidekickId: "dictation", key: "request:d1"))
        XCTAssertEqual(request["status"]?.stringValue, "done")
        XCTAssertEqual(request["runs"]?.numberValue, 2)
        XCTAssertEqual(request["kind"]?.stringValue, "test.dictation", "what the page wrote stays")
        XCTAssertNil(center.shownSession)
    }

    func testASecondRequestWhileOpenIsCancelled() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        try store.set(sidekickId: "dictation", key: "request:d1", value: pendingRequest())
        try store.set(sidekickId: "dictation", key: "request:d2", value: pendingRequest())
        center.handleRequestWritten(sidekickId: "dictation", key: "request:d1", value: pendingRequest())

        center.handleRequestWritten(sidekickId: "dictation", key: "request:d2", value: pendingRequest())

        XCTAssertEqual(store.get(sidekickId: "dictation", key: "request:d2")?["status"]?.stringValue, "cancelled")
        XCTAssertEqual(center.shownSession?.requestKey, "request:d1")
    }

    func testTheShellTellsThePageItCanOpenTheScreen() {
        let capabilities = SidekickStoreChannel.shellCapabilities()
        let kinds = capabilities["requests"]?.arrayValue ?? []
        XCTAssertTrue(kinds.contains(.string("test.dictation")))
        XCTAssertTrue(kinds.contains(.string(ShellRequests.homeScreenWidgetKind)), "the other kinds stay")
    }

    // MARK: Runs as records

    func testASpokenRunIsSavedWithEveryTiming() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let releasedAt = fixedNow
        let timings = DictationTimings(releasedAt: releasedAt, rawFinalAt: releasedAt.addingTimeInterval(0.230),
                                       cleanupStartedAt: releasedAt.addingTimeInterval(0.250), cleanedAt: releasedAt.addingTimeInterval(0.900))
        let result = DictationCleanupResult(cleanedText: "Be there at 6.", durationMs: 640, isFirstCall: true)
        let run = DictationTestRuns.spoken(raw: "um so like be there at 5 no wait 6", result: result, timings: timings, status: .available,
                                           at: releasedAt.addingTimeInterval(0.900))

        center.save(run)

        XCTAssertNil(center.lastSaveError)
        let runs = store.query(sidekickId: "dictation", keyPrefix: "run:")
        XCTAssertEqual(runs.count, 1)
        let value = try XCTUnwrap(runs.first?.value)
        XCTAssertEqual(value["$type"]?.stringValue, "dictation.run", "stamped by the gate from the manifest")
        XCTAssertEqual(value["source"]?.stringValue, "spoken")
        XCTAssertEqual(value["raw"]?.stringValue, "um so like be there at 5 no wait 6")
        XCTAssertEqual(value["cleaned"]?.stringValue, "Be there at 6.")
        XCTAssertEqual(value["releaseToRawMs"]?.numberValue, 230)
        XCTAssertEqual(value["cleanupMs"]?.numberValue, 650, "the screen's cleanup timing")
        XCTAssertEqual(value["totalMs"]?.numberValue, 900)
        XCTAssertEqual(value["firstCall"]?.boolValue, true)
        XCTAssertEqual(value["modelStatus"]?.stringValue, "Available")
        XCTAssertEqual(value["device"]?.stringValue, "iPhone17,1")
        XCTAssertEqual(value["ios"]?.stringValue, "26.1")
        XCTAssertEqual(value["build"]?.stringValue, "25")
    }

    func testAPhraseRunHasCleanupOnly() throws {
        let result = DictationCleanupResult(cleanedText: "Tell Mom I'm on my way.", durationMs: 412, isFirstCall: false)
        let run = DictationTestRuns.phrase("uh tell mom im on my way", result: result, source: .runAll, status: .available, at: fixedNow)
        let value = DictationRunRecord.value(run, device: device)

        XCTAssertEqual(value["source"]?.stringValue, "run-all")
        XCTAssertEqual(value["cleanupMs"]?.numberValue, 412)
        XCTAssertNil(value["releaseToRawMs"])
        XCTAssertNil(value["totalMs"])
    }

    func testLongTextIsCutToTheManifestsLimitAndStillSaved() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let longText = String(repeating: "word ", count: 1_500)
        let run = DictationRun(at: fixedNow, source: .spoken, raw: longText, cleaned: longText, cleanupMs: 3_000, releaseToRawMs: 100, totalMs: 3_200,
                               firstCall: false, modelStatus: "Available")

        center.save(run)

        XCTAssertNil(center.lastSaveError)
        let value = try XCTUnwrap(store.query(sidekickId: "dictation", keyPrefix: "run:").first?.value)
        XCTAssertEqual(value["raw"]?.stringValue?.count, 4_000)
    }

    func testARunTheTypesRefuseIsReportedNotSaved() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let badRun = DictationRun(at: fixedNow, source: .phrase, raw: "x", cleaned: "x", cleanupMs: -5, releaseToRawMs: nil, totalMs: nil,
                                  firstCall: false, modelStatus: "Available")

        center.save(badRun)

        XCTAssertNotNil(center.lastSaveError)
        XCTAssertTrue(store.query(sidekickId: "dictation", keyPrefix: "run:").isEmpty)
    }

    func testKeysSortByTimeAndNeverCollide() {
        let first = DictationRunRecord.key(at: fixedNow, counter: 1)
        let sameMoment = DictationRunRecord.key(at: fixedNow, counter: 2)
        let later = DictationRunRecord.key(at: fixedNow.addingTimeInterval(0.001), counter: 1)

        XCTAssertTrue(first.hasPrefix("run:"))
        XCTAssertTrue(first.hasSuffix("Z-0001"))
        XCTAssertNotEqual(first, sameMoment)
        XCTAssertLessThan(first, later)
        XCTAssertLessThan(sameMoment, later)
    }

    // MARK: Summary

    func testTheSummaryMatchesThePage() throws {
        // The same five runs as backend/test/dictation-sidekick.test.ts: the newest (21:40) is 650 ms;
        // (1900 + 400 + 401 + 650 + 300) / 5 = 730.2
        let entries: [(String, Int)] = [("21:30", 1900), ("21:31", 400), ("21:32", 401), ("21:40", 650), ("21:35", 300)]
        var records: [LocalRecord] = []
        for (index, entry) in entries.enumerated() {
            let value = dictationJSON(#"{ "at": "2026-11-13T\#(entry.0):00.000Z", "cleanupMs": \#(entry.1) }"#)
            records.append(LocalRecord(sidekickId: "dictation", key: "run:\(index)", value: value))
        }
        records.append(LocalRecord(sidekickId: "dictation", key: "summary:main", value: dictationJSON(#"{ "runs": 9 }"#)))

        let summary = DictationRunRecord.summary(of: records, updatedAt: fixedNow)

        XCTAssertEqual(summary["runs"]?.numberValue, 5)
        XCTAssertEqual(summary["lastCleanupMs"]?.numberValue, 650)
        XCTAssertEqual(summary["averageCleanupMs"]?.numberValue, 730)
        XCTAssertEqual(summary["worstCleanupMs"]?.numberValue, 1900)
        XCTAssertEqual(summary["lastAt"]?.stringValue, "2026-11-13T21:40:00.000Z")
    }

    func testTheSummaryAverageRoundsHalfUpAndIsEmptyWithoutRuns() {
        let records = [
            LocalRecord(sidekickId: "dictation", key: "run:a", value: dictationJSON(#"{ "at": "2026-11-13T21:00:00Z", "cleanupMs": 1 }"#)),
            LocalRecord(sidekickId: "dictation", key: "run:b", value: dictationJSON(#"{ "at": "2026-11-13T21:01:00Z", "cleanupMs": 2 }"#)),
        ]
        XCTAssertEqual(DictationRunRecord.summary(of: records, updatedAt: fixedNow)["averageCleanupMs"]?.numberValue, 2)
        let empty = DictationRunRecord.summary(of: [], updatedAt: fixedNow)
        XCTAssertEqual(empty["runs"]?.numberValue, 0)
        XCTAssertNil(empty["averageCleanupMs"])
    }

    func testEverySaveRewritesTheSummary() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()

        center.save(phraseRun(cleanupMs: 1_000, secondsAfter: 1, firstCall: true))
        center.save(phraseRun(cleanupMs: 300, secondsAfter: 2))

        let summary = try XCTUnwrap(store.get(sidekickId: "dictation", key: "summary:main"))
        XCTAssertEqual(summary["$type"]?.stringValue, "dictation.summary")
        XCTAssertEqual(summary["runs"]?.numberValue, 2)
        XCTAssertEqual(summary["lastCleanupMs"]?.numberValue, 300)
        XCTAssertEqual(summary["averageCleanupMs"]?.numberValue, 650)
        XCTAssertEqual(summary["worstCleanupMs"]?.numberValue, 1_000)
    }

    // MARK: Widget

    private func widgetFromThePage() throws -> JSONValue {
        let toolsSource = try String(contentsOf: dictationRepoRoot.appending(path: "sidekicks/dictation/tools.js"), encoding: .utf8)
        let beginRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: begin */"))
        let endRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: end */", range: beginRange.upperBound..<toolsSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(toolsSource[beginRange.upperBound..<endRange.lowerBound]))
        XCTAssertNil(context.exception)
        let widgetText = try XCTUnwrap(context.evaluateScript("JSON.stringify(DictationLogic.widgetRecords()[0].value)")?.toString())
        return dictationJSON(widgetText)
    }

    private func texts(in piece: WidgetPiece) -> [String] {
        switch piece {
        case .vstack(let stack), .hstack(let stack):
            var found: [String] = []
            for child in stack.children {
                found.append(contentsOf: texts(in: child))
            }
            return found
        case .text(let text):
            return [text.text]
        default:
            return []
        }
    }

    private func screen(widget: JSONValue, summary: JSONValue?, size: SidekickWidgetSize) -> SidekickWidgetScreen {
        var records = [LocalRecord(sidekickId: "dictation", key: "widget:summary", value: widget)]
        if let summary {
            records.append(LocalRecord(sidekickId: "dictation", key: "summary:main", value: summary))
        }
        let filler = SidekickWidgetFiller(calendar: Calendar(identifier: .gregorian))
        let filledWidget = filler.fill(sidekickId: "dictation", sidekickName: "Dictation", record: records[0], sidekickRecords: records, now: fixedNow)
        let file = SharedSidekickWidgets(widgets: [filledWidget], savedAt: fixedNow)
        return SidekickWidgetLayout.screen(file: file, sidekickId: "dictation", widgetChoiceId: "dictation/summary", size: size, at: fixedNow)
    }

    private let typicalSummary = dictationJSON(#"{ "runs": 5, "lastCleanupMs": 650, "averageCleanupMs": 730, "worstCleanupMs": 1900 }"#)

    func testTheWidgetPassesTheCheckerAndShowsLastAndAverage() throws {
        let widget = try widgetFromThePage()
        XCTAssertNil(SidekickWidgetDescription.validationError(widget))

        guard case .piece(let typical, _, _) = screen(widget: widget, summary: typicalSummary, size: .small) else {
            return XCTFail("no small widget")
        }
        let typicalTexts = texts(in: typical)
        XCTAssertTrue(typicalTexts.contains("650 ms"), "\(typicalTexts)")
        XCTAssertTrue(typicalTexts.contains("Avg 730 ms"), "\(typicalTexts)")
        XCTAssertFalse(typicalTexts.contains("No Runs"))

        guard case .piece(let empty, _, _) = screen(widget: widget, summary: nil, size: .small) else {
            return XCTFail("no empty widget")
        }
        let emptyTexts = texts(in: empty)
        XCTAssertTrue(emptyTexts.contains("No Runs"), "\(emptyTexts)")
        XCTAssertFalse(emptyTexts.contains("Avg  ms"))
    }

    /// Saves light and dark PNGs of the small and medium widget when MIDAS_WIDGET_RENDER_DIR is set.
    func testRendersInLightAndDark() throws {
        let widget = try widgetFromThePage()
        let directory = ProcessInfo.processInfo.environment["MIDAS_WIDGET_RENDER_DIR"]
        for size in [SidekickWidgetSize.small, .medium] {
            let filledScreen = screen(widget: widget, summary: typicalSummary, size: size)
            for (scheme, name) in [(ColorScheme.light, "light"), (ColorScheme.dark, "dark")] {
                let view = SidekickWidgetSnapshot(screen: filledScreen, size: size).environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                renderer.scale = 3
                _ = renderer.uiImage
                let image = try XCTUnwrap(renderer.uiImage)
                XCTAssertGreaterThan(image.size.width, 0)
                if let directory {
                    let fileURL = URL(fileURLWithPath: directory).appending(path: "dictation-widget-2026-11-13-\(size.rawValue)-\(name).png")
                    try XCTUnwrap(image.pngData()).write(to: fileURL)
                }
            }
        }
    }
}
#endif
