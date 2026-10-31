import SwiftUI
import UIKit
import XCTest
@testable import Midas

/// Founder, on the phone (Midas Test build 12, 2026-10-23): "the text that is typed sort of appears
/// somewhere else", with screenshots: the words jess heard sat at the bottom of a pill grown to two
/// lines, under the orb's line, with an empty line above them. The spoken words had a frame of
/// their own that took three lines' height and pinned the text to its bottom, and anything typed
/// went into a second box on a line of its own. B3 (docs/mockups/repair-feedback-2026-10-23.html)
/// has one text area on the orb's line: the typed words carry on straight after the spoken words,
/// inside the pill, with the pill above the keyboard.

/// Hosts the repair layer the way `SidekickScreen` does, and reports the pill's frame.
private struct PillTypingHost: View {
    let session: RepairSession
    let onLayout: (RepairLayerPart, CGRect) -> Void
    let onPillLayout: (CGRect) -> Void

    var body: some View {
        Color.gray
            .repairLayer(session, onLayout: onLayout, onPillLayout: onPillLayout)
    }
}

/// Keeps the latest pill frame.
@MainActor
private final class PillFrameRecorder {
    var pill = CGRect.zero
    var send = CGRect.zero

    func receive(_ frame: CGRect) {
        pill = frame
    }

    func receivePart(_ part: RepairLayerPart, _ frame: CGRect) {
        if part == .send {
            send = frame
        }
    }
}

/// Keeps listening, and hands the test the words to say when it wants.
@MainActor
private final class PillTypingTranscriber: RepairTranscribing {
    private var hear: (@MainActor (RepairTranscript) -> Void)?

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        hear = onUpdate
    }

    func stop() {}

    func say(_ text: String) {
        hear?(RepairTranscript(text: text, words: []))
    }
}

/// Never hears anything (no microphone); the user types.
@MainActor
private final class PillTypingDeafTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        throw RepairSpeechError.notAuthorized
    }

    func stop() {}
}

private struct PillTypingNoUpload: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .retryLater
    }
}

/// Waits for the software keyboard and keeps where it landed.
private final class PillTypingKeyboardWatcher: NSObject {
    private(set) var keyboardFrame = CGRect.zero

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardDidChangeFrameNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        keyboardFrame = frameValue?.cgRectValue ?? .zero
    }
}

@MainActor
final class RepairPillTypingTests: XCTestCase {
    private static let spoken = "the last row is cut off"
    private static let typed = "on the right"

    private var window: UIWindow?
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-pill-typing-\(UUID().uuidString)")
    }

    override func tearDown() {
        window?.endEditing(true)
        window?.isHidden = true
        window = nil
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    // MARK: Hosting

    private func host(transcriber: RepairTranscribing, recorder: PillFrameRecorder) async throws -> (UIWindow, RepairSession) {
        let scenes = UIApplication.shared.connectedScenes.compactMap(Self.windowScene)
        let scene = try XCTUnwrap(scenes.first, "the test host has no window scene")
        let hostWindow = UIWindow(windowScene: scene)
        hostWindow.frame = scene.coordinateSpace.bounds
        hostWindow.overrideUserInterfaceStyle = .light
        window = hostWindow
        let size = hostWindow.bounds.size
        let uploader = RepairUploader(api: PillTypingNoUpload(), outbox: RepairOutbox(directoryURL: outboxURL))
        let session = RepairSession(sidekickId: "reminders", snapshot: Self.solidImage(size: size), viewSize: size, transcriber: transcriber, uploader: uploader)
        let rootView = PillTypingHost(session: session, onLayout: recorder.receivePart, onPillLayout: recorder.receive)
        hostWindow.rootViewController = UIHostingController(rootView: rootView)
        hostWindow.makeKeyAndVisible()
        await settle(hostWindow)
        return (hostWindow, session)
    }

    private static func windowScene(_ scene: UIScene) -> UIWindowScene? {
        scene as? UIWindowScene
    }

    private static func solidImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image(actions: fillGrey(size: size))
    }

    private static func fillGrey(size: CGSize) -> (UIGraphicsImageRendererContext) -> Void {
        { context in
            UIColor(white: 0.2, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func settle(_ hostWindow: UIWindow) async {
        hostWindow.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(500))
        hostWindow.layoutIfNeeded()
    }

    private static func textInputs(in view: UIView) -> [UITextView] {
        var found: [UITextView] = []
        if let textView = view as? UITextView {
            found.append(textView)
        }
        for subview in view.subviews {
            found += textInputs(in: subview)
        }
        return found
    }

    private func onlyTextInput(in hostWindow: UIWindow) throws -> UITextView {
        let inputs = Self.textInputs(in: hostWindow)
        XCTAssertEqual(inputs.count, 1, "the pill has one text area")
        return try XCTUnwrap(inputs.first, "the pill has no text area")
    }

    /// Focuses the text area, as a tap on the words does, and waits for the keyboard.
    private func startTyping(in hostWindow: UIWindow) async throws -> (UITextView, CGRect) {
        let watcher = PillTypingKeyboardWatcher()
        let textView = try onlyTextInput(in: hostWindow)
        XCTAssertTrue(textView.becomeFirstResponder(), "the text area would not take focus")
        try? await Task.sleep(for: .seconds(1))
        await settle(hostWindow)
        return (textView, watcher.keyboardFrame)
    }

    /// The width one line of words gets in the text area, on this phone.
    private static func lineWidth(of textView: UITextView) -> CGFloat {
        let insets = textView.textContainerInset.left + textView.textContainerInset.right
        return textView.bounds.width - insets - 2 * textView.textContainer.lineFragmentPadding
    }

    /// The width of words in the pill's font, on one line.
    private static func textWidth(of words: String) -> CGFloat {
        let font = UIFont.systemFont(ofSize: RepairPillSpec.fontSize)
        return (words as NSString).size(withAttributes: [.font: font]).width
    }

    /// Where a piece of the text area's text is drawn, in window points.
    private static func drawnFrame(of piece: String, in textView: UITextView) throws -> CGRect {
        let text = textView.text as NSString? ?? ""
        let range = text.range(of: piece, options: .backwards)
        XCTAssertNotEqual(range.location, NSNotFound, "\"\(piece)\" is not in the text area (it holds \"\(text)\")")
        let start = try XCTUnwrap(textView.position(from: textView.beginningOfDocument, offset: range.location))
        let end = try XCTUnwrap(textView.position(from: start, offset: range.length))
        let textRange = try XCTUnwrap(textView.textRange(from: start, to: end))
        let rects = textView.selectionRects(for: textRange).map(Self.selectionRect)
        let union = rects.reduce(CGRect.null, Self.union)
        return textView.convert(union, to: nil)
    }

    private static func selectionRect(_ selection: UITextSelectionRect) -> CGRect {
        selection.rect
    }

    private static func union(_ first: CGRect, _ second: CGRect) -> CGRect {
        first.union(second)
    }

    private func assertInside(_ inner: CGRect, _ outer: CGRect, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThan(inner.height, 0, "\(what) has no height", file: file, line: line)
        XCTAssertGreaterThanOrEqual(inner.minX, outer.minX - 0.5, "\(what) starts left of the pill", file: file, line: line)
        XCTAssertLessThanOrEqual(inner.maxX, outer.maxX + 0.5, "\(what) runs past the pill's right edge", file: file, line: line)
        XCTAssertGreaterThanOrEqual(inner.minY, outer.minY - 0.5, "\(what) shows above the pill", file: file, line: line)
        XCTAssertLessThanOrEqual(inner.maxY, outer.maxY + 0.5, "\(what) shows below the pill", file: file, line: line)
    }

    /// The window drawn to pixels, in points: brightness 0...1 at a point.
    private static func brightnessReader(of hostWindow: UIWindow) -> (CGPoint) -> Double {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(bounds: hostWindow.bounds, format: format)
        let image = renderer.image(actions: drawWindow(hostWindow))
        let cgImage = image.cgImage!
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        bytes.withUnsafeMutableBytes(drawInto(cgImage: cgImage, width: width, height: height, colorSpace: colorSpace, bitmapInfo: bitmapInfo))
        let pixels = bytes
        func brightness(at point: CGPoint) -> Double {
            let pixelX = min(max(Int(point.x), 0), width - 1)
            let pixelY = min(max(Int(point.y), 0), height - 1)
            let offset = (pixelY * width + pixelX) * 4
            let total = Double(pixels[offset]) + Double(pixels[offset + 1]) + Double(pixels[offset + 2])
            return total / (3 * 255)
        }
        return brightness
    }

    private static func drawWindow(_ hostWindow: UIWindow) -> (UIGraphicsImageRendererContext) -> Void {
        { _ in
            hostWindow.drawHierarchy(in: hostWindow.bounds, afterScreenUpdates: true)
        }
    }

    private static func drawInto(cgImage: CGImage, width: Int, height: Int, colorSpace: CGColorSpace, bitmapInfo: UInt32) -> (UnsafeMutableRawBufferPointer) -> Void {
        { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo)
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The rows of the pill, between the orb and Send, where text is drawn (light mode: dark
    /// pixels on the white pill).
    private static func inkRows(in pill: CGRect, before send: CGRect, brightness: (CGPoint) -> Double) -> (minY: CGFloat, maxY: CGFloat)? {
        var minY = CGFloat.infinity
        var maxY = -CGFloat.infinity
        var y = pill.minY + 3
        while y < pill.maxY - 3 {
            var x = pill.minX + 60
            while x < send.minX - 4 {
                if brightness(CGPoint(x: x, y: y)) < 0.6 {
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
                x += 1
            }
            y += 1
        }
        guard minY <= maxY else {
            return nil
        }
        return (minY, maxY)
    }

    // MARK: Spoken only

    /// The founder's screenshots: "So the voice to text" sat under the orb's line in a pill two
    /// lines tall.
    func testSpokenWordsSitOnTheOrbsLineInAOneLinePill() async throws {
        let transcriber = PillTypingTranscriber()
        let recorder = PillFrameRecorder()
        let (hostWindow, _) = try await host(transcriber: transcriber, recorder: recorder)
        transcriber.say("So the voice to text")
        await settle(hostWindow)
        let pill = recorder.pill
        let send = recorder.send
        XCTAssertGreaterThan(send.height, 0, "Send was not laid out")
        XCTAssertEqual(pill.height, RepairPillSpec.height, accuracy: 1, "one line of words keeps the pill one line tall")
        let brightness = Self.brightnessReader(of: hostWindow)
        let rows = try XCTUnwrap(Self.inkRows(in: pill, before: send, brightness: brightness), "no words drawn in the pill")
        let wordsMiddle = (rows.minY + rows.maxY) / 2
        XCTAssertEqual(wordsMiddle, send.midY, accuracy: 3, "the spoken words must sit on the orb's and Send's line")
        // The line itself (not only its ink) is centred on the line, one line tall
        let textView = try onlyTextInput(in: hostWindow)
        XCTAssertEqual(textView.text, "So the voice to text", "the spoken words are in the pill's text area")
        let line = try Self.drawnFrame(of: "So the voice to text", in: textView)
        XCTAssertEqual(line.midY, send.midY, accuracy: 1, "the words' line is off the orb's centre line")
        let lineHeight = UIFont.systemFont(ofSize: RepairPillSpec.fontSize).lineHeight
        XCTAssertEqual(textView.bounds.height, lineHeight, accuracy: 1.5, "one line of words takes one line")
    }

    /// Long words grow the pill a line at a time, up to three, and the newest words stay in view.
    func testLongWordsGrowToThreeLinesAndKeepTheNewestInView() async throws {
        let transcriber = PillTypingTranscriber()
        let recorder = PillFrameRecorder()
        let (hostWindow, _) = try await host(transcriber: transcriber, recorder: recorder)
        let lineHeight = UIFont.systemFont(ofSize: RepairPillSpec.fontSize).lineHeight
        // Two lines on any iPhone width (about 350 pt of words; the text area is 229 pt on a
        // 375 pt phone, 247 pt on a 393 pt one, 256 pt on a 402 pt one)
        let twoLineWords = "the last row is cut off on the right and the date"
        transcriber.say(twoLineWords)
        await settle(hostWindow)
        let twoLines = try onlyTextInput(in: hostWindow)
        let lineWidth = Self.lineWidth(of: twoLines)
        let wordsWidth = Self.textWidth(of: twoLineWords)
        XCTAssertGreaterThan(wordsWidth, lineWidth, "the sentence must be too long for one line on this phone")
        XCTAssertLessThan(wordsWidth, lineWidth * 2 - 40, "the sentence must fit two lines on this phone")
        XCTAssertEqual(twoLines.bounds.height, lineHeight * 2, accuracy: 2, "two lines of words take two lines")
        transcriber.say("the last row is cut off on the right and the date under it is too close to the next one so it reads as one long line and the button overlaps it as well")
        await settle(hostWindow)
        let textView = try onlyTextInput(in: hostWindow)
        XCTAssertEqual(textView.bounds.height, lineHeight * 3, accuracy: 2, "the words stop growing at three lines")
        let newest = try Self.drawnFrame(of: "as well", in: textView)
        let visible = textView.convert(textView.bounds, to: nil)
        XCTAssertTrue(visible.insetBy(dx: -1, dy: -1).contains(newest), "the newest words must stay in view")
        assertInside(visible, recorder.pill, "the text area")
    }

    // MARK: Spoken, then typed

    func testTypedWordsCarryOnAfterTheSpokenWordsInsideThePill() async throws {
        // Short enough for one line on any iPhone width (the text area is 247 pt on a 393 pt
        // phone); checked below against this phone's text area
        let spoken = "the last row"
        let typed = "is cut off"
        let transcriber = PillTypingTranscriber()
        let recorder = PillFrameRecorder()
        let (hostWindow, session) = try await host(transcriber: transcriber, recorder: recorder)
        transcriber.say(spoken)
        await settle(hostWindow)

        let (textView, keyboard) = try await startTyping(in: hostWindow)
        textView.insertText(typed)
        await settle(hostWindow)

        // One text area: the spoken words, a space, then what was typed
        XCTAssertEqual(textView.text, spoken + " " + typed, "the typed words must carry on after the spoken words in the same text area")
        XCTAssertEqual(session.typedText, typed, "only the typed words are the typed text")
        XCTAssertEqual(session.transcript.text, spoken)
        XCTAssertLessThan(Self.textWidth(of: spoken + " " + typed), Self.lineWidth(of: textView), "the words must fit one line on this phone")

        let pill = recorder.pill
        XCTAssertGreaterThan(pill.height, 0, "the pill was not laid out")
        let field = textView.convert(textView.bounds, to: nil)
        assertInside(field, pill, "the text area")
        let typedFrame = try Self.drawnFrame(of: typed, in: textView)
        assertInside(typedFrame, pill, "the typed words")
        let spokenFrame = try Self.drawnFrame(of: spoken, in: textView)
        assertInside(spokenFrame, pill, "the spoken words")
        XCTAssertEqual(typedFrame.minY, spokenFrame.minY, accuracy: 1, "short typed words go on the spoken words' line, not a line of their own")
        XCTAssertGreaterThan(typedFrame.minX, spokenFrame.maxX - 1, "the typed words follow the spoken words")

        if keyboard.height > 0 {
            XCTAssertLessThanOrEqual(pill.maxY, keyboard.minY + 0.5, "the pill must sit above the keyboard")
        }
    }

    func testDeletingStopsAtTheSpokenWords() async throws {
        let transcriber = PillTypingTranscriber()
        let recorder = PillFrameRecorder()
        let (hostWindow, session) = try await host(transcriber: transcriber, recorder: recorder)
        transcriber.say(Self.spoken)
        await settle(hostWindow)
        let (textView, _) = try await startTyping(in: hostWindow)
        textView.insertText("ok")
        for _ in 0..<40 {
            textView.deleteBackward()
        }
        await settle(hostWindow)
        XCTAssertEqual(session.typedText, "")
        XCTAssertEqual(session.transcript.text, Self.spoken, "backspace never eats what jess heard")
        XCTAssertTrue((textView.text ?? "").hasPrefix(Self.spoken), "the spoken words stay in the text area")
    }

    func testWordsHeardWhileTypingGoBeforeTheTypedWords() async throws {
        let transcriber = PillTypingTranscriber()
        let recorder = PillFrameRecorder()
        let (hostWindow, session) = try await host(transcriber: transcriber, recorder: recorder)
        transcriber.say("the last row")
        await settle(hostWindow)
        let (textView, _) = try await startTyping(in: hostWindow)
        textView.insertText(Self.typed)
        await settle(hostWindow)
        transcriber.say(Self.spoken)
        await settle(hostWindow)
        XCTAssertEqual(textView.text, Self.spoken + " " + Self.typed)
        XCTAssertEqual(session.typedText, Self.typed)
        textView.insertText("!")
        await settle(hostWindow)
        XCTAssertEqual(session.typedText, Self.typed + "!", "the caret stays at the end of the typed words")
    }

    // MARK: Typed only

    func testTypingWithNoSpokenWordsShowsInsideThePill() async throws {
        let recorder = PillFrameRecorder()
        let (hostWindow, session) = try await host(transcriber: PillTypingDeafTranscriber(), recorder: recorder)
        let (textView, keyboard) = try await startTyping(in: hostWindow)
        textView.insertText(Self.typed)
        await settle(hostWindow)
        XCTAssertEqual(textView.text, Self.typed)
        XCTAssertEqual(session.typedText, Self.typed)
        let pill = recorder.pill
        XCTAssertEqual(pill.height, RepairPillSpec.height, accuracy: 1, "one typed line keeps the pill one line tall")
        let typedLine = try Self.drawnFrame(of: Self.typed, in: textView)
        XCTAssertEqual(typedLine.midY, recorder.send.midY, accuracy: 1, "typed words sit on the orb's line, where spoken words do")
        assertInside(textView.convert(textView.bounds, to: nil), pill, "the text area")
        assertInside(try Self.drawnFrame(of: Self.typed, in: textView), pill, "the typed words")
        if keyboard.height > 0 {
            XCTAssertLessThanOrEqual(pill.maxY, keyboard.minY + 0.5, "the pill must sit above the keyboard")
        }
    }
}
