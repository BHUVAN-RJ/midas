import XCTest
@testable import Midas

/// Returns a fixed list, as GET /sidekicks would.
private struct FixedDirectoryFetcher: SidekickDirectoryFetching {
    let entries: [SidekickEntry]

    func fetchSidekicks() async throws -> [SidekickEntry] {
        entries
    }
}

/// A writer that keeps the test away from the real App Group container.
private func silentWriter() -> SharedSidekickListWriter {
    SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: {})
}

private let remindersEntry = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FF9500", version: "v2")

/// midas:// links from a widget tile reach the router (shell/Midas/MidasLinkHandler.swift).
@MainActor
final class MidasLinkHandlerTests: XCTestCase {
    private var cacheFileURL: URL!

    override func setUp() async throws {
        cacheFileURL = FileManager.default.temporaryDirectory.appending(path: "link-directory-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheFileURL)
    }

    private func makeLoadedRouter() async -> SidekickRouter {
        let fetcher = FixedDirectoryFetcher(entries: [remindersEntry])
        let directory = SidekickDirectory(cacheFileURL: cacheFileURL, fetcher: fetcher, sharedListWriter: silentWriter())
        await directory.refresh()
        return SidekickRouter(directory: directory)
    }

    func testOpenLinkOpensAKnownSidekick() async {
        let router = await makeLoadedRouter()
        MidasLinkHandler.handle(url: MidasLink.openSidekick(id: "reminders").url, router: router)
        XCTAssertEqual(router.path, [remindersEntry])
    }

    func testOpenLinkIgnoresAnUnknownSidekick() async {
        let router = await makeLoadedRouter()
        MidasLinkHandler.handle(url: MidasLink.openSidekick(id: "calendar").url, router: router)
        XCTAssertEqual(router.path, [])
    }

    func testHomeLinkEmptiesThePath() async {
        let router = await makeLoadedRouter()
        router.open(sidekickId: "reminders")
        XCTAssertEqual(router.path, [remindersEntry])

        MidasLinkHandler.handle(url: MidasLink.home.url, router: router)
        XCTAssertEqual(router.path, [])
    }

    func testOtherLinksChangeNothing() async throws {
        let router = await makeLoadedRouter()
        router.open(sidekickId: "reminders")
        let unrelated = try XCTUnwrap(URL(string: "https://example.test/open/reminders"))
        MidasLinkHandler.handle(url: unrelated, router: router)
        XCTAssertEqual(router.path, [remindersEntry])
    }

    // Before the directory has loaded (or signed out) there is nothing to open; the link is dropped.
    func testOpenLinkBeforeTheDirectoryLoadsIsDropped() {
        let fetcher = FixedDirectoryFetcher(entries: [remindersEntry])
        let directory = SidekickDirectory(cacheFileURL: cacheFileURL, fetcher: fetcher, sharedListWriter: silentWriter())
        let router = SidekickRouter(directory: directory)
        MidasLinkHandler.handle(url: MidasLink.openSidekick(id: "reminders").url, router: router)
        XCTAssertEqual(router.path, [])
    }
}

/// The built app must claim the midas scheme and the App Group, or links and the shared file
/// never reach it.
final class WidgetAppConfigTests: XCTestCase {
    func testInfoPlistRegistersTheMidasScheme() {
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        var schemes: [String] = []
        for urlType in urlTypes {
            let typeSchemes = urlType["CFBundleURLSchemes"] as? [String] ?? []
            schemes.append(contentsOf: typeSchemes)
        }
        XCTAssertTrue(schemes.contains(MidasLink.scheme), "schemes: \(schemes)")
    }

    func testEntitlementsCarryTheWidgetAppGroup() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let entitlementsURL = testFile.deletingLastPathComponent().deletingLastPathComponent().appending(path: "Midas/Midas.entitlements")
        let entitlementsData = try Data(contentsOf: entitlementsURL)
        let entitlements = try PropertyListSerialization.propertyList(from: entitlementsData, format: nil) as? [String: Any]
        let groups = entitlements?["com.apple.security.application-groups"] as? [String] ?? []
        XCTAssertEqual(groups, [WidgetShared.appGroupIdentifier])
    }
}
