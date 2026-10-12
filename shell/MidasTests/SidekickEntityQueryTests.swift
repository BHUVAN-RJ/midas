import XCTest
@testable import Midas

/// The Folder widget's configuration sheet reads the shared list file the app writes
/// (shell/Shared/SidekickEntity.swift; brief docs/briefs/widget-extension.md).
final class SidekickEntityQueryTests: XCTestCase {
    private var sampleFileURL: URL!

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sampleFileURL = directory.appending(path: "widget-sidekicks.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: sampleFileURL.deletingLastPathComponent())
    }

    func testSuggestedEntitiesAreTheSharedListInHomeGridOrder() async throws {
        try writeSampleList(sampleEntries())
        let query = SidekickEntityQuery(listFileURL: sampleFileURL)

        let suggested = try await query.suggestedEntities()

        XCTAssertEqual(suggested.map(\.id), ["reminders", "groceries", "habits"])
        XCTAssertEqual(suggested.map(\.name), ["Reminders", "Groceries", "Habits"])
    }

    func testEntitiesForIdsResolveFromTheSharedListAndSkipUnknownIds() async throws {
        try writeSampleList(sampleEntries())
        let query = SidekickEntityQuery(listFileURL: sampleFileURL)

        let resolved = try await query.entities(for: ["habits", "deleted", "reminders"])

        XCTAssertEqual(resolved.map(\.id), ["habits", "reminders"])
    }

    func testNoFileGivesNoEntities() async throws {
        let query = SidekickEntityQuery(listFileURL: sampleFileURL)

        let suggested = try await query.suggestedEntities()

        XCTAssertEqual(suggested.count, 0)
    }

    func testNoAppGroupGivesNoEntities() async throws {
        let query = SidekickEntityQuery(listFileURL: nil)

        let suggested = try await query.suggestedEntities()

        XCTAssertEqual(suggested.count, 0)
    }

    func testAFileOfAnUnknownFormatGivesNoEntities() async throws {
        let list = SharedSidekickList(sidekicks: sampleEntries(), savedAt: Date())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: list.encoded()) as? [String: Any])
        object["formatVersion"] = SharedSidekickList.currentFormatVersion + 1
        try JSONSerialization.data(withJSONObject: object).write(to: sampleFileURL)
        let query = SidekickEntityQuery(listFileURL: sampleFileURL)

        let suggested = try await query.suggestedEntities()

        XCTAssertEqual(suggested.count, 0)
    }

    func testTheEntityShowsTheSidekicksName() {
        let groceries = SidekickEntry(id: "groceries", name: "Groceries", symbolName: "cart", backgroundHex: "#30D5C8", version: "v2")

        let entity = SidekickEntity(entry: groceries)

        XCTAssertEqual(entity.id, "groceries")
        XCTAssertEqual(entity.name, "Groceries")
    }

    func testTheReaderReadsWhatTheAppWrites() throws {
        try writeSampleList(sampleEntries())

        let list = SharedSidekickListReader.read(from: sampleFileURL)

        XCTAssertEqual(list?.sidekicks.map(\.id), ["reminders", "groceries", "habits"])
        XCTAssertNil(SharedSidekickListReader.read(from: nil))
    }

    // MARK: Helpers

    private func sampleEntries() -> [SidekickEntry] {
        let reminders = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#FFFFFF", version: "v1")
        let groceries = SidekickEntry(id: "groceries", name: "Groceries", symbolName: "cart", backgroundHex: "#30D5C8", version: "v2")
        let habits = SidekickEntry(id: "habits", name: "Habits", symbolName: "flame", backgroundHex: "#FFBF00", version: "v1")
        return [reminders, groceries, habits]
    }

    private func writeSampleList(_ entries: [SidekickEntry]) throws {
        let list = SharedSidekickList(sidekicks: entries, savedAt: Date(timeIntervalSince1970: 1_791_700_000))
        try list.encoded().write(to: sampleFileURL)
    }
}
