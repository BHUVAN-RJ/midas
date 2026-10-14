import UIKit
import XCTest
@testable import Midas

/// The report that leaves the phone: transcript, strokes, screenshot and drawing are in it;
/// audio never is; an empty transcript is never built (the server rejects it).
final class RepairReportEncoderTests: XCTestCase {
    private static func solidImage(color: UIColor, size: CGSize = CGSize(width: 4, height: 4)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private static let sessionStart = Date(timeIntervalSince1970: 1_760_000_000)

    private func makeReport(spokenText: String = "the tag is wrong", typedText: String = "") throws -> RepairReport {
        let screenshot = Self.solidImage(color: .white)
        let drawing = Self.solidImage(color: .red)
        let words = [RepairWord(word: "the", startMs: 100, endMs: 200), RepairWord(word: "tag", startMs: 200, endMs: 350)]
        let strokes = [RepairStroke(points: [[10, 20, 300], [30, 40, 350]])]
        let bundle = SidekickBundleVersions.Entry(version: "2026-10-13T10:00:00Z", scope: "base")
        let deviceInfo = RepairDeviceInfo(device: "iPhone17,1", iosVersion: "26.0", appVersion: "0.1.0", appBuild: "2")
        return try RepairReportBuilder.build(
            clientReportId: "report-1",
            sidekickId: "reminders",
            bundle: bundle,
            spokenText: spokenText,
            typedText: typedText,
            words: words,
            strokes: strokes,
            screenshot: screenshot,
            drawing: drawing,
            viewSize: CGSize(width: 393, height: 800),
            screenScale: 3,
            sessionStartedAt: Self.sessionStart,
            deviceInfo: deviceInfo
        )
    }

    private func partNames(in body: Data) -> [String] {
        let text = String(decoding: body, as: UTF8.self)
        var names: [String] = []
        for line in text.components(separatedBy: "\r\n") where line.hasPrefix("Content-Disposition: form-data; name=\"") {
            let afterPrefix = line.dropFirst("Content-Disposition: form-data; name=\"".count)
            if let closingQuote = afterPrefix.firstIndex(of: "\"") {
                names.append(String(afterPrefix[..<closingQuote]))
            }
        }
        return names
    }

    func testMultipartCarriesEveryContractPart() throws {
        let report = try makeReport()
        let body = try RepairMultipart.body(for: report, boundary: "b")
        let names = partNames(in: body)
        let required = [
            RepairMultipart.Part.sidekickId, RepairMultipart.Part.kind, RepairMultipart.Part.bundleVersion,
            RepairMultipart.Part.transcript, RepairMultipart.Part.strokes, RepairMultipart.Part.screenshot,
            RepairMultipart.Part.drawing, RepairMultipart.Part.clientReportId, RepairMultipart.Part.transcriptWords,
            RepairMultipart.Part.bundleScope, RepairMultipart.Part.device, RepairMultipart.Part.iosVersion,
            RepairMultipart.Part.appVersion, RepairMultipart.Part.appBuild, RepairMultipart.Part.typedText,
        ]
        for name in required {
            XCTAssertTrue(names.contains(name), "missing part \(name)")
        }
        XCTAssertEqual(names.count, required.count, "unexpected parts: \(names)")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("--b--\r\n"))
        XCTAssertTrue(text.contains("Content-Type: image/jpeg"))
        XCTAssertTrue(text.contains("Content-Type: image/png"))
    }

    func testAudioIsNeverInThePayload() throws {
        let report = try makeReport()
        let body = try RepairMultipart.body(for: report, boundary: "b")
        let text = String(decoding: body, as: UTF8.self).lowercased()
        XCTAssertFalse(text.contains("audio"), "payload mentions audio")
        for name in partNames(in: body) {
            XCTAssertFalse(name.lowercased().contains("audio"))
        }
        let mirror = Mirror(reflecting: report)
        for child in mirror.children {
            XCTAssertFalse((child.label ?? "").lowercased().contains("audio"), "report field \(child.label ?? "") carries audio")
        }
    }

    func testEmptyTranscriptIsRefused() {
        XCTAssertThrowsError(try makeReport(spokenText: "", typedText: "   ")) { error in
            XCTAssertEqual(error as? RepairReportError, .emptyTranscript)
        }
    }

    func testTypedTextAloneIsEnough() throws {
        let report = try makeReport(spokenText: "", typedText: "move the tag")
        XCTAssertEqual(report.transcript, "move the tag")
        XCTAssertEqual(report.spokenText, "")
        XCTAssertEqual(report.typedText, "move the tag")
    }

    func testSpokenAndTypedAreCombinedWithTheSplitKept() throws {
        let report = try makeReport(spokenText: "the tag is wrong", typedText: "second row")
        XCTAssertEqual(report.transcript, "the tag is wrong\n\nsecond row")
        XCTAssertEqual(report.spokenText, "the tag is wrong")
        XCTAssertEqual(report.typedText, "second row")
    }

    func testStrokesJSONIsTheArrayIntakeAccepts() throws {
        let report = try makeReport()
        let strokes = try RepairStrokesJSON.decode(report.strokesJSON)
        XCTAssertEqual(strokes, [RepairStroke(points: [[10, 20, 300], [30, 40, 350]])])
        let parsed = try JSONSerialization.jsonObject(with: report.strokesJSON)
        XCTAssertNotNil(parsed as? [[[Double]]], "intake requires a JSON array of point lists")
    }

    func testKindIsUnknownUntilClassificationExists() throws {
        let report = try makeReport()
        XCTAssertEqual(report.kind, "unknown")
        XCTAssertEqual(report.bundleScope, "base")
        XCTAssertEqual(report.bundleVersion, "2026-10-13T10:00:00Z")
    }

    func testRequestPostsToRepairsWithTheSession() throws {
        let report = try makeReport()
        let origin = URL(string: "https://midas-api-staging.midas-backend.workers.dev")!
        let request = try RemoteRepairUploadAPI.request(platformOrigin: origin, report: report, token: "tok")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api-staging.midas-backend.workers.dev/repairs")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        XCTAssertNotNil(request.httpBody)
    }

    func testBundleVersionsFallBackToUnknown() {
        let versions = SidekickBundleVersions()
        XCTAssertEqual(versions.entry(forSidekickId: "x"), SidekickBundleVersions.Entry(version: "unknown", scope: "unknown"))
        versions.record(sidekickId: "x", version: "v1", scope: "user")
        XCTAssertEqual(versions.entry(forSidekickId: "x"), SidekickBundleVersions.Entry(version: "v1", scope: "user"))
        versions.record(sidekickId: "y", version: "v2", scope: nil)
        XCTAssertEqual(versions.entry(forSidekickId: "y").scope, "unknown")
    }
}
