import SwiftUI
import UIKit
import XCTest
@testable import Midas

/// Stands in for a Sidekick's web view exactly as `SidekickScreen` lays it out, with the repair
/// layer over it.
private struct HostedSidekick: View {
    let session: RepairSession?
    let onLayout: (RepairLayerPart, CGRect) -> Void
    let onWebViewFrame: (CGRect) -> Void

    var body: some View {
        Color.gray
            .onGeometryChange(for: CGRect.self, of: Self.globalFrame, action: onWebViewFrame)
            .repairLayer(session, onLayout: onLayout)
    }

    nonisolated private static func globalFrame(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .global)
    }
}

/// Where the repair layer's parts landed, in window coordinates.
private struct RepairLayerFrames {
    var snapshot: CGRect = .zero
    var cancel: CGRect = .zero
    var bottomBar: CGRect = .zero
    var send: CGRect = .zero
}

/// Keeps the latest frames the hosted view reported.
@MainActor
private final class LayoutRecorder {
    var frames = RepairLayerFrames()
    var webViewFrame = CGRect.zero
    var keyboardFrame = CGRect.zero

    func receiveFrame(_ part: RepairLayerPart, _ frame: CGRect) {
        switch part {
        case .snapshot:
            frames.snapshot = frame
        case .cancel:
            frames.cancel = frame
        case .bottomBar:
            frames.bottomBar = frame
        case .send:
            frames.send = frame
        }
    }

    func receiveWebViewFrame(_ frame: CGRect) {
        webViewFrame = frame
    }
}

/// Waits for the software keyboard and keeps where it landed.
private final class KeyboardWatcher: NSObject {
    let shown = XCTestExpectation(description: "the keyboard rose")
    private(set) var keyboardFrame = CGRect.zero

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidShow(_:)), name: UIResponder.keyboardDidShowNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func keyboardDidShow(_ notification: Notification) {
        let frameValue = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue
        keyboardFrame = frameValue?.cgRectValue ?? .zero
        shown.fulfill()
    }
}

/// Reads pixels of a rendered window, in points.
private struct RenderedPixels {
    private let data: [UInt8]
    private let width: Int
    private let height: Int
    private let scale: CGFloat

    init(image: UIImage) {
        let cgImage = image.cgImage!
        width = cgImage.width
        height = cgImage.height
        scale = image.scale
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        bytes.withUnsafeMutableBytes(Self.drawInto(cgImage: cgImage, width: width, height: height, colorSpace: colorSpace, bitmapInfo: bitmapInfo))
        data = bytes
    }

    private static func drawInto(cgImage: CGImage, width: Int, height: Int, colorSpace: CGColorSpace, bitmapInfo: UInt32) -> (UnsafeMutableRawBufferPointer) -> Void {
        { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo)
            context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// Brightness 0...1 of the pixel at a point.
    func brightness(at point: CGPoint) -> Double {
        let pixelX = min(max(Int(point.x * scale), 0), width - 1)
        let pixelY = min(max(Int(point.y * scale), 0), height - 1)
        let offset = (pixelY * width + pixelX) * 4
        let red = Double(data[offset])
        let green = Double(data[offset + 1])
        let blue = Double(data[offset + 2])
        return (red + green + blue) / (3 * 255)
    }
}

/// Bugs 2 and 3 of the first phone test (2026-10-14): the frozen Sidekick slid under the status
/// bar, Cancel went off screen, the text box hid under the keyboard, white showed in dark mode.
@MainActor
final class RepairLayerLayoutTests: XCTestCase {
    /// The frozen Sidekick in the tests: one dark grey, so anything else shows.
    private static let snapshotBrightness = 0.2

    private var window: UIWindow?
    private var outboxURL: URL!

    override func setUp() {
        super.setUp()
        outboxURL = FileManager.default.temporaryDirectory.appending(path: "repair-layout-\(UUID().uuidString)")
    }

    override func tearDown() {
        window?.isHidden = true
        window = nil
        try? FileManager.default.removeItem(at: outboxURL)
        super.tearDown()
    }

    // MARK: Hosting

    private func makeWindow(style: UIUserInterfaceStyle) throws -> UIWindow {
        let scenes = UIApplication.shared.connectedScenes.compactMap(Self.windowScene)
        let scene = try XCTUnwrap(scenes.first, "the test host has no window scene")
        let newWindow = UIWindow(windowScene: scene)
        newWindow.frame = scene.coordinateSpace.bounds
        newWindow.overrideUserInterfaceStyle = style
        window = newWindow
        return newWindow
    }

    private static func windowScene(_ scene: UIScene) -> UIWindowScene? {
        scene as? UIWindowScene
    }

    private func host(_ session: RepairSession?, in hostWindow: UIWindow, recorder: LayoutRecorder) async -> UIHostingController<HostedSidekick> {
        let rootView = HostedSidekick(session: session, onLayout: recorder.receiveFrame, onWebViewFrame: recorder.receiveWebViewFrame)
        let controller = UIHostingController(rootView: rootView)
        hostWindow.rootViewController = controller
        hostWindow.makeKeyAndVisible()
        await settle(hostWindow)
        return controller
    }

    /// Raises the real software keyboard by focusing the text box, as a tap on it does, and
    /// returns where the keyboard landed.
    private func raiseKeyboard(in hostWindow: UIWindow) async throws -> CGRect {
        let watcher = KeyboardWatcher()
        let textInput = try XCTUnwrap(Self.firstTextInput(in: hostWindow), "the text box was not found")
        XCTAssertTrue(textInput.becomeFirstResponder(), "the text box would not take focus")
        await fulfillment(of: [watcher.shown], timeout: 5)
        await settle(hostWindow)
        return watcher.keyboardFrame
    }

    private static func firstTextInput(in view: UIView) -> UIView? {
        if view is UITextView || view is UITextField {
            return view
        }
        for subview in view.subviews {
            if let found = firstTextInput(in: subview) {
                return found
            }
        }
        return nil
    }

    private func settle(_ hostWindow: UIWindow) async {
        hostWindow.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(300))
        hostWindow.layoutIfNeeded()
    }

    private static func snapshot(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image(actions: fillSnapshot(size: size))
    }

    private static func fillSnapshot(size: CGSize) -> (UIGraphicsImageRendererContext) -> Void {
        { context in
            UIColor(white: snapshotBrightness, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeSession(viewSize: CGSize) -> RepairSession {
        let uploader = RepairUploader(api: NeverUploadAPI(), outbox: RepairOutbox(directoryURL: outboxURL))
        return RepairSession(sidekickId: "reminders", snapshot: Self.snapshot(size: viewSize), viewSize: viewSize, transcriber: SilentTranscriber(), uploader: uploader)
    }

    /// Lays the stand-in web view out alone first, as the app does before the circle, then freezes
    /// it at that size.
    private func hostRepair(style: UIUserInterfaceStyle, raisesKeyboard: Bool, typedText: String = "") async throws -> (window: UIWindow, recorder: LayoutRecorder) {
        let hostWindow = try makeWindow(style: style)
        let recorder = LayoutRecorder()
        _ = await host(nil, in: hostWindow, recorder: recorder)
        let webViewFrame = recorder.webViewFrame
        XCTAssertGreaterThan(webViewFrame.height, 0)
        let session = makeSession(viewSize: webViewFrame.size)
        session.typedText = typedText
        _ = await host(session, in: hostWindow, recorder: recorder)
        if raisesKeyboard {
            recorder.keyboardFrame = try await raiseKeyboard(in: hostWindow)
        }
        XCTAssertEqual(recorder.webViewFrame, webViewFrame, "the web view itself must not move")
        return (hostWindow, recorder)
    }

    private func render(_ hostWindow: UIWindow) -> RenderedPixels {
        let renderer = UIGraphicsImageRenderer(bounds: hostWindow.bounds)
        let image = renderer.image(actions: drawWindow(hostWindow))
        return RenderedPixels(image: image)
    }

    private func drawWindow(_ hostWindow: UIWindow) -> (UIGraphicsImageRendererContext) -> Void {
        { _ in
            hostWindow.drawHierarchy(in: hostWindow.bounds, afterScreenUpdates: true)
        }
    }

    // MARK: Frames

    private func assertFramesHold(raisesKeyboard: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let (hostWindow, recorder) = try await hostRepair(style: .light, raisesKeyboard: raisesKeyboard)
        let webViewFrame = recorder.webViewFrame
        let frames = recorder.frames
        XCTAssertEqual(frames.snapshot, webViewFrame, "the frozen Sidekick must sit exactly on the web view", file: file, line: line)

        let safeTop = hostWindow.safeAreaInsets.top
        XCTAssertGreaterThanOrEqual(frames.cancel.minY, safeTop, "Cancel must stay below the status bar", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frames.cancel.minX, -0.5, "Cancel must stay on screen", file: file, line: line)
        XCTAssertGreaterThan(frames.cancel.height, 0, "Cancel was not laid out", file: file, line: line)

        var lowestControl = hostWindow.bounds.height - hostWindow.safeAreaInsets.bottom
        if raisesKeyboard {
            XCTAssertGreaterThan(recorder.keyboardFrame.height, 100, "the keyboard did not rise", file: file, line: line)
            lowestControl = min(lowestControl, recorder.keyboardFrame.minY)
        }
        XCTAssertGreaterThan(frames.bottomBar.height, 0, "the bottom bar was not laid out", file: file, line: line)
        XCTAssertLessThanOrEqual(frames.bottomBar.maxY, lowestControl + 0.5, "the bottom bar must sit above the keyboard and the home indicator", file: file, line: line)
        XCTAssertGreaterThan(frames.bottomBar.minY, frames.cancel.maxY, "the bar must not run into Cancel", file: file, line: line)
    }

    func testFrozenSidekickSitsExactlyOnTheWebViewAndControlsStayInside() async throws {
        try await assertFramesHold(raisesKeyboard: false)
    }

    func testKeyboardRaisesTheBarAndNeverMovesTheFrozenSidekickOrCancel() async throws {
        try await assertFramesHold(raisesKeyboard: true)
    }

    // MARK: Dark mode, no white band

    /// Everywhere outside Cancel and the bottom bar, the screen shows the frozen Sidekick and
    /// nothing else: no band of another colour above, below or beside it.
    private func assertOnlyTheSnapshotShows(style: UIUserInterfaceStyle, raisesKeyboard: Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        let (hostWindow, recorder) = try await hostRepair(style: style, raisesKeyboard: raisesKeyboard)
        let pixels = render(hostWindow)
        let frames = recorder.frames
        let cancelArea = frames.cancel.insetBy(dx: -6, dy: -6)
        let webViewFrame = recorder.webViewFrame
        var mismatches: [CGPoint] = []
        var y = webViewFrame.minY + 1
        while y < frames.bottomBar.minY - 1 {
            var x: CGFloat = 1
            while x < webViewFrame.maxX - 1 {
                let point = CGPoint(x: x, y: y)
                if !cancelArea.contains(point), abs(pixels.brightness(at: point) - Self.snapshotBrightness) > 0.04 {
                    mismatches.append(point)
                }
                x += 8
            }
            y += 8
        }
        XCTAssertEqual(mismatches.count, 0, "not the frozen Sidekick at \(mismatches.prefix(5))", file: file, line: line)
    }

    func testDarkModeShowsOnlyTheFrozenSidekickAroundTheControls() async throws {
        try await assertOnlyTheSnapshotShows(style: .dark, raisesKeyboard: false)
    }

    func testDarkModeWithTheKeyboardUpShowsNoBand() async throws {
        try await assertOnlyTheSnapshotShows(style: .dark, raisesKeyboard: true)
    }

    func testLightModeShowsOnlyTheFrozenSidekickAroundTheControls() async throws {
        try await assertOnlyTheSnapshotShows(style: .light, raisesKeyboard: false)
    }

    /// Send is filled with the text colour; its word must still show, in both modes.
    private func assertSendIsReadable(style: UIUserInterfaceStyle, file: StaticString = #filePath, line: UInt = #line) async throws {
        let (hostWindow, recorder) = try await hostRepair(style: style, raisesKeyboard: false, typedText: "move it")
        let pixels = render(hostWindow)
        let send = recorder.frames.send
        XCTAssertGreaterThan(send.width, 0, "Send was not laid out", file: file, line: line)
        var brightest = 0.0
        var darkest = 1.0
        var x = send.minX + 4
        while x < send.maxX - 4 {
            let value = pixels.brightness(at: CGPoint(x: x, y: send.midY))
            brightest = max(brightest, value)
            darkest = min(darkest, value)
            x += 0.5
        }
        XCTAssertGreaterThan(brightest - darkest, 0.5, "the word Send does not stand out from its button", file: file, line: line)
    }

    func testSendIsReadableInDarkMode() async throws {
        try await assertSendIsReadable(style: .dark)
    }

    func testSendIsReadableInLightMode() async throws {
        try await assertSendIsReadable(style: .light)
    }

    func testTheRepairLayerHardCodesNoLightModeColour() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory.deletingLastPathComponent().appending(path: "Midas").appending(path: "RepairCanvasView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        for colour in ["Color.white", "Color.black", ".white)", ".black)", "UIColor.white", "UIColor.black"] {
            XCTAssertFalse(source.contains(colour), "the repair layer assumes a mode with \(colour)")
        }
    }
}

/// Never hears anything; the layer still opens.
@MainActor
private final class SilentTranscriber: RepairTranscribing {
    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        throw RepairSpeechError.notAuthorized
    }

    func stop() {}
}

/// The layout tests never send.
private struct NeverUploadAPI: RepairUploadAPI {
    func upload(_ report: RepairReport) async throws -> RepairUploadOutcome {
        .retryLater
    }
}
