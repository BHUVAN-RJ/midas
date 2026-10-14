import CryptoKit
import WebKit
import XCTest
@testable import Midas

// The Sidekick widget, step 7 (founder, 2026-10-13; plan
// docs/mockups/sidekick-widget-plan-2026-10-13.html): its first user. The real care-reminders
// page in a real WKWebView writes "Meds today" and "Next up" through the shell's checker; the
// shell fills them from the page's reminders; Taken on the widget ticks the reminder.

private struct CareWidgetBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class CareWidgetPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

@MainActor
final class CareRemindersWidgetTests: XCTestCase {
    private static let sidekickId = "care-reminders"
    private static let zoneName = "America/Los_Angeles"
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appending(path: "care-widget-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var zoneCalendar: Calendar {
        return ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: Self.zoneName)!)
    }

    private func bundleHTML() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let repositoryRoot = testsDirectory.deletingLastPathComponent().deletingLastPathComponent()
        let bundleURL = repositoryRoot.appending(path: "sidekicks/care-reminders/index.html")
        return try String(contentsOf: bundleURL, encoding: .utf8)
    }

    /// The CSP hash of each inline script, computed the way the deploy script does.
    private func inlineScriptHashes(in html: String) -> [String] {
        var hashes: [String] = []
        var searchStart = html.startIndex
        while let openRange = html.range(of: "<script>", range: searchStart..<html.endIndex),
              let closeRange = html.range(of: "</script>", range: openRange.upperBound..<html.endIndex) {
            let scriptText = String(html[openRange.upperBound..<closeRange.lowerBound])
            let digest = SHA256.hash(data: Data(scriptText.utf8))
            hashes.append("'sha256-\(Data(digest).base64EncodedString())'")
            searchStart = closeRange.upperBound
        }
        return hashes
    }

    /// The page with the shell's own record checks, the widget checker included.
    private func loadPage(store: LocalRecordStore) async throws -> (WKWebView, CareWidgetPageWaiter) {
        let html = try bundleHTML()
        let channel = SidekickStoreChannel(store: store, reservedValidators: ShellServices.reservedRecordValidators)
        let loader = CareWidgetBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = CareWidgetPageWaiter()
        let finished = expectation(description: "care reminders page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: Self.sidekickId)))
        await fulfillment(of: [finished], timeout: 10)
        try await waitUntilReady(webView)
        return (webView, waiter)
    }

    private func reload(_ webView: WKWebView, waiter: CareWidgetPageWaiter) async throws {
        let finished = expectation(description: "care reminders page reloaded")
        waiter.finished = finished
        webView.reload()
        await fulfillment(of: [finished], timeout: 10)
        try await waitUntilReady(webView)
    }

    private func waitUntilReady(_ webView: WKWebView) async throws {
        let probe = """
        if (typeof CareApp !== 'object' || typeof store !== 'object') { return 'script did not run'; }
        await CareApp.whenReady();
        return 'ready';
        """
        let outcome = try await webView.callAsyncJavaScript(probe, contentWorld: .page) as? String
        XCTAssertEqual(outcome, "ready")
    }

    private func widgetOps(_ store: LocalRecordStore) -> Int {
        var count = 0
        for pendingOp in store.pendingOps() where pendingOp.key.hasPrefix("widget:") {
            count += 1
        }
        return count
    }

    private func makePublisher(store: LocalRecordStore) -> SidekickWidgetPublisher {
        let calendar = zoneCalendar
        let listSidekicks: @MainActor () -> [(id: String, name: String)] = { [(id: CareRemindersWidgetTests.sidekickId, name: "Reminders")] }
        return SidekickWidgetPublisher(fileURL: directory.appending(path: "widgets.json"), store: store, sidekicks: listSidekicks,
                                       now: Date.init, calendar: { calendar }, reloadWidget: {},
                                       pendingActionsFileURL: directory.appending(path: "actions.json"))
    }

    private func texts(in piece: WidgetPiece?) -> [String] {
        guard let piece else {
            return []
        }
        switch piece {
        case .vstack(let stack), .hstack(let stack):
            var found: [String] = []
            for child in stack.children {
                found.append(contentsOf: texts(in: child))
            }
            return found
        case .text(let textPiece):
            return [textPiece.text]
        default:
            return []
        }
    }

    private func firstButton(in piece: WidgetPiece?) -> WidgetButtonPiece? {
        guard let piece else {
            return nil
        }
        switch piece {
        case .vstack(let stack), .hstack(let stack):
            for child in stack.children {
                if let button = firstButton(in: child) {
                    return button
                }
            }
            return nil
        case .button(let button):
            return button
        default:
            return nil
        }
    }

    func testThePageDescribesTwoWidgetsTheShellAccepts() async throws {
        let store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        let (webView, waiter) = try await loadPage(store: store)
        let meds = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "widget:meds"))
        let next = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "widget:next"))
        XCTAssertEqual(meds["name"], .string("Meds today"))
        XCTAssertEqual(next["name"], .string("Next up"))
        XCTAssertNil(SidekickWidgetDescription.validationError(meds))
        XCTAssertNil(SidekickWidgetDescription.validationError(next))

        // Opening the page again does not write the same descriptions again.
        let opsBefore = widgetOps(store)
        try await reload(webView, waiter: waiter)
        XCTAssertEqual(widgetOps(store), opsBefore)
    }

    func testMedsTodayShowsTheNextMedicineAndTakenTicksIt() async throws {
        let store = LocalRecordStore(fileURL: directory.appending(path: "records.json"))
        let (webView, _) = try await loadPage(store: store)
        let today = zoneCalendar.dateComponents([.year, .month, .day], from: Date())
        let todayText = String(format: "%04d-%02d-%02d", today.year!, today.month!, today.day!)
        let script = """
        var itemId = await CareApp.saveReminder({ title: 'Vitamin D', list: 'medicine', date: '\(todayText)', time: '23:30',
                                                  repeatKey: 'never', timeZone: '\(Self.zoneName)' });
        return itemId;
        """
        let scriptResult = try await webView.callAsyncJavaScript(script, contentWorld: .page)
        let itemId = try XCTUnwrap(scriptResult as? String)

        let publisher = makePublisher(store: store)
        let widgets = publisher.filledWidgets()
        XCTAssertEqual(widgets.map(\.choiceId), ["care-reminders/meds", "care-reminders/next"])
        let meds = try XCTUnwrap(widgets.first)
        XCTAssertTrue(meds.isUsable)
        let small = meds.looks.first?.small
        XCTAssertTrue(texts(in: small).contains("Vitamin D"))
        XCTAssertTrue(texts(in: small).contains("0/1"))
        let taken = try XCTUnwrap(firstButton(in: small))
        XCTAssertEqual(taken.title, "Taken")
        XCTAssertEqual(taken.action.key, "reminder:\(itemId)")

        publisher.perform(taken.action)
        let ticked = store.get(sidekickId: Self.sidekickId, key: "reminder:\(itemId)")
        XCTAssertEqual(ticked?["done"], .bool(true))
        let afterTick = publisher.filledWidgets().first?.looks.first?.small
        XCTAssertTrue(texts(in: afterTick).contains("All done"))
        XCTAssertTrue(texts(in: afterTick).contains("1/1"))
        XCTAssertNil(firstButton(in: afterTick))
    }
}
