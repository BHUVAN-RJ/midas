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
}

/// The pen follows V1 (founder, 2026-10-23: tomato left Midas's colours): 5 pt Volt, and in light
/// mode over an 8 pt ink line so it shows on white (docs/DESIGN.md 2.2).
enum RepairPen {
    static let colorHex = RepairVolt.hex
    static let uiColor = RepairVolt.color.uiColor
    static let color = Color(uiColor: uiColor)
    static let lineWidth: CGFloat = RepairDrawingRenderer.lineWidth
    static let keylineUIColor = RepairVolt.ink.uiColor
    static let keylineColor = Color(uiColor: keylineUIColor)
    static let keylineWidth: CGFloat = 8

    /// The ink line goes under the Volt in light mode only.
    static func keyline(for style: UIUserInterfaceStyle) -> UIColor? {
        style == .dark ? nil : keylineUIColor
    }
}

/// How a repair layer ended, so the rim and the tag can leave the right way.
enum RepairFinish: Equatable, Sendable {
    case sent
    case cancelled
}

/// One repair from the three-finger swipe to Send or Cancel: the frozen Sidekick, the strokes, the words
/// heard and typed. Every time is on one clock, zero at the moment the swipe fired.
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

    private let transcriber: RepairTranscribing
    private let uploader: RepairUploader
    private let bundleVersions: SidekickBundleVersions
    /// Set by the host view; dismisses the layer.
    var onFinish: (() -> Void)?
    /// Set by the host view; the sent report and the circled screenshot, for the Repair tag.
    var onSent: ((RepairReport, UIImage) -> Void)?
    /// How the layer ended; nil while it is open.
    private(set) var finish: RepairFinish?
    /// Where the fingers lifted, in window points: jess's orb pops there (O4). Nil when the layer
    /// was opened another way; the orb then starts in the pill.
    var liftPoint: CGPoint?
    /// Light or dark when the swipe fired: the pen's ink line is drawn in light mode only.
    var interfaceStyle: UIUserInterfaceStyle = .light

    init(sidekickId: String, snapshot: UIImage, viewSize: CGSize, transcriber: RepairTranscribing, uploader: RepairUploader, bundleVersions: SidekickBundleVersions = .shared, startedAt: Date = Date()) {
        self.sidekickId = sidekickId
        self.snapshot = snapshot
        self.viewSize = viewSize
        self.transcriber = transcriber
        self.uploader = uploader
        self.bundleVersions = bundleVersions
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
        let session = RepairSession(sidekickId: sidekickId, snapshot: snapshot, viewSize: webView.bounds.size, transcriber: transcriber, uploader: uploader, startedAt: startedAt)
        session.interfaceStyle = webView.traitCollection.userInterfaceStyle
        return session
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

    // MARK: Listening

    /// Listens if Midas was given the microphone and speech recognition at launch
    /// (`VoicePermissions`, founder 2026-10-15). The layer never asks.
    func startListening() async {
        guard !isListening else {
            return
        }
        do {
            try await transcriber.start(sessionStartedAt: startedAt, onUpdate: receiveTranscript)
            isListening = true
        } catch {
            // Permission declined, no on-device model, or the audio engine failed: the user can
            // still draw and type.
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
        finish = .cancelled
        onFinish?()
    }

    /// True while a finger is drawing: the rim steps back.
    var isDrawing: Bool {
        activeStroke != nil
    }

    /// Dismisses at once; the upload runs on its own and is queued if it cannot go now.
    func send() {
        guard canSend else {
            return
        }
        endStroke()
        stopListening()
        let drawing = renderDrawing()
        let report = buildReport(drawing: drawing)
        finish = .sent
        onFinish?()
        guard let report else {
            return
        }
        onSent?(report, drawing)
        let uploader = self.uploader
        Task { @MainActor in
            await uploader.send(report)
        }
    }

    /// The screenshot with the strokes, as the user saw them.
    func renderDrawing() -> UIImage {
        RepairDrawingRenderer.render(screenshot: snapshot, strokes: strokes, penColor: RepairPen.uiColor, keylineColor: RepairPen.keyline(for: interfaceStyle))
    }

    private func buildReport(drawing: UIImage) -> RepairReport? {
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
