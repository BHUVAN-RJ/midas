import CryptoKit
import WebKit
import XCTest
@testable import Midas

// Files from a Sidekick page (unified data plan, section 7): `store.putFile` posts the bytes to
// the page's own origin and gets "file:<id>"; `store.fileUrl` gets the bytes back as a blob: URL
// (the page's content policy keeps `img-src data: blob:`). A record over 64 KB because of a
// `data:` URL is fixed by the shell: the data becomes a file, the field its reference.

private struct FilesPageLoader: SidekickBundleLoading {
    let html: String
    let scriptHashes: [String]

    func loadBundle(sidekickId: String) async throws -> SidekickBundle {
        SidekickBundle(html: Data(html.utf8), scriptHashes: scriptHashes, version: "test")
    }
}

private final class FilesPageWaiter: NSObject, WKNavigationDelegate {
    let finished: XCTestExpectation

    init(finished: XCTestExpectation) {
        self.finished = finished
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished.fulfill()
    }
}

private final class StubFileTransfer: FileTransfer, @unchecked Sendable {
    var downloads: [String: (data: Data, contentType: String)] = [:]
    var downloadCount = 0

    func upload(fileId: String, data: Data, contentType: String) async throws {}

    func download(fileId: String) async throws -> (data: Data, contentType: String)? {
        downloadCount += 1
        return downloads[fileId]
    }
}

@MainActor
final class SidekickFilesChannelTests: XCTestCase {
    private var folder: URL!
    private var store: LocalRecordStore!
    private var files: FileStore!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "files-channel-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        files = FileStore(directoryURL: folder.appending(path: "files"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func makeChannel(transfer: FileTransfer? = nil) -> SidekickStoreChannel {
        let channel = SidekickStoreChannel(store: store)
        channel.fileStore = files
        channel.fileTransfer = transfer
        return channel
    }

    func testAFileFromThePageIsSavedQueuedAndAnsweredWithItsReference() throws {
        let channel = makeChannel()
        let reply = channel.handleFilePut(sidekickId: "reminders", body: Data("shot".utf8), contentType: "image/jpeg")
        XCTAssertEqual(reply.statusCode, 200)
        let reference = try XCTUnwrap(reply.body["ref"]?.stringValue)
        let fileId = try XCTUnwrap(FileStore.fileId(fromReference: reference))
        XCTAssertEqual(files.data(for: fileId)?.data, Data("shot".utf8))
        XCTAssertEqual(files.data(for: fileId)?.contentType, "image/jpeg")
        XCTAssertEqual(files.pendingUploads(), [fileId])

        XCTAssertEqual(channel.handleFilePut(sidekickId: "reminders", body: Data(), contentType: "image/jpeg").statusCode, 400)
        let tooBig = Data(count: FileStore.maxFileBytes + 1)
        let refused = channel.handleFilePut(sidekickId: "reminders", body: tooBig, contentType: "image/jpeg")
        XCTAssertEqual(refused.statusCode, 400)
        XCTAssertEqual(refused.body["error"], .string("file is over \(FileStore.maxFileBytes) bytes"))
        XCTAssertEqual(files.pendingUploads(), [fileId], "a refused file is not kept")
        XCTAssertEqual(channel.handleFilePut(sidekickId: "reminders", body: Data("x".utf8), contentType: nil).body["ok"], .bool(true))

        let withoutFiles = SidekickStoreChannel(store: store)
        XCTAssertEqual(withoutFiles.handleFilePut(sidekickId: "reminders", body: Data("x".utf8), contentType: nil).statusCode, 400)
    }

    func testAFileIsReadFromThePhoneOrFetchedOnceAndKept() async throws {
        let transfer = StubFileTransfer()
        transfer.downloads["abcdefabcdef0001"] = (Data("from the server".utf8), "text/plain")
        let channel = makeChannel(transfer: transfer)
        let localId = try files.save(Data("local".utf8), contentType: "text/plain")

        let local = await channel.fileData(fileId: localId)
        XCTAssertEqual(local?.data, Data("local".utf8))
        XCTAssertEqual(transfer.downloadCount, 0)

        let fetched = await channel.fileData(fileId: "abcdefabcdef0001")
        XCTAssertEqual(fetched?.data, Data("from the server".utf8))
        XCTAssertEqual(fetched?.contentType, "text/plain")
        let again = await channel.fileData(fileId: "abcdefabcdef0001")
        XCTAssertEqual(again?.data, Data("from the server".utf8))
        XCTAssertEqual(transfer.downloadCount, 1, "the second read is local")
        XCTAssertEqual(files.pendingUploads(), [localId], "a fetched file is not queued for upload")

        let missing = await channel.fileData(fileId: "neverstored00001")
        XCTAssertNil(missing)
        let bad = await channel.fileData(fileId: "../escape")
        XCTAssertNil(bad)
    }

    func testARecordOverTheLimitBecauseOfADataURLKeepsAFileReferenceInstead() throws {
        let channel = makeChannel()
        let bigImage = "data:image/png;base64," + Data(count: 70 * 1024).base64EncodedString()
        let request = try JSONEncoder().encode(JSONValue.object(["op": .string("set"), "key": .string("note:shot"), "value": .object(["title": .string("Fix this"), "image": .string(bigImage)])]))
        let reply = channel.handle(sidekickId: "notes", requestBody: request)
        XCTAssertEqual(reply.statusCode, 200, "\(reply.body)")
        let stored = try XCTUnwrap(store.get(sidekickId: "notes", key: "note:shot"))
        XCTAssertEqual(stored["title"], .string("Fix this"))
        let fileId = try XCTUnwrap(FileStore.fileId(fromReference: stored["image"]?.stringValue ?? ""), "the image is not a file reference: \(String(describing: stored["image"]))")
        XCTAssertEqual(files.data(for: fileId)?.data, Data(count: 70 * 1024))
        XCTAssertEqual(files.data(for: fileId)?.contentType, "image/png")
        XCTAssertLessThan(RecordSync.valueByteCount(stored), SidekickStoreChannel.maxValueBytes)

        // Under the limit a data: URL is left alone, and without a file store the old refusal stands.
        let smallImage = "data:image/png;base64,iVBORw0KGgo="
        let smallRequest = try JSONEncoder().encode(JSONValue.object(["op": .string("set"), "key": .string("note:small"), "value": .object(["image": .string(smallImage)])]))
        XCTAssertEqual(channel.handle(sidekickId: "notes", requestBody: smallRequest).statusCode, 200)
        XCTAssertEqual(store.get(sidekickId: "notes", key: "note:small")?["image"], .string(smallImage))
        let plainChannel = SidekickStoreChannel(store: store)
        XCTAssertEqual(plainChannel.handle(sidekickId: "notes", requestBody: request).statusCode, 400)
    }

    // MARK: End to end from the page

    private func helperScript() throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let scriptURL = testsDirectory.deletingLastPathComponent().appending(path: "sdk/midas-store.js")
        return try String(contentsOf: scriptURL, encoding: .utf8)
    }

    func testThePageStoresAFileAndGetsItBackThroughTheHelper() async throws {
        let script = try helperScript()
        let digest = SHA256.hash(data: Data(script.utf8))
        let scriptHash = "'sha256-\(Data(digest).base64EncodedString())'"
        let html = "<!doctype html><html><body><script>\(script)</script></body></html>"
        let channel = makeChannel()
        let loader = FilesPageLoader(html: html, scriptHashes: [scriptHash])
        let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: loader, platformOrigin: platformOrigin, storeChannel: channel)
        let finished = expectation(description: "page loaded")
        let waiter = FilesPageWaiter(finished: finished)
        webView.navigationDelegate = waiter
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: "notes")))
        await fulfillment(of: [finished], timeout: 10)

        let roundTrip = """
        var blob = new Blob(['hello files'], { type: 'text/plain' });
        var ref = await store.putFile(blob);
        await store.set('note:1', { text: 'see the file', image: ref });
        var url = await store.fileUrl(ref);
        var response = await fetch(window.location.origin + '/_midas/files/' + ref.slice(5));
        var text = await response.text();
        return JSON.stringify({ ref: ref, isBlobUrl: url.indexOf('blob:') === 0, text: text, type: response.headers.get('Content-Type') });
        """
        let outcomeText = try await webView.callAsyncJavaScript(roundTrip, contentWorld: .page) as? String
        let outcome = try JSONDecoder().decode(JSONValue.self, from: Data(try XCTUnwrap(outcomeText).utf8))
        let reference = try XCTUnwrap(outcome["ref"]?.stringValue)
        let fileId = try XCTUnwrap(FileStore.fileId(fromReference: reference))
        XCTAssertEqual(outcome["isBlobUrl"], .bool(true))
        XCTAssertEqual(outcome["text"], .string("hello files"))
        XCTAssertEqual(outcome["type"], .string("text/plain"))
        XCTAssertEqual(files.data(for: fileId)?.data, Data("hello files".utf8))
        XCTAssertEqual(store.get(sidekickId: "notes", key: "note:1")?["image"], .string(reference))
        XCTAssertEqual(files.pendingUploads(), [fileId])

        let missing = try await webView.callAsyncJavaScript("try { await store.fileUrl('file:neverstored00001'); return 'found'; } catch (error) { return error.message; }", contentWorld: .page) as? String
        XCTAssertEqual(missing, "no such file")
        _ = waiter
    }
}
