import Foundation
import UIKit

/// One drawn stroke over the frozen Sidekick: points `[x, y, ms]`, ms on the session clock
/// (0 = the moment the swipe fired).
struct RepairStroke: Codable, Equatable, Sendable {
    var points: [[Double]]

    init(points: [[Double]] = []) {
        self.points = points
    }
}

/// One spoken word with its time on the session clock (same clock as the strokes), so a later
/// enhancement can match "here" to a stroke (docs/ENHANCEMENTS.md #1).
typealias RepairWord = VoiceWord

/// Rebases speech-recogniser timings (seconds since the audio started) onto the session clock.
typealias RepairWordTiming = VoiceWordTiming

/// Everything POST /repairs receives (docs/briefs/repair-contract.md). Audio is never part of it:
/// transcription happens on the phone and only the words leave.
struct RepairReport: Equatable, Sendable {
    let clientReportId: String
    let sidekickId: String
    let kind: String
    let bundleVersion: String
    let bundleScope: String
    /// Spoken words, then a blank line, then what was typed; never empty (the server rejects it).
    let transcript: String
    let spokenText: String
    let typedText: String
    let words: [RepairWord]
    let strokesJSON: Data
    let screenshotJPEG: Data
    let drawingPNG: Data
    let device: String
    let iosVersion: String
    let appVersion: String
    let appBuild: String

    /// Kinds the contract accepts (founder, 2026-10-13: bug, change, feature). The shell sends
    /// `unknown`: the kind is a hint and the agent decides from the transcript.
    static let contractKinds = ["bug", "change", "feature", "unknown"]
    static let unknownKind = "unknown"
}

enum RepairReportError: Error, Equatable {
    case emptyTranscript
    case imageEncodingFailed
}

/// What the phone adds to a report: model, iOS and app version.
struct RepairDeviceInfo: Equatable, Sendable {
    let device: String
    let iosVersion: String
    let appVersion: String
    let appBuild: String

    @MainActor
    static func current() -> RepairDeviceInfo {
        let bundleInfo = Bundle.main.infoDictionary ?? [:]
        let appVersion = bundleInfo["CFBundleShortVersionString"] as? String ?? "unknown"
        let appBuild = bundleInfo["CFBundleVersion"] as? String ?? "unknown"
        return RepairDeviceInfo(device: hardwareModel(), iosVersion: UIDevice.current.systemVersion, appVersion: appVersion, appBuild: appBuild)
    }

    /// "iPhone17,1" style identifier, from the kernel; the Simulator reports its own model.
    private static func hardwareModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        var identifier = ""
        for child in machineMirror.children {
            guard let value = child.value as? Int8, value != 0 else {
                continue
            }
            identifier.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }
}

/// Builds the report from a finished repair session. Refuses an empty transcript: the backend
/// rejects it, so the shell never sends one.
enum RepairReportBuilder {
    static func combinedTranscript(spokenText: String, typedText: String) -> String {
        let spoken = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let typed = typedText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (spoken.isEmpty, typed.isEmpty) {
        case (true, true):
            return ""
        case (false, true):
            return spoken
        case (true, false):
            return typed
        case (false, false):
            return spoken + "\n\n" + typed
        }
    }

    static func build(
        clientReportId: String,
        sidekickId: String,
        bundle: SidekickBundleVersions.Entry,
        spokenText: String,
        typedText: String,
        words: [RepairWord],
        strokes: [RepairStroke],
        screenshot: UIImage,
        drawing: UIImage,
        viewSize: CGSize,
        screenScale: CGFloat,
        sessionStartedAt: Date,
        deviceInfo: RepairDeviceInfo
    ) throws -> RepairReport {
        let transcript = combinedTranscript(spokenText: spokenText, typedText: typedText)
        guard !transcript.isEmpty else {
            throw RepairReportError.emptyTranscript
        }
        guard let screenshotJPEG = screenshot.jpegData(compressionQuality: 0.8), let drawingPNG = drawing.pngData() else {
            throw RepairReportError.imageEncodingFailed
        }
        // viewSize, screenScale and sessionStartedAt describe the session but are not sent: the
        // screenshot carries the view, and the server stamps the report's time.
        _ = (viewSize, screenScale, sessionStartedAt)
        let strokesJSON = try RepairStrokesJSON.encode(strokes: strokes)
        return RepairReport(
            clientReportId: clientReportId,
            sidekickId: sidekickId,
            kind: RepairReport.unknownKind,
            bundleVersion: bundle.version,
            bundleScope: bundle.scope,
            transcript: transcript,
            spokenText: spokenText.trimmingCharacters(in: .whitespacesAndNewlines),
            typedText: typedText.trimmingCharacters(in: .whitespacesAndNewlines),
            words: words,
            strokesJSON: strokesJSON,
            screenshotJPEG: screenshotJPEG,
            drawingPNG: drawingPNG,
            device: deviceInfo.device,
            iosVersion: deviceInfo.iosVersion,
            appVersion: deviceInfo.appVersion,
            appBuild: deviceInfo.appBuild
        )
    }
}

/// The `strokes` part. Intake (backend/src/repairs.ts, merged 2026-10-14) requires a JSON array;
/// its fixture shape is one array of `[x, y, ms]` points per stroke: `[[[x, y, ms], ...], ...]`.
/// Points are in web-view points; the screenshot carries the view's size and scale.
enum RepairStrokesJSON {
    static func encode(strokes: [RepairStroke]) throws -> Data {
        let pointLists = strokes.map(pointList)
        return try JSONEncoder().encode(pointLists)
    }

    static func decode(_ data: Data) throws -> [RepairStroke] {
        let pointLists = try JSONDecoder().decode([[[Double]]].self, from: data)
        return pointLists.map(RepairStroke.init(points:))
    }

    private static func pointList(of stroke: RepairStroke) -> [[Double]] {
        stroke.points
    }
}

/// The `drawing` part: the strokes drawn over the screenshot, as the user saw them.
enum RepairDrawingRenderer {
    static let lineWidth: CGFloat = 5

    /// The ink line under the Volt pen in light mode (V1, founder 2026-10-23): 8 pt.
    static let keylineWidth: CGFloat = 8

    static func render(screenshot: UIImage, strokes: [RepairStroke], penColor: UIColor, lineWidth: CGFloat = lineWidth, keylineColor: UIColor? = nil) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenshot.scale
        let renderer = UIGraphicsImageRenderer(size: screenshot.size, format: format)
        return renderer.image { context in
            screenshot.draw(at: .zero)
            let cgContext = context.cgContext
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            // Every ink line first, so a crossing stroke's ink never cuts through Volt
            if let keylineColor {
                cgContext.setStrokeColor(keylineColor.cgColor)
                cgContext.setLineWidth(keylineWidth)
                for stroke in strokes {
                    addPath(of: stroke, to: cgContext)
                    cgContext.strokePath()
                }
            }
            cgContext.setStrokeColor(penColor.cgColor)
            cgContext.setLineWidth(lineWidth)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            for stroke in strokes {
                addPath(of: stroke, to: cgContext)
                cgContext.strokePath()
            }
        }
    }

    private static func addPath(of stroke: RepairStroke, to cgContext: CGContext) {
        let points = stroke.points.compactMap(pointFromArray)
        guard let first = points.first else {
            return
        }
        cgContext.beginPath()
        cgContext.move(to: first)
        // A single tap leaves a dot, not nothing.
        if points.count == 1 {
            cgContext.addLine(to: first)
        }
        for point in points.dropFirst() {
            cgContext.addLine(to: point)
        }
    }

    private static func pointFromArray(_ array: [Double]) -> CGPoint? {
        guard array.count >= 2 else {
            return nil
        }
        return CGPoint(x: array[0], y: array[1])
    }
}

/// Encodes a report as multipart/form-data for POST /repairs.
enum RepairMultipart {
    enum Part {
        static let clientReportId = "clientReportId"
        static let sidekickId = "sidekickId"
        static let kind = "kind"
        static let bundleVersion = "bundleVersion"
        static let bundleScope = "bundleScope"
        static let transcript = "transcript"
        static let typedText = "typedText"
        static let transcriptWords = "transcriptWords"
        static let strokes = "strokes"
        static let screenshot = "screenshot"
        static let drawing = "drawing"
        static let device = "device"
        static let iosVersion = "iosVersion"
        static let appVersion = "appVersion"
        static let appBuild = "appBuild"
    }

    /// `X-Midas-Bundle-Scope` values intake stores (backend/src/repairs.ts BUNDLE_SCOPES).
    static let contractScopes: Set<String> = ["user", "base"]

    static func makeBoundary() -> String {
        "midas-repair-" + UUID().uuidString
    }

    static func contentType(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }

    static func body(for report: RepairReport, boundary: String) throws -> Data {
        var body = Data()
        appendText(&body, boundary: boundary, name: Part.clientReportId, value: report.clientReportId)
        appendText(&body, boundary: boundary, name: Part.sidekickId, value: report.sidekickId)
        appendText(&body, boundary: boundary, name: Part.kind, value: report.kind)
        appendText(&body, boundary: boundary, name: Part.bundleVersion, value: report.bundleVersion)
        // Intake accepts only user or base and rejects anything else with 400; a scope the shell
        // never learned (no header yet) is left out.
        if contractScopes.contains(report.bundleScope) {
            appendText(&body, boundary: boundary, name: Part.bundleScope, value: report.bundleScope)
        }
        appendText(&body, boundary: boundary, name: Part.transcript, value: report.transcript)
        appendText(&body, boundary: boundary, name: Part.typedText, value: report.typedText)
        let wordsJSON = try JSONEncoder().encode(report.words)
        appendFile(&body, boundary: boundary, name: Part.transcriptWords, filename: "transcript-words.json", contentType: "application/json", data: wordsJSON)
        appendFile(&body, boundary: boundary, name: Part.strokes, filename: "strokes.json", contentType: "application/json", data: report.strokesJSON)
        appendFile(&body, boundary: boundary, name: Part.screenshot, filename: "screenshot.jpg", contentType: "image/jpeg", data: report.screenshotJPEG)
        appendFile(&body, boundary: boundary, name: Part.drawing, filename: "drawing.png", contentType: "image/png", data: report.drawingPNG)
        appendText(&body, boundary: boundary, name: Part.device, value: report.device)
        appendText(&body, boundary: boundary, name: Part.iosVersion, value: report.iosVersion)
        appendText(&body, boundary: boundary, name: Part.appVersion, value: report.appVersion)
        appendText(&body, boundary: boundary, name: Part.appBuild, value: report.appBuild)
        body.append(Data("--\(boundary)--\r\n".utf8))
        return body
    }

    private static func appendText(_ body: inout Data, boundary: String, name: String, value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data(value.utf8))
        body.append(Data("\r\n".utf8))
    }

    private static func appendFile(_ body: inout Data, boundary: String, name: String, filename: String, contentType: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(contentType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }
}

extension RepairReport {
    /// The same report under a new phone id: Try Again sends it again, and the server keeps one
    /// row per phone id, so a resend needs its own.
    func resent(clientReportId newClientReportId: String) -> RepairReport {
        RepairReport(
            clientReportId: newClientReportId,
            sidekickId: sidekickId,
            kind: kind,
            bundleVersion: bundleVersion,
            bundleScope: bundleScope,
            transcript: transcript,
            spokenText: spokenText,
            typedText: typedText,
            words: words,
            strokesJSON: strokesJSON,
            screenshotJPEG: screenshotJPEG,
            drawingPNG: drawingPNG,
            device: device,
            iosVersion: iosVersion,
            appVersion: appVersion,
            appBuild: appBuild
        )
    }
}
