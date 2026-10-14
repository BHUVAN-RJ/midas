import Foundation
import Observation
import SwiftUI
import WebKit

/// Words on the repair layer (docs/WRITING.md; founder approved the layout 2026-10-13).
enum RepairCopy {
    static let cancelLabel = "Cancel"
    static let undoButton = "Undo"
    static let clearButton = "Clear"
    static let sendButton = "Send"
    static let textPlaceholder = "What to fix"
    static let permissionTitle = "Speak While You Draw"
    static let continueButton = "Continue"
    static let notNowButton = "Not Now"
    static let openSettingsButton = "Open Settings"
}

/// The pen: Tomato light, the first assigned use of the reserved accent (founder, 2026-10-13;
/// docs/DESIGN.md 2.2).
enum RepairPen {
    static let colorHex = "#FF6347"
    static let uiColor = UIColor(red: 1.0, green: 99.0 / 255.0, blue: 71.0 / 255.0, alpha: 1)
    static let color = Color(uiColor: uiColor)
    static let lineWidth: CGFloat = RepairDrawingRenderer.lineWidth
}

/// One repair from the scribble to Send or Cancel: the frozen Sidekick, the strokes, the words
/// heard and typed. Every time is on one clock, zero at the moment the scribble fired.
@MainActor
@Observable
final class RepairSession: Identifiable {
    let id = UUID().uuidString
    let sidekickId: String
    let snapshot: UIImage
    let viewSize: CGSize
    let startedAt: Date

    private(set) var strokes: [RepairStroke] = []
    private(set) var activeStroke: RepairStroke?
    var typedText = ""
    private(set) var transcript: RepairTranscript = .empty
    private(set) var isListening = false
    private(set) var permissionState: RepairPermissionState
    /// The "Speak While You Draw" screen: up until Continue grants or Not Now dismisses it.
    private(set) var isPermissionScreenShown: Bool

    private let transcriber: RepairTranscribing
    private let uploader: RepairUploader
    private let bundleVersions: SidekickBundleVersions
    /// Set by the host view; dismisses the layer.
    var onFinish: (() -> Void)?

    init(sidekickId: String, snapshot: UIImage, viewSize: CGSize, transcriber: RepairTranscribing, uploader: RepairUploader, bundleVersions: SidekickBundleVersions = .shared, permissionState: RepairPermissionState, startedAt: Date = Date()) {
        self.sidekickId = sidekickId
        self.snapshot = snapshot
        self.viewSize = viewSize
        self.transcriber = transcriber
        self.uploader = uploader
        self.bundleVersions = bundleVersions
        self.permissionState = permissionState
        self.isPermissionScreenShown = permissionState != .granted
        self.startedAt = startedAt
    }

    /// Freezes the web view: a snapshot at its exact size, no chrome, so the Sidekick looks
    /// stopped rather than photographed. Nil if WebKit could not snapshot.
    static func begin(sidekickId: String, webView: WKWebView, transcriber: RepairTranscribing, uploader: RepairUploader) async -> RepairSession? {
        let startedAt = Date()
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        configuration.afterScreenUpdates = false
        guard let snapshot = try? await webView.takeSnapshot(configuration: configuration) else {
            return nil
        }
        return RepairSession(sidekickId: sidekickId, snapshot: snapshot, viewSize: webView.bounds.size, transcriber: transcriber, uploader: uploader, permissionState: RepairPermissions.state(), startedAt: startedAt)
    }

    /// Send lights up once there is a word, spoken or typed; the server rejects an empty transcript.
    var canSend: Bool {
        let combined = RepairReportBuilder.combinedTranscript(spokenText: transcript.text, typedText: typedText)
        return !combined.isEmpty
    }

    var allStrokes: [RepairStroke] {
        if let activeStroke {
            return strokes + [activeStroke]
        }
        return strokes
    }

    // MARK: Permissions

    /// "Continue" on the permission screen: the iOS prompts the first time, Settings after a denial.
    func continuePermissions() async {
        if permissionState == .denied {
            openSettings()
            return
        }
        permissionState = await RepairPermissions.request()
        if permissionState == .granted {
            isPermissionScreenShown = false
            await startListening()
        }
    }

    /// "Not Now": drawing and typing still work; nothing is heard.
    func declinePermissions() {
        isPermissionScreenShown = false
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    // MARK: Listening

    func startListening() async {
        guard !isListening, permissionState == .granted else {
            return
        }
        do {
            try await transcriber.start(sessionStartedAt: startedAt, onUpdate: receiveTranscript)
            isListening = true
        } catch {
            // No on-device model, or the audio engine failed: the user can still draw and type.
            isListening = false
        }
    }

    private func receiveTranscript(_ newTranscript: RepairTranscript) {
        transcript = newTranscript
    }

    private func stopListening() {
        guard isListening else {
            return
        }
        transcriber.stop()
        isListening = false
    }

    // MARK: Drawing

    func elapsedMs(at date: Date = Date()) -> Double {
        (date.timeIntervalSince(startedAt) * 1000).rounded()
    }

    func beginStroke(at point: CGPoint) {
        activeStroke = RepairStroke(points: [[point.x, point.y, elapsedMs()]])
    }

    func extendStroke(to point: CGPoint) {
        guard activeStroke != nil else {
            beginStroke(at: point)
            return
        }
        activeStroke?.points.append([point.x, point.y, elapsedMs()])
    }

    func endStroke() {
        guard let activeStroke else {
            return
        }
        strokes.append(activeStroke)
        self.activeStroke = nil
    }

    func undo() {
        guard !strokes.isEmpty else {
            return
        }
        strokes.removeLast()
    }

    func clear() {
        strokes.removeAll()
        activeStroke = nil
    }

    // MARK: Finish

    func cancel() {
        stopListening()
        onFinish?()
    }

    /// Dismisses at once; the upload runs on its own and is queued if it cannot go now.
    func send() {
        guard canSend else {
            return
        }
        endStroke()
        stopListening()
        let report = buildReport()
        onFinish?()
        guard let report else {
            return
        }
        let uploader = self.uploader
        Task { @MainActor in
            await uploader.send(report)
        }
    }

    private func buildReport() -> RepairReport? {
        let drawing = RepairDrawingRenderer.render(screenshot: snapshot, strokes: strokes, penColor: RepairPen.uiColor)
        let screenScale = UIScreen.main.scale
        return try? RepairReportBuilder.build(
            clientReportId: id,
            sidekickId: sidekickId,
            bundle: bundleVersions.entry(forSidekickId: sidekickId),
            spokenText: transcript.text,
            typedText: typedText,
            words: transcript.words,
            strokes: strokes,
            screenshot: snapshot,
            drawing: drawing,
            viewSize: viewSize,
            screenScale: screenScale,
            sessionStartedAt: startedAt,
            deviceInfo: RepairDeviceInfo.current()
        )
    }
}
