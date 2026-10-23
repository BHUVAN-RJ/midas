import Foundation

/// What the server said about one upload attempt.
enum RepairUploadOutcome: Equatable, Sendable {
    /// Stored (2xx). The report leaves the outbox.
    case accepted
    /// Refused for good (400, 413, 422): retrying would never succeed. Dropped.
    case rejected(statusCode: Int)
    /// Not now: offline, 401, 429, 5xx. Kept for the next try.
    case retryLater
}

protocol RepairUploadAPI: Sendable {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome
}

/// POST /repairs with the user's session, multipart as the contract describes.
struct RemoteRepairUploadAPI: RepairUploadAPI {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        guard let token = sessionToken() else {
            return .retryLater
        }
        let request = try Self.request(platformOrigin: platformOrigin, report: report, token: token)
        let (_, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Self.outcome(forStatusCode: statusCode)
    }

    static func request(platformOrigin: URL, report: RepairReport, token: String) throws -> URLRequest {
        let boundary = RepairMultipart.makeBoundary()
        var request = URLRequest(url: platformOrigin.appending(path: "repairs"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(RepairMultipart.contentType(boundary: boundary), forHTTPHeaderField: "Content-Type")
        request.httpBody = try RepairMultipart.body(for: report, boundary: boundary)
        return request
    }

    static func outcome(forStatusCode statusCode: Int) -> RepairUploadOutcome {
        switch statusCode {
        case 200...299:
            return .accepted
        case 400, 413, 422:
            return .rejected(statusCode: statusCode)
        default:
            return .retryLater
        }
    }
}

/// Reports waiting to be uploaded, one folder each on disk, so a report made offline survives a
/// relaunch. `manifest.json` holds the text fields; the images and strokes sit beside it.
struct RepairOutbox: Sendable {
    let directoryURL: URL

    private struct Manifest: Codable {
        let clientReportId: String
        let sidekickId: String
        let kind: String
        let bundleVersion: String
        let bundleScope: String
        let transcript: String
        let spokenText: String
        let typedText: String
        let words: [RepairWord]
        let device: String
        let iosVersion: String
        let appVersion: String
        let appBuild: String
        /// Missing in reports queued before 2026-10-23.
        let voiceError: String?
        let queuedAt: Date
    }

    private enum FileName {
        static let manifest = "manifest.json"
        static let strokes = "strokes.json"
        static let screenshot = "screenshot.jpg"
        static let drawing = "drawing.png"
    }

    static func defaultDirectoryURL() -> URL {
        let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return supportDirectory.appending(path: "repairs")
    }

    func enqueue(_ report: RepairReport) throws {
        let folder = directoryURL.appending(path: report.clientReportId)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = Manifest(
            clientReportId: report.clientReportId,
            sidekickId: report.sidekickId,
            kind: report.kind,
            bundleVersion: report.bundleVersion,
            bundleScope: report.bundleScope,
            transcript: report.transcript,
            spokenText: report.spokenText,
            typedText: report.typedText,
            words: report.words,
            device: report.device,
            iosVersion: report.iosVersion,
            appVersion: report.appVersion,
            appBuild: report.appBuild,
            voiceError: report.voiceError,
            queuedAt: Date()
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: folder.appending(path: FileName.manifest), options: .atomic)
        try report.strokesJSON.write(to: folder.appending(path: FileName.strokes), options: .atomic)
        try report.screenshotJPEG.write(to: folder.appending(path: FileName.screenshot), options: .atomic)
        try report.drawingPNG.write(to: folder.appending(path: FileName.drawing), options: .atomic)
    }

    func remove(clientReportId: String) {
        let folder = directoryURL.appending(path: clientReportId)
        try? FileManager.default.removeItem(at: folder)
    }

    /// Every queued report, oldest first. A folder missing a file is skipped, never crashes.
    func pending() -> [RepairReport] {
        let fileManager = FileManager.default
        guard let folders = try? fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil) else {
            return []
        }
        var reports: [(Date, RepairReport)] = []
        for folder in folders {
            if let loaded = loadReport(from: folder) {
                reports.append(loaded)
            }
        }
        reports.sort { $0.0 < $1.0 }
        return reports.map { $0.1 }
    }

    private func loadReport(from folder: URL) -> (Date, RepairReport)? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifestData = try? Data(contentsOf: folder.appending(path: FileName.manifest)),
              let manifest = try? decoder.decode(Manifest.self, from: manifestData),
              let strokesJSON = try? Data(contentsOf: folder.appending(path: FileName.strokes)),
              let screenshotJPEG = try? Data(contentsOf: folder.appending(path: FileName.screenshot)),
              let drawingPNG = try? Data(contentsOf: folder.appending(path: FileName.drawing)) else {
            return nil
        }
        let report = RepairReport(
            clientReportId: manifest.clientReportId,
            sidekickId: manifest.sidekickId,
            kind: manifest.kind,
            bundleVersion: manifest.bundleVersion,
            bundleScope: manifest.bundleScope,
            transcript: manifest.transcript,
            spokenText: manifest.spokenText,
            typedText: manifest.typedText,
            words: manifest.words,
            strokesJSON: strokesJSON,
            screenshotJPEG: screenshotJPEG,
            drawingPNG: drawingPNG,
            device: manifest.device,
            iosVersion: manifest.iosVersion,
            appVersion: manifest.appVersion,
            appBuild: manifest.appBuild,
            voiceError: manifest.voiceError
        )
        return (manifest.queuedAt, report)
    }
}

/// Sends repair reports and keeps the ones that could not go yet. The user is told nothing:
/// Send dismisses the layer at once and the upload happens here, now or on a later launch.
@MainActor
final class RepairUploader {
    private let api: RepairUploadAPI
    private let outbox: RepairOutbox
    private var isRetrying = false

    init(api: RepairUploadAPI, outbox: RepairOutbox) {
        self.api = api
        self.outbox = outbox
    }

    /// Queues first, so nothing is lost if the app dies mid-upload, then tries at once.
    func send(_ report: RepairReport) async {
        try? outbox.enqueue(report)
        await attempt(report)
    }

    /// Everything still queued, oldest first. Called when the app comes to the foreground.
    func retryQueued() async {
        guard !isRetrying else {
            return
        }
        isRetrying = true
        for report in outbox.pending() {
            await attempt(report)
        }
        isRetrying = false
    }

    var pendingCount: Int {
        outbox.pending().count
    }

    private func attempt(_ report: RepairReport) async {
        let outcome: RepairUploadOutcome
        do {
            outcome = try await api.upload(report)
        } catch {
            outcome = .retryLater
        }
        switch outcome {
        case .accepted, .rejected:
            outbox.remove(clientReportId: report.clientReportId)
        case .retryLater:
            break
        }
    }
}
