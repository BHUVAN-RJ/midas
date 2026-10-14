import XCTest
@testable import Midas

/// What intake (backend/src/repairs.ts, merged to main 2026-10-14) refuses with 400, the shell
/// never sends: strokes must be a JSON array; bundleScope must be user or base or absent.
final class RepairIntakeCompatibilityTests: XCTestCase {
    private func makeReport(bundleScope: String) -> RepairReport {
        RepairReport(
            clientReportId: "r", sidekickId: "reminders", kind: "unknown", bundleVersion: "v1", bundleScope: bundleScope,
            transcript: "the tag is wrong", spokenText: "the tag is wrong", typedText: "", words: [],
            strokesJSON: Data("[]".utf8), screenshotJPEG: Data([1]), drawingPNG: Data([2]),
            device: "iPhone17,1", iosVersion: "26.0", appVersion: "0.1.0", appBuild: "2"
        )
    }

    func testStrokesAreAJSONArrayOfPointLists() throws {
        let strokes = [RepairStroke(points: [[10, 20, 0], [30, 40, 50]]), RepairStroke(points: [[100, 100, 900]])]
        let data = try RepairStrokesJSON.encode(strokes: strokes)
        let parsed = try JSONSerialization.jsonObject(with: data)
        let array = try XCTUnwrap(parsed as? [[[Double]]], "strokes must be a JSON array, got \(String(decoding: data, as: UTF8.self))")
        XCTAssertEqual(array, [[[10, 20, 0], [30, 40, 50]], [[100, 100, 900]]])
        XCTAssertEqual(try RepairStrokesJSON.decode(data), strokes)
    }

    func testNoStrokesIsAnEmptyArray() throws {
        let data = try RepairStrokesJSON.encode(strokes: [])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[]")
    }

    func testUnknownBundleScopeIsLeftOut() throws {
        let body = try RepairMultipart.body(for: makeReport(bundleScope: "unknown"), boundary: "b")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"bundleScope\""), "an unknown scope would be a 400")
    }

    func testKnownBundleScopeIsSent() throws {
        for scope in ["user", "base"] {
            let body = try RepairMultipart.body(for: makeReport(bundleScope: scope), boundary: "b")
            let text = String(decoding: body, as: UTF8.self)
            XCTAssertTrue(text.contains("name=\"bundleScope\"\r\n\r\n\(scope)\r\n"), "scope \(scope) missing")
        }
    }

    func testShortFieldsFitIntakeLimit() throws {
        let body = try RepairMultipart.body(for: makeReport(bundleScope: "base"), boundary: "b")
        let text = String(decoding: body, as: UTF8.self)
        for name in ["bundleVersion", "clientReportId", "device", "iosVersion", "appVersion", "appBuild"] {
            XCTAssertTrue(text.contains("name=\"\(name)\""), "\(name) missing")
        }
        XCTAssertLessThanOrEqual(UUID().uuidString.count, 80, "clientReportId must fit intake's 80-character short field")
    }
}
