import XCTest
@testable import Midas

/// Returns a fixed list, or fails, as GET /sidekicks would.
private final class StubDirectoryFetcher: SidekickDirectoryFetching, @unchecked Sendable {
    var result: Result<[SidekickEntry], Error>

    init(result: Result<[SidekickEntry], Error>) {
        self.result = result
    }

    func fetchSidekicks() async throws -> [SidekickEntry] {
        try result.get()
    }
}

private let remindersEntry = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FF9500", version: "v2")
private let calendarEntry = SidekickEntry(id: "calendar", name: "Calendar", symbolName: "calendar", backgroundHex: "#FF3B30", version: "c1")

private func httpResponse(status: Int, headers: [String: String] = [:]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://example.test/")!, statusCode: status, httpVersion: nil, headerFields: headers)!
}

final class PlatformConfigTests: XCTestCase {
    func testOnlyTheTwoMidasServersAreAccepted() {
        XCTAssertEqual(PlatformConfig.origin(forHost: PlatformConfig.stagingHost).host(), PlatformConfig.stagingHost)
        XCTAssertEqual(PlatformConfig.origin(forHost: PlatformConfig.liveHost).host(), PlatformConfig.liveHost)
        XCTAssertEqual(PlatformConfig.origin(forHost: nil).host(), PlatformConfig.liveHost)
        XCTAssertEqual(PlatformConfig.origin(forHost: "evil.example").host(), PlatformConfig.liveHost)
        XCTAssertEqual(PlatformConfig.origin(forHost: "$(MIDAS_PLATFORM_HOST)").host(), PlatformConfig.liveHost)
    }

    // Tests run as a Debug build, which is the one pressing Run in Xcode installs: staging.
    func testDebugBuildTalksToStaging() {
        XCTAssertEqual(PlatformConfig.platformOrigin.host(), PlatformConfig.stagingHost)
    }

    // Passkeys work only for domains in the entitlements; both servers must be there.
    func testEntitlementsListBothPasskeyDomains() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let entitlementsURL = testFile.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Midas/Midas.entitlements")
        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any]
        let domains = entitlements?["com.apple.developer.associated-domains"] as? [String] ?? []
        XCTAssertTrue(domains.contains("webcredentials:\(PlatformConfig.liveHost)"))
        XCTAssertTrue(domains.contains("webcredentials:\(PlatformConfig.stagingHost)"))
        XCTAssertTrue(domains.contains("webcredentials:\(PlatformConfig.platformOrigin.host() ?? "")"))
    }
}

final class SidekickBundleRequestTests: XCTestCase {
    private let origin = URL(string: "https://midas-api-staging.midas-backend.workers.dev")!

    func testBundleRequestCarriesTheSession() {
        let request = RemoteSidekickBundleLoader.bundleRequest(platformOrigin: origin, sidekickId: "reminders", token: "abc")
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api-staging.midas-backend.workers.dev/sidekicks/reminders/bundle")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
    }

    func testBundleRequestWithoutSessionSendsNoAuthorization() {
        let request = RemoteSidekickBundleLoader.bundleRequest(platformOrigin: origin, sidekickId: "reminders", token: nil)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }

    func testBundleResponsesMapToErrorsOrABundle() throws {
        XCTAssertThrowsError(try RemoteSidekickBundleLoader.bundle(from: Data(), response: httpResponse(status: 401))) { error in
            XCTAssertEqual(error as? SidekickBundleError, .signInRequired)
        }
        XCTAssertThrowsError(try RemoteSidekickBundleLoader.bundle(from: Data(), response: httpResponse(status: 404))) { error in
            XCTAssertEqual(error as? SidekickBundleError, .notFound)
        }
        let headers = ["X-Midas-Bundle-Version": "v2", "X-Midas-Script-Hashes": "'sha256-AAAA'"]
        let bundle = try RemoteSidekickBundleLoader.bundle(from: Data("<p>hi</p>".utf8), response: httpResponse(status: 200, headers: headers))
        XCTAssertEqual(bundle.version, "v2")
        XCTAssertEqual(String(data: bundle.html, encoding: .utf8), "<p>hi</p>")
    }

    func testDirectoryRequestCarriesTheSession() {
        let request = RemoteSidekickDirectoryFetcher.directoryRequest(platformOrigin: origin, token: "abc")
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api-staging.midas-backend.workers.dev/sidekicks")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
    }
}

final class SidekickDirectoryParsingTests: XCTestCase {
    func testParsesTheBackendReply() throws {
        let reply = """
        {"sidekicks":[{"id":"reminders","name":"Reminders","icon":{"symbol":"checklist","background":"#FF9500"},"reads":[],"version":"v2"}]}
        """
        let entries = try RemoteSidekickDirectoryFetcher.entries(from: Data(reply.utf8))
        XCTAssertEqual(entries, [remindersEntry])
    }

    func testRejectsAMalformedReply() {
        XCTAssertThrowsError(try RemoteSidekickDirectoryFetcher.entries(from: Data("{\"sidekicks\":[{\"id\":1}]}".utf8))) { error in
            XCTAssertEqual(error as? SidekickDirectoryError, .badResponse)
        }
    }

    func testHexColors() {
        let orange = SidekickColor.rgbComponents(fromHex: "#FF9500")
        XCTAssertEqual(orange?.red, 1)
        XCTAssertEqual(orange?.green ?? 0, 149.0 / 255, accuracy: 0.0001)
        XCTAssertEqual(orange?.blue, 0)
        XCTAssertNil(SidekickColor.rgbComponents(fromHex: "orange"))
        XCTAssertNil(SidekickColor.rgbComponents(fromHex: "#GG0000"))
    }
}

@MainActor
final class SidekickDirectoryTests: XCTestCase {
    private var cacheURL: URL!

    override func setUp() async throws {
        cacheURL = FileManager.default.temporaryDirectory.appending(path: "directory-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheURL)
    }

    func testRefreshShowsTheServerListAndSavesIt() async {
        let fetcher = StubDirectoryFetcher(result: .success([remindersEntry, calendarEntry]))
        let directory = SidekickDirectory(cacheFileURL: cacheURL, fetcher: fetcher)
        XCTAssertEqual(directory.entries, [])
        XCTAssertFalse(directory.hasLoadedFromServer)

        await directory.refresh()
        XCTAssertEqual(directory.entries, [remindersEntry, calendarEntry])
        XCTAssertTrue(directory.hasLoadedFromServer)

        // Next launch, no connection: the saved list shows.
        let offlineFetcher = StubDirectoryFetcher(result: .failure(URLError(.notConnectedToInternet)))
        let relaunched = SidekickDirectory(cacheFileURL: cacheURL, fetcher: offlineFetcher)
        XCTAssertEqual(relaunched.entries, [remindersEntry, calendarEntry])
        await relaunched.refresh()
        XCTAssertEqual(relaunched.entries, [remindersEntry, calendarEntry])
    }

    func testAnEmptyServerListEmptiesTheFolder() async {
        let fetcher = StubDirectoryFetcher(result: .success([remindersEntry]))
        let directory = SidekickDirectory(cacheFileURL: cacheURL, fetcher: fetcher)
        await directory.refresh()
        fetcher.result = .success([])
        await directory.refresh()
        XCTAssertEqual(directory.entries, [])
    }

    func testCacheFileIsPerServer() {
        let liveURL = SidekickDirectory.defaultCacheFileURL(platformOrigin: PlatformConfig.origin(forHost: PlatformConfig.liveHost))
        let stagingURL = SidekickDirectory.defaultCacheFileURL(platformOrigin: PlatformConfig.origin(forHost: PlatformConfig.stagingHost))
        XCTAssertNotEqual(liveURL, stagingURL)
    }

    func testRouterOpensOnlyListedSidekicks() async {
        let fetcher = StubDirectoryFetcher(result: .success([remindersEntry]))
        let directory = SidekickDirectory(cacheFileURL: cacheURL, fetcher: fetcher)
        await directory.refresh()
        let router = SidekickRouter(directory: directory)

        router.open(sidekickId: "calendar")
        XCTAssertEqual(router.path, [])
        router.open(sidekickId: "reminders")
        XCTAssertEqual(router.path, [remindersEntry])
    }
}
