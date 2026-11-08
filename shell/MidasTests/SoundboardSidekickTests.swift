import CryptoKit
import JavaScriptCore
import SwiftUI
import UIKit
import WebKit
import XCTest
@testable import Midas

// The Sounds Sidekick (`sidekicks/soundboard/`, docs/briefs/soundboard-sidekick.md, founder
// 2026-11-07) on the phone: the real page in a real WKWebView under the real CSP, writing through
// the scheme handler into a store whose write gate checks every record against the manifest and
// whose channel keeps files (store.putFile) and runs the shell's widget check. On first open the
// page copies its five starter sounds (clip and GIF) into the store; a starter deleted stays
// deleted; a clip decodes through the files endpoint (Web Audio: the CSP has no media-src). Its
// tools.js runs in JavaScriptCore with every op going through RecordWriter, and its widget goes
// through the shell's checker and filler, drawn in light and dark (saved when
// MIDAS_WIDGET_RENDER_DIR is set: docs/mockups/soundboard-widget-{light,dark}-2026-11-07.png).

private let soundboardRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let soundboardNowText = "2026-11-07T20:00:00.000Z"
private let soundboardCalendar = ReminderSchedule.phoneCalendar(timeZone: TimeZone(identifier: "America/Los_Angeles")!)

private struct SoundboardBundleLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class SoundboardPageWaiter: NSObject, WKNavigationDelegate {
    var finished: XCTestExpectation?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished?.fulfill()
        finished = nil
    }
}

/// Every text inside a filled piece, depth first.
private func soundboardTexts(in piece: WidgetPiece?) -> [String] {
    guard let piece else {
        return []
    }
    switch piece {
    case .text(let textPiece):
        return [textPiece.text]
    case .vstack(let stack), .hstack(let stack):
        var found: [String] = []
        for child in stack.children {
            found.append(contentsOf: soundboardTexts(in: child))
        }
        return found
    case .background(let backgroundPiece):
        return soundboardTexts(in: backgroundPiece.content)
    default:
        return []
    }
}

@MainActor
final class SoundboardSidekickTests: XCTestCase {
    private static let sidekickId = "soundboard"
    private static let starterKeys = ["sound:fahh", "sound:bruh", "sound:boom", "sound:khatam", "sound:gay"]
    private var folder: URL!
    private var files: FileStore!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "soundboard-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        files = FileStore(directoryURL: folder.appending(path: "files"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    // MARK: Files and the store

    private func sidekickFile(_ fileName: String) throws -> String {
        try String(contentsOf: soundboardRepoRoot.appending(path: "sidekicks/soundboard/\(fileName)"), encoding: .utf8)
    }

    private func manifest() throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(try sidekickFile("manifest.json").utf8))
    }

    private func json(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    /// A store whose write gate checks every record against the real manifest types (and the
    /// shell's own types for `widget:`).
    private func makeGatedStore() throws -> LocalRecordStore {
        let engine = try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
        let types = try manifest()["types"]
        let store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        func typesFor(requestedSidekickId: String) -> JSONValue? {
            requestedSidekickId == Self.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: typesFor)
        return store
    }

    private func soundKeys(_ store: LocalRecordStore) -> [String] {
        var keys: [String] = []
        for record in store.query(sidekickId: Self.sidekickId, keyPrefix: "sound:") {
            keys.append(record.key)
        }
        return keys
    }

    // MARK: Loading the page

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

    private func loadPage(store: LocalRecordStore) async throws -> (WKWebView, SoundboardPageWaiter) {
        let html = try sidekickFile("index.html")
        let channel = SidekickStoreChannel(store: store, reservedValidators: ShellServices.reservedRecordValidators)
        channel.fileStore = files
        let loader = SoundboardBundleLoader(html: html, scriptHashes: inlineScriptHashes(in: html))
        XCTAssertEqual(loader.scriptHashes.count, 1, "the starter block must not be a script")
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let waiter = SoundboardPageWaiter()
        let finished = expectation(description: "sounds page loaded")
        waiter.finished = finished
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: Self.sidekickId)))
        // The first page of a run starts the web content process, which can take over ten seconds
        await fulfillment(of: [finished], timeout: 30)
        let probe = """
        if (typeof SoundsApp !== 'object' || typeof SoundsLogic !== 'object' || typeof store !== 'object') { return 'script did not run'; }
        await SoundsApp.whenReady();
        return 'ready';
        """
        let outcome = try await webView.callAsyncJavaScript(probe, contentWorld: .page) as? String
        XCTAssertEqual(outcome, "ready", "the page's script did not run under the CSP")
        return (webView, waiter)
    }

    private func runScript(_ webView: WKWebView, _ script: String) async throws -> String {
        let result = try await webView.callAsyncJavaScript(script, contentWorld: .page)
        return try XCTUnwrap(result as? String, "the script returned no text")
    }

    // MARK: The page

    func testFirstOpenCopiesInTheFiveStartersWithTheirClipsAndGIFs() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)

        XCTAssertEqual(Set(soundKeys(store)), Set(Self.starterKeys))
        let expectedNames = ["sound:fahh": "Fahh", "sound:bruh": "Bruh", "sound:boom": "Vine Boom", "sound:khatam": "Khatam Tata Bye Bye", "sound:gay": "Why Are You Gay"]
        for key in Self.starterKeys {
            let sound = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: key), key)
            XCTAssertEqual(sound["$type"], .string("soundboard.sound"), key)
            XCTAssertEqual(sound["name"], .string(expectedNames[key]!), key)
            let audioId = try XCTUnwrap(FileStore.fileId(fromReference: sound["audio"]?.stringValue ?? ""), "\(key) has no clip")
            let audio = try XCTUnwrap(files.data(for: audioId), "\(key)'s clip is not stored")
            XCTAssertEqual(audio.contentType, "audio/mpeg", key)
            XCTAssertGreaterThan(audio.data.count, 2000, key)
            let imageId = try XCTUnwrap(FileStore.fileId(fromReference: sound["image"]?.stringValue ?? ""), "\(key) has no GIF")
            let image = try XCTUnwrap(files.data(for: imageId), "\(key)'s GIF is not stored")
            XCTAssertEqual(image.contentType, "image/gif", key)
            XCTAssertEqual(String(decoding: image.data.prefix(3), as: UTF8.self), "GIF", key)
        }
        let settings = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "settings:self"))
        XCTAssertEqual(settings["$type"], .string("soundboard.settings"))
        XCTAssertEqual(settings["seeded"], .array([.string("fahh"), .string("bruh"), .string("boom"), .string("khatam"), .string("gay")]))

        let widget = try XCTUnwrap(store.get(sidekickId: Self.sidekickId, key: "widget:sounds"), "widget:sounds was not written")
        XCTAssertEqual(widget["$type"], .string("midas.widget"))
        XCTAssertNil(SidekickWidgetDescription.validationError(widget))
        XCTAssertEqual(widget["background"], .object(["light": .string("#FFE600"), "dark": .string("#1A1A1A")]), "not the light-and-dark widget")

        // The tiles, in order, each with its GIF loaded from a blob: URL (img-src allows blob:)
        let tiles = try await runScript(webView, """
        for (let attempt = 0; attempt < 100; attempt += 1) {
          const images = Array.from(document.querySelectorAll('.tile img'));
          const loaded = images.filter(function isLoaded(image) { return image.complete && image.naturalWidth > 0 && image.src.indexOf('blob:') === 0; });
          if (images.length === 5 && loaded.length === 5) { break; }
          await new Promise(function wait(resolve) { setTimeout(resolve, 50); });
        }
        const names = Array.from(document.querySelectorAll('.tile .name'), function nameOf(node) { return node.textContent; });
        const loadedCount = Array.from(document.querySelectorAll('.tile img')).filter(function isLoaded(image) { return image.naturalWidth > 0; }).length;
        return names.join('|') + ' ' + loadedCount;
        """)
        XCTAssertEqual(tiles, "Fahh|Bruh|Vine Boom|Khatam Tata Bye Bye|Why Are You Gay 5")
        _ = waiter
    }

    func testOpeningAgainCopiesNothingAndADeletedStarterStaysDeleted() async throws {
        let store = try makeGatedStore()
        let (firstView, firstWaiter) = try await loadPage(store: store)
        _ = try await runScript(firstView, "await SoundsApp.deleteSound('sound:bruh'); return 'deleted';")
        XCTAssertNil(store.get(sidekickId: Self.sidekickId, key: "sound:bruh"))
        let filesBefore = files.pendingUploads().count

        let (secondView, secondWaiter) = try await loadPage(store: store)
        XCTAssertEqual(Set(soundKeys(store)), Set(["sound:fahh", "sound:boom", "sound:khatam", "sound:gay"]), "a deleted starter came back")
        XCTAssertEqual(files.pendingUploads().count, filesBefore, "a second open copied files in again")
        let names = try await runScript(secondView, "return SoundsApp.state().entries.map(function nameOf(entry) { return entry.sound.name; }).join('|');")
        XCTAssertEqual(names, "Fahh|Vine Boom|Khatam Tata Bye Bye|Why Are You Gay")
        _ = (firstWaiter, secondWaiter)
    }

    func testAStarterClipDecodesFromTheFilesEndpointUnderTheContentSecurityPolicy() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)
        let seconds = try await runScript(webView, "return String(await SoundsApp.prepare('sound:khatam'));")
        let duration = try XCTUnwrap(Double(seconds), "not a duration: \(seconds)")
        XCTAssertGreaterThan(duration, 1, "the Khatam clip is several seconds long")
        _ = waiter
    }

    func testSearchFiltersByNameAndTagAnyCase() async throws {
        let store = try makeGatedStore()
        let (webView, waiter) = try await loadPage(store: store)
        let byTag = try await runScript(webView, "SoundsApp.search('RAHUL'); return Array.from(document.querySelectorAll('.tile .name'), function nameOf(node) { return node.textContent; }).join('|');")
        XCTAssertEqual(byTag, "Khatam Tata Bye Bye")
        let none = try await runScript(webView, "SoundsApp.search('airhorn'); return document.getElementById('board').textContent;")
        XCTAssertEqual(none, "No Sounds")
        let all = try await runScript(webView, "SoundsApp.search(''); return String(document.querySelectorAll('.tile').length);")
        XCTAssertEqual(all, "5")
        _ = waiter
    }

    // MARK: The tools in JavaScriptCore

    private func toolsEngine() throws -> SidekickToolsEngine {
        try SidekickToolsEngine(source: try sidekickFile("tools.js"))
    }

    private func seededToolsStore() throws -> LocalRecordStore {
        let store = try makeGatedStore()
        try store.set(sidekickId: Self.sidekickId, key: "settings:self", value: try json(#"{"seeded":["fahh","boom"],"overlap":true}"#))
        try store.set(sidekickId: Self.sidekickId, key: "sound:fahh", value: try json(#"{"name":"Fahh","tags":["fah","fail"],"audio":"file:fahhaudio0001","image":"file:fahhimage0001","order":1,"starter":"fahh","createdAt":"2026-11-07T18:00:00.000Z"}"#))
        try store.set(sidekickId: Self.sidekickId, key: "sound:boom", value: try json(#"{"name":"Vine Boom","tags":["boom","rock"],"audio":"file:boomaudio0001","order":2,"starter":"boom","createdAt":"2026-11-07T18:00:01.000Z"}"#))
        return store
    }

    func testToolsLoadInJavaScriptCoreWithAHandlerForEveryTool() throws {
        guard case .array(let tools)? = try manifest()["agent"]?["tools"] else {
            return XCTFail("no agent tools in manifest.json")
        }
        var verbs: [String] = []
        for tool in tools {
            if case .string(let name)? = tool["name"] {
                verbs.append(String(name.dropFirst("soundboard.".count)))
            }
        }
        XCTAssertEqual(try toolsEngine().handlerNames(), verbs.sorted())
        XCTAssertEqual(verbs.sorted(), ["delete", "list", "rename", "search", "set_overlap", "tag"])
    }

    func testRenameTagAndDeleteRunInJavaScriptCoreAndPassTheWriteGate() throws {
        let store = try seededToolsStore()
        let engine = try toolsEngine()
        let now = ReminderRecord.parseDate(.string(soundboardNowText))!
        let writer = RecordWriter(store: store)

        let rename = try engine.run(verb: "rename", input: try json(#"{"name":"fahh","newName":"Faaah"}"#), records: store.query(sidekickId: Self.sidekickId, keyPrefix: ""), now: now)
        XCTAssertEqual(rename.text, "Renamed to Faaah")
        guard case .changes(let renameOps) = rename.outcome else {
            return XCTFail("expected changes, got \(rename.outcome)")
        }
        try writer.apply(sidekickId: Self.sidekickId, ops: renameOps)
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "sound:fahh")?["name"], .string("Faaah"))
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "sound:fahh")?["image"], .string("file:fahhimage0001"), "the GIF was lost")

        let tag = try engine.run(verb: "tag", input: try json(#"{"name":"Vine Boom","add":["Bass"],"remove":["rock"]}"#), records: store.query(sidekickId: Self.sidekickId, keyPrefix: ""), now: now)
        guard case .changes(let tagOps) = tag.outcome else {
            return XCTFail("expected changes, got \(tag.outcome)")
        }
        try writer.apply(sidekickId: Self.sidekickId, ops: tagOps)
        XCTAssertEqual(store.get(sidekickId: Self.sidekickId, key: "sound:boom")?["tags"], .array([.string("boom"), .string("bass")]))

        let delete = try engine.run(verb: "delete", input: try json(#"{"name":"Vine Boom"}"#), records: store.query(sidekickId: Self.sidekickId, keyPrefix: ""), now: now)
        XCTAssertEqual(delete.text, "Deleted Vine Boom")
        guard case .changes(let deleteOps) = delete.outcome else {
            return XCTFail("expected changes, got \(delete.outcome)")
        }
        try writer.apply(sidekickId: Self.sidekickId, ops: deleteOps)
        XCTAssertNil(store.get(sidekickId: Self.sidekickId, key: "sound:boom"))
    }

    func testARefusalChangesNothingAndContextGivesTheNames() throws {
        let store = try seededToolsStore()
        let before = store.query(sidekickId: Self.sidekickId, keyPrefix: "")
        let engine = try toolsEngine()
        let now = ReminderRecord.parseDate(.string(soundboardNowText))!
        let missing = try engine.run(verb: "delete", input: try json(#"{"name":"airhorn"}"#), records: before, now: now)
        XCTAssertEqual(missing.outcome, .refused(reason: "no-such-sound"))
        XCTAssertEqual(store.query(sidekickId: Self.sidekickId, keyPrefix: ""), before)
        let context = try engine.context(records: before, now: now)
        XCTAssertEqual(context["sounds"], .array([.string("Fahh"), .string("Vine Boom")]))
        XCTAssertEqual(context["count"], .number(2))
    }

    // MARK: The widget

    private func pageWidget() throws -> JSONValue {
        let toolsSource = try sidekickFile("tools.js")
        let beginRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: begin */"))
        let endRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: end */", range: beginRange.upperBound..<toolsSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(toolsSource[beginRange.upperBound..<endRange.lowerBound]))
        XCTAssertNil(context.exception)
        let widgetText = try XCTUnwrap(context.evaluateScript("JSON.stringify(SoundsLogic.widgetRecords()[0].value)")?.toString())
        return try json(widgetText)
    }

    private func soundRecords(_ names: [String]) -> [LocalRecord] {
        var records: [LocalRecord] = []
        for (index, name) in names.enumerated() {
            let value = JSONValue.object(["name": .string(name), "audio": .string("file:aaaaaaaa\(index)"), "order": .number(Double(index + 1))])
            records.append(LocalRecord(sidekickId: Self.sidekickId, key: String(format: "sound:%02d", index), value: value))
        }
        return records
    }

    private func filled(_ widget: JSONValue, sounds: [String]) -> FilledSidekickWidget {
        let widgetRecord = LocalRecord(sidekickId: Self.sidekickId, key: "widget:sounds", value: widget)
        let filler = SidekickWidgetFiller(calendar: soundboardCalendar)
        let now = ReminderRecord.parseDate(.string(soundboardNowText))!
        return filler.fill(sidekickId: Self.sidekickId, sidekickName: "Sounds", record: widgetRecord, sidekickRecords: soundRecords(sounds) + [widgetRecord], now: now)
    }

    func testTheWidgetPassesTheCheckerAndShowsTheCountAndTheFirstNames() throws {
        let widget = try pageWidget()
        XCTAssertNil(SidekickWidgetDescription.validationError(widget))

        let empty = filled(widget, sounds: []).looks.first?.small
        XCTAssertEqual(soundboardTexts(in: empty), ["Sounds", "0", "No Sounds"])

        let four = filled(widget, sounds: ["Fahh", "Bruh", "Vine Boom", "Khatam Tata Bye Bye"]).looks.first
        XCTAssertEqual(soundboardTexts(in: four?.small), ["Sounds", "4", "Fahh", "Bruh", "Vine Boom", "+1 more"])
        XCTAssertEqual(soundboardTexts(in: four?.medium), ["Sounds", "4", "Fahh", "Bruh", "Vine Boom", "Khatam Tata Bye Bye"])

        var many: [String] = []
        for index in 0..<12 {
            many.append("Sound \(index)")
        }
        let twelve = filled(widget, sounds: many).looks.first?.small
        XCTAssertEqual(soundboardTexts(in: twelve), ["Sounds", "12", "Sound 0", "Sound 1", "Sound 2", "+9 more"])
    }

    /// Small and medium side by side on a plain wallpaper, light and dark; saved only when asked for.
    func testRenderTheWidgetLightAndDark() throws {
        let widget = try pageWidget()
        let filledWidget = filled(widget, sounds: ["Fahh", "Bruh", "Vine Boom", "Khatam Tata Bye Bye"])
        let now = ReminderRecord.parseDate(.string(soundboardNowText))!
        let file = SharedSidekickWidgets(widgets: [filledWidget], savedAt: now)
        for (colorScheme, modeName) in [(ColorScheme.light, "light"), (ColorScheme.dark, "dark")] {
            let wallpaper = colorScheme == .dark ? Color(red: 0.1, green: 0.1, blue: 0.11) : Color(red: 0.86, green: 0.87, blue: 0.9)
            let smallScreen = SidekickWidgetLayout.screen(file: file, sidekickId: Self.sidekickId, widgetChoiceId: "soundboard/sounds", size: .small, at: now)
            let mediumScreen = SidekickWidgetLayout.screen(file: file, sidekickId: Self.sidekickId, widgetChoiceId: "soundboard/sounds", size: .medium, at: now)
            let board = HStack(alignment: .top, spacing: 22) {
                SidekickWidgetSnapshot(screen: smallScreen, size: .small)
                SidekickWidgetSnapshot(screen: mediumScreen, size: .medium)
            }
            .padding(24)
            .background(wallpaper)
            let renderer = ImageRenderer(content: board.environment(\.colorScheme, colorScheme))
            renderer.scale = 3
            // Drawn twice, the first one thrown away (a first drawing once came back blank)
            _ = renderer.uiImage
            let image = try XCTUnwrap(renderer.uiImage, "\(modeName) did not draw")
            XCTAssertGreaterThan(image.size.width, 300)
            guard let renderDirectory = ProcessInfo.processInfo.environment["MIDAS_WIDGET_RENDER_DIR"] else {
                continue
            }
            let pngData = try XCTUnwrap(image.pngData())
            try pngData.write(to: URL(filePath: renderDirectory).appending(path: "soundboard-widget-\(modeName)-2026-11-07.png"))
        }
    }
}
