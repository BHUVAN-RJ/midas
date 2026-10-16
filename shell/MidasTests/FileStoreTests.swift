import XCTest
@testable import Midas

// Files on the phone (unified data plan, section 7): saved first, queued for upload in order,
// never changed; a `data:` URL in an oversize record moves to a file and leaves its reference.

@MainActor
final class FileStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "files-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    func testSavedFilesComeBackWithTheirTypeAndQueueInOrderUntilUploaded() throws {
        let store = FileStore(directoryURL: folder)
        let first = try store.save(Data("first".utf8), contentType: "text/plain")
        let second = try store.save(Data([0x89, 0x50, 0x4e, 0x47]), contentType: "image/png")
        XCTAssertTrue(FileStore.isValidFileId(first))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(store.data(for: first)?.data, Data("first".utf8))
        XCTAssertEqual(store.data(for: first)?.contentType, "text/plain")
        XCTAssertEqual(store.data(for: second)?.contentType, "image/png")
        XCTAssertEqual(store.pendingUploads(), [first, second])
        XCTAssertEqual(store.meta(for: first)?.uploaded, false)

        try store.markUploaded(first)
        XCTAssertEqual(store.pendingUploads(), [second])
        XCTAssertEqual(store.meta(for: first)?.uploaded, true)
        XCTAssertNotNil(store.data(for: first), "an uploaded file stays on the phone")

        let reopened = FileStore(directoryURL: folder)
        XCTAssertEqual(reopened.pendingUploads(), [second])
        XCTAssertEqual(reopened.data(for: second)?.data, Data([0x89, 0x50, 0x4e, 0x47]))
        XCTAssertNil(reopened.data(for: "never-saved-1"))
        XCTAssertNil(reopened.data(for: "../escape"))
    }

    func testADownloadedFileIsKeptWithoutBeingQueued() throws {
        let store = FileStore(directoryURL: folder)
        try store.saveDownloaded(fileId: "abcdefabcdef", data: Data("from the server".utf8), contentType: "text/plain")
        XCTAssertEqual(store.data(for: "abcdefabcdef")?.data, Data("from the server".utf8))
        XCTAssertEqual(store.pendingUploads(), [])
        XCTAssertEqual(store.meta(for: "abcdefabcdef")?.uploaded, true)
        XCTAssertThrowsError(try store.saveDownloaded(fileId: "../bad", data: Data(), contentType: "text/plain"))
    }

    func testReferencesAreFileColonId() {
        XCTAssertEqual(FileStore.reference(for: "abc12345"), "file:abc12345")
        XCTAssertEqual(FileStore.fileId(fromReference: "file:abc12345"), "abc12345")
        XCTAssertNil(FileStore.fileId(fromReference: "abc12345"))
        XCTAssertNil(FileStore.fileId(fromReference: "file:has space"))
        XCTAssertNil(FileStore.fileId(fromReference: "file:short"))
        let generated = FileStore.newFileId()
        XCTAssertEqual(generated.count, 32)
        XCTAssertTrue(FileStore.isValidFileId(generated))
    }

    func testDataURLsAreDecodedAndEverythingElseIsNot() {
        let decoded = FileStore.decodeDataURL("data:image/png;base64,iVBORw0KGgo=")
        XCTAssertEqual(decoded?.contentType, "image/png")
        XCTAssertEqual(decoded?.data, Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
        XCTAssertEqual(FileStore.decodeDataURL("data:;base64,aGk=")?.contentType, "application/octet-stream")
        XCTAssertNil(FileStore.decodeDataURL("data:text/plain,hello"), "only base64 data URLs are files")
        XCTAssertNil(FileStore.decodeDataURL("https://example.test/a.png"))
        XCTAssertNil(FileStore.decodeDataURL("data:image/png;base64,"))
    }

    func testTheSafetyNetMovesDataURLsToFilesAndLeavesTheRest() throws {
        let store = FileStore(directoryURL: folder)
        let pixel = "data:image/png;base64,iVBORw0KGgo="
        let value: JSONValue = .object([
            "title": .string("Screenshot"),
            "image": .string(pixel),
            "notes": .string("data: is a word, not a URL"),
            "gallery": .array([.string(pixel), .number(3)]),
            "nested": .object(["inner": .string("data:text/plain;base64,aGk=")]),
        ])
        let replaced = try store.replacingDataURLs(in: value)
        XCTAssertEqual(replaced["title"], .string("Screenshot"))
        XCTAssertEqual(replaced["notes"], .string("data: is a word, not a URL"))
        let imageReference = try XCTUnwrap(replaced["image"]?.stringValue)
        let imageId = try XCTUnwrap(FileStore.fileId(fromReference: imageReference))
        XCTAssertEqual(store.data(for: imageId)?.contentType, "image/png")
        XCTAssertEqual(store.data(for: imageId)?.data.count, 8)
        XCTAssertNotNil(FileStore.fileId(fromReference: replaced["gallery"]?.arrayValue?[0].stringValue ?? ""))
        XCTAssertEqual(replaced["gallery"]?.arrayValue?[1], .number(3))
        let innerId = try XCTUnwrap(FileStore.fileId(fromReference: replaced["nested"]?["inner"]?.stringValue ?? ""))
        XCTAssertEqual(store.data(for: innerId)?.data, Data("hi".utf8))
        XCTAssertEqual(store.pendingUploads().count, 3, "every moved file is queued for upload")
    }
}
