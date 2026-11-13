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
    /// The Worker sorts each report and answers with its lane (repair lanes, 2026-11-13). False:
    /// Send closes the layer at once, as before the lanes.
    var sortsReports: Bool { get }
    /// The upload, with the sort's reply when the Worker sent one.
    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload
    /// The person's answer to the question card; the reply is the same request sorted again.
    func answer(repairId: String, answer: RepairSortAnswer) async throws -> RepairSortReply?
    /// The same, telling a dropped card (410) apart from a failure.
    func answerOutcome(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome
}

/// One upload and, when the Worker sorted it, its lane.
struct RepairSortedUpload: Equatable, Sendable {
    let outcome: RepairUploadOutcome
    let reply: RepairSortReply?
}

// An upload API that does not sort: every report goes to the edit lane as before
extension RepairUploadAPI {
    var sortsReports: Bool {
        false
    }

    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        let outcome = try await upload(report)
        return RepairSortedUpload(outcome: outcome, reply: nil)
    }

    func answer(repairId: String, answer: RepairSortAnswer) async throws -> RepairSortReply? {
        nil
    }

    // From `answer`: a reply is sorted, nothing or an error failed
    func answerOutcome(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome {
        guard let reply = try? await self.answer(repairId: repairId, answer: answer) else {
            return .failed
        }
        return .sorted(reply)
    }
}

/// POST /repairs with the user's session, multipart as the contract describes.
struct RemoteRepairUploadAPI: RepairUploadAPI {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        let sorted = try await uploadSorted(report)
        return sorted.outcome
    }

    var sortsReports: Bool {
        true
    }

    /// POST /repairs; a 2xx body carries the lane once the Worker sorts (W2). Today's
    /// `{ id, status }` reads as the edit lane. With the Debug stub on, nothing is uploaded.
    func uploadSorted(_ report: RepairReport) async throws -> RepairSortedUpload {
        if RepairSortStub.isOn {
            let reply = RepairSortStub.reply(transcript: report.transcript, sidekickId: report.sidekickId, reportId: report.clientReportId)
            return RepairSortedUpload(outcome: .accepted, reply: reply)
        }
        guard let token = sessionToken() else {
            return RepairSortedUpload(outcome: .retryLater, reply: nil)
        }
        var request = try Self.request(platformOrigin: platformOrigin, report: report, token: token)
        // The sort can take about 12 s before the Worker answers
        request.timeoutInterval = RepairAskBackSpec.requestTimeoutSeconds
        let (body, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let outcome = Self.outcome(forStatusCode: statusCode)
        let reply = outcome == .accepted ? RepairSortReply.decode(body) : nil
        return RepairSortedUpload(outcome: outcome, reply: reply)
    }

    /// POST /repairs/:id/answer with `{ optionId }` or `{ text }`. Nil when it did not go through.
    func answer(repairId: String, answer: RepairSortAnswer) async throws -> RepairSortReply? {
        let outcome = await answerOutcome(repairId: repairId, answer: answer)
        guard case .sorted(let reply) = outcome else {
            return nil
        }
        return reply
    }

    /// The answer route: 2xx is the same request sorted again (`{ lane, message? }`), 410 a card
    /// the Worker dropped, anything else a failure.
    func answerOutcome(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome {
        if RepairSortStub.isOn {
            return .sorted(RepairSortStub.answerReply())
        }
        guard let token = sessionToken() else {
            return .failed
        }
        guard let request = try? Self.answerRequest(platformOrigin: platformOrigin, repairId: repairId, answer: answer, token: token) else {
            return .failed
        }
        guard let (body, response) = try? await session.data(for: request) else {
            return .failed
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return Self.answerOutcome(statusCode: statusCode, body: body)
    }

    static func answerOutcome(statusCode: Int, body: Data) -> RepairAnswerOutcome {
        if statusCode == 410 {
            return .dropped
        }
        guard outcome(forStatusCode: statusCode) == .accepted else {
            return .failed
        }
        return .sorted(RepairSortReply.decode(body))
    }

    static func answerRequest(platformOrigin: URL, repairId: String, answer: RepairSortAnswer, token: String) throws -> URLRequest {
        let path = platformOrigin.appending(path: "repairs").appending(path: repairId).appending(path: "answer")
        var request = URLRequest(url: path)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try answer.jsonBody()
        request.timeoutInterval = RepairAskBackSpec.requestTimeoutSeconds
        return request
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

    /// The Worker sorts reports: Send waits for the lane before the layer closes.
    var sortsReports: Bool {
        api.sortsReports
    }

    /// Queues first, like `send`, then uploads and hands back the sort's reply. Nil when the
    /// upload did not go through now (it stays queued) or the Worker sent no lane.
    func sendSorted(_ report: RepairReport) async -> RepairSortReply? {
        try? outbox.enqueue(report)
        let sorted: RepairSortedUpload
        do {
            sorted = try await api.uploadSorted(report)
        } catch {
            return nil
        }
        switch sorted.outcome {
        case .accepted, .rejected:
            outbox.remove(clientReportId: report.clientReportId)
        case .retryLater:
            break
        }
        return sorted.reply
    }

    /// The answer to the question card: sorted again, dropped (410), or failed.
    func answer(repairId: String, answer: RepairSortAnswer) async -> RepairAnswerOutcome {
        await api.answerOutcome(repairId: repairId, answer: answer)
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
