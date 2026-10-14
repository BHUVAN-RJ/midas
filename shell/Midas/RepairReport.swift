import Foundation
import UIKit

/// One drawn stroke over the frozen Sidekick: points `[x, y, ms]`, ms on the session clock
/// (0 = the moment the scribble fired).
struct RepairStroke: Codable, Equatable, Sendable {
    var points: [[Double]]

    init(points: [[Double]] = []) {
        self.points = points
    }
}

/// One spoken word with its time on the session clock (same clock as the strokes), so a later
/// enhancement can match "here" to a stroke (docs/ENHANCEMENTS.md #1).
struct RepairWord: Codable, Equatable, Sendable {
    let word: String
    let startMs: Int
    let endMs: Int
}

/// Rebases speech-recogniser timings (seconds since the audio started) onto the session clock.
enum RepairWordTiming {
    static func word(_ text: String, segmentTimestamp: TimeInterval, segmentDuration: TimeInterval, audioStartedAt: Date, sessionStartedAt: Date) -> RepairWord {
        let audioOffsetMs = audioStartedAt.timeIntervalSince(sessionStartedAt) * 1000
        let startMs = Int((audioOffsetMs + segmentTimestamp * 1000).rounded())
        let endMs = Int((audioOffsetMs + (segmentTimestamp + segmentDuration) * 1000).rounded())
        return RepairWord(word: text, startMs: startMs, endMs: endMs)
    }
}

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
        let strokesJSON = try RepairStrokesJSON.encode(strokes: strokes, viewSize: viewSize, screenScale: screenScale, sessionStartedAt: sessionStartedAt)
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

/// The `strokes` part: same shape as the founder's capture page, plus the view the points are in.
enum RepairStrokesJSON {
    struct Document: Codable, Equatable {
        struct View: Codable, Equatable {
            let width: Double
            let height: Double
            let units: String
            let scale: Double
            let pointFormat: String
        }

        let view: View
        let sessionStartedAt: String
        let strokes: [RepairStroke]
    }

    static func encode(strokes: [RepairStroke], viewSize: CGSize, screenScale: CGFloat, sessionStartedAt: Date) throws -> Data {
        let view = Document.View(width: viewSize.width, height: viewSize.height, units: "points", scale: screenScale, pointFormat: "[x, y, ms]")
        let document = Document(view: view, sessionStartedAt: ISO8601DateFormatter().string(from: sessionStartedAt), strokes: strokes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(document)
    }

    static func decode(_ data: Data) throws -> Document {
        try JSONDecoder().decode(Document.self, from: data)
    }
}

/// The `drawing` part: the strokes drawn over the screenshot, as the user saw them.
enum RepairDrawingRenderer {
    static let lineWidth: CGFloat = 5

    static func render(screenshot: UIImage, strokes: [RepairStroke], penColor: UIColor, lineWidth: CGFloat = lineWidth) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenshot.scale
        let renderer = UIGraphicsImageRenderer(size: screenshot.size, format: format)
        return renderer.image { context in
            screenshot.draw(at: .zero)
            let cgContext = context.cgContext
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
        appendText(&body, boundary: boundary, name: Part.bundleScope, value: report.bundleScope)
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
