import SwiftUI
import UIKit
import XCTest
@testable import Midas

// jess's camera (founder, 2026-11-02, build 23; docs/mockups/jess-camera-2026-11-02.html): a camera
// button right of the orb; Use Photo sends the photo (shrunk to 1024 px, JPEG) with the words heard
// so far; Cancel sends the words alone or listens again; the request keeps its photo on disk so a
// request finished later still sends it; the Workdesk card shows the photo ("Photo" with no words);
// deleting the card deletes the photo.

private let cameraSaidTime = Date(timeIntervalSince1970: 1_793_200_000)

private func cameraShellRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
}

@MainActor
private func waitForCamera(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<300 {
        if condition() {
            return
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

private func solidImage(width: CGFloat, height: CGFloat) -> UIImage {
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
    func fill(_ context: UIGraphicsImageRendererContext) {
        UIColor.orange.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return renderer.image(actions: fill)
}

// MARK: - The photo as sent

final class JessCameraPhotoTests: XCTestCase {
    func testAPhotoIsShrunkToTenTwentyFourOnItsLongestSide() {
        XCTAssertEqual(JessCameraSpec.shrunkSize(CGSize(width: 4032, height: 3024)), CGSize(width: 1024, height: 768))
        XCTAssertEqual(JessCameraSpec.shrunkSize(CGSize(width: 3024, height: 4032)), CGSize(width: 768, height: 1024))
        XCTAssertEqual(JessCameraSpec.shrunkSize(CGSize(width: 800, height: 600)), CGSize(width: 800, height: 600), "never enlarged")
    }

    func testTheJPEGSentIsSmallAndShrunk() throws {
        let jpeg = try XCTUnwrap(JessCameraSpec.jpeg(from: solidImage(width: 3000, height: 2000)))
        let decoded = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(max(decoded.size.width * decoded.scale, decoded.size.height * decoded.scale), 1024)
        XCTAssertLessThan(jpeg.count, 1_500_000, "within the server's limit")
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8], "a JPEG")
    }

    func testTheRequestCarriesThePhotoOnlyWhenThereIsOne() throws {
        let app = VoiceParseApp(version: "0.1.0", build: "23", ios: "26.1", device: "iPhone17,1")
        let plain = JessRouteRequest(transcript: "add milk", now: "2026-11-02T10:00:00", timeZone: "America/Los_Angeles", locale: "en-US", sidekicks: [], app: app, listenMs: 900)
        let plainJSON = try XCTUnwrap(String(data: JSONEncoder().encode(plain), encoding: .utf8))
        XCTAssertFalse(plainJSON.contains("\"photo\""))
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
        var withPhoto = plain
        withPhoto.photo = JessPhotoPayload(jpeg: jpeg)
        let photoJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(withPhoto)) as? [String: Any])
        let photo = try XCTUnwrap(photoJSON["photo"] as? [String: String])
        XCTAssertEqual(photo["mediaType"], "image/jpeg")
        XCTAssertEqual(photo["data"], jpeg.base64EncodedString())
        XCTAssertEqual(RemoteJessRouter.timeout(for: withPhoto), RemoteJessRouter.photoRequestTimeout)
        XCTAssertEqual(RemoteJessRouter.timeout(for: plain), RemoteJessRouter.requestTimeout)
        XCTAssertGreaterThan(RemoteJessRouter.photoRequestTimeout, 30, "two 15 s model calls on the server")
        XCTAssertNil(JessRouter.photoPayload(nil))
    }
}

// MARK: - The jess screen

@MainActor
private final class CameraTranscriber: VoiceTranscribing {
    var onUpdate: (@MainActor (VoiceTranscript) -> Void)?
    var onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        startCount += 1
        self.onUpdate = onUpdate
        self.onEnd = onEnd
    }

    func stop() {
        stopCount += 1
        let endHandler = onEnd
        onEnd = nil
        onUpdate = nil
        endHandler?(.stopped)
    }

    func say(_ text: String) {
        onUpdate?(VoiceTranscript(text: text, words: []))
    }
}

private struct CameraUnusedParser: VoiceReminderParsing {
    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        .unreachable
    }
}

@MainActor
private final class CameraFlowHarness {
    let transcriber = CameraTranscriber()
    var routed: [String] = []
    var photosRouted: [(String, Data)] = []
    private(set) var flow: VoiceReminderFlow!

    init(withCamera: Bool = true) {
        flow = VoiceReminderFlow(dependencies: dependencies(withCamera: withCamera))
    }

    private func dependencies(withCamera: Bool) -> VoiceReminderDependencies {
        func isSignedIn() -> Bool {
            true
        }
        func lists() -> [VoiceReminderList] {
            []
        }
        func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing {
            transcriber
        }
        func save(_ reminder: VoiceResolvedReminder) throws {}
        func now() -> Date {
            cameraSaidTime
        }
        func timeZone() -> TimeZone {
            TimeZone(identifier: "America/Los_Angeles")!
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "23", ios: "26.1", device: "iPhone17,1")
        }
        func route(transcript: String, listenMs: Int) async {
            routed.append(transcript)
        }
        func routePhoto(transcript: String, listenMs: Int, photo: Data) async {
            photosRouted.append((transcript, photo))
        }
        var dependencies = VoiceReminderDependencies(isSignedIn: isSignedIn, lists: lists, makeTranscriber: makeTranscriber, api: CameraUnusedParser(), save: save, now: now, timeZone: timeZone, app: app)
        dependencies.route = route
        if withCamera {
            dependencies.routePhoto = routePhoto
        }
        return dependencies
    }
}

@MainActor
final class JessCameraFlowTests: XCTestCase {
    func testThePhotoGoesWithTheWordsHeardSoFar() async {
        let harness = CameraFlowHarness()
        harness.flow.request()
        await harness.flow.startListening()
        harness.transcriber.say("add this to my calendar")
        XCTAssertTrue(harness.flow.cameraTapWorks)

        harness.flow.holdForCamera()
        XCTAssertEqual(harness.transcriber.stopCount, 1, "listening stops while the camera is up")
        XCTAssertEqual(harness.flow.phase, .ready)
        let jpeg = Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9])
        harness.flow.sendPhoto(jpeg)
        await waitForCamera { harness.photosRouted.count == 1 && harness.flow.phase == .ready }

        XCTAssertEqual(harness.photosRouted.first?.0, "add this to my calendar")
        XCTAssertEqual(harness.photosRouted.first?.1, jpeg)
        XCTAssertTrue(harness.routed.isEmpty, "the words were not sent without the photo")
        XCTAssertTrue(harness.flow.isPresented)
    }

    func testAPhotoNeedsNoWords() async {
        let harness = CameraFlowHarness()
        harness.flow.request()
        await harness.flow.startListening()
        harness.flow.holdForCamera()
        harness.flow.sendPhoto(Data([0xFF, 0xD8]))
        await waitForCamera { harness.photosRouted.count == 1 }
        XCTAssertEqual(harness.photosRouted.first?.0, "")
    }

    func testCancelSendsTheWordsAloneOrListensAgain() async {
        let withWords = CameraFlowHarness()
        withWords.flow.request()
        await withWords.flow.startListening()
        withWords.transcriber.say("call mom at 6")
        withWords.flow.holdForCamera()
        await withWords.flow.cameraCancelled()
        await waitForCamera { withWords.routed.count == 1 }
        XCTAssertEqual(withWords.routed, ["call mom at 6"], "nothing said is lost")
        XCTAssertTrue(withWords.photosRouted.isEmpty)

        let noWords = CameraFlowHarness()
        noWords.flow.request()
        await noWords.flow.startListening()
        noWords.flow.holdForCamera()
        await noWords.flow.cameraCancelled()
        XCTAssertEqual(noWords.flow.phase, .listening, "back to listening")
        XCTAssertEqual(noWords.transcriber.startCount, 2)
        XCTAssertTrue(noWords.routed.isEmpty)
    }

    func testNoCameraWithoutAPhotoRoute() async {
        let harness = CameraFlowHarness(withCamera: false)
        harness.flow.request()
        await harness.flow.startListening()
        XCTAssertFalse(harness.flow.hasCamera)
        XCTAssertFalse(harness.flow.cameraTapWorks)
    }

    func testTheButtonSitsRightOfTheOrb() throws {
        XCTAssertGreaterThan(VoiceCaptureView.cameraOffset, VoiceCaptureView.orbSize / 2 + JessCameraSpec.buttonSize / 2, "clear of the orb, on its right")
        XCTAssertLessThan(VoiceCaptureView.orbSize / 2 + VoiceCaptureView.cameraOffset + JessCameraSpec.buttonSize / 2, 402 / 2 + 160, "on screen on an iPhone 16 Pro")
        let source = try String(contentsOf: cameraShellRoot().appending(path: "Midas/VoiceCaptureView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("JessCameraButton(action: openCamera)"))
        XCTAssertTrue(source.contains(".offset(x: Self.cameraOffset)"))
        XCTAssertTrue(source.contains("JessCameraPicker(onFinish: cameraFinished)"))
        let services = try String(contentsOf: cameraShellRoot().appending(path: "Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertTrue(services.contains("voiceDependencies.routePhoto = submitPhotoToJess"))
    }

    func testTheCameraPermissionTextNamesWhatItIsFor() throws {
        let plist = try XCTUnwrap(NSDictionary(contentsOf: cameraShellRoot().appending(path: "Midas/Info.plist")))
        let text = try XCTUnwrap(plist["NSCameraUsageDescription"] as? String)
        XCTAssertTrue(text.hasPrefix("Midas"))
        XCTAssertTrue(text.contains("jess"))
        XCTAssertTrue(text.hasSuffix("."), "a full sentence (docs/WRITING.md rule 10)")
    }
}

// MARK: - The request and its card

@MainActor
private final class CameraBackgroundTime: JessBackgroundTime {
    func begin(expired: @escaping @MainActor () -> Void) -> Int {
        1
    }

    func end(_ token: Int) {}
}

/// Answers in order and notes the photo each call carried.
@MainActor
private final class PhotoRoute {
    var answers: [JessResult]
    private(set) var photosSeen: [Data?] = []

    init(answers: [JessResult]) {
        self.answers = answers
    }

    func route(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        photosSeen.append(JessRouteContext.current?.photo)
        let answer = answers.isEmpty ? JessResult.cutOff(transcript: transcript) : answers.removeFirst()
        if case .done = answer {
            onApplied(answer)
        }
        return answer
    }
}

private func cameraResultsFileURL() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "jess-camera-\(UUID().uuidString)/results.json")
}

@MainActor
private func cameraResults(route: PhotoRoute, fileURL: URL) -> JessResults {
    func routeCall(transcript: String, listenMs: Int, saidAt: Date, timeZone: TimeZone, onApplied: @escaping @MainActor (JessResult) -> Void) async -> JessResult {
        await route.route(transcript: transcript, listenMs: listenMs, saidAt: saidAt, timeZone: timeZone, onApplied: onApplied)
    }
    func isSignedIn() -> Bool {
        true
    }
    func isInForeground() -> Bool {
        false
    }
    func now() -> Date {
        cameraSaidTime
    }
    func timeZone() -> TimeZone {
        TimeZone(identifier: "America/Los_Angeles")!
    }
    var dependencies = JessResultsDependencies(route: routeCall, backgroundTime: CameraBackgroundTime(), isSignedIn: isSignedIn, isInForeground: isInForeground, now: now, timeZone: timeZone)
    dependencies.foregroundRetryDelay = nil
    return JessResults(file: JessResultsFile(fileURL: fileURL), dependencies: dependencies)
}

@MainActor
final class JessCameraResultsTests: XCTestCase {
    private let jpeg = Data([0xFF, 0xD8, 0x10, 0x20, 0xFF, 0xD9])

    func testThePhotoIsSentWithTheRequestAndShownOnItsCard() async {
        let route = PhotoRoute(answers: [.done(text: "Added Dentist", at: nil, allDay: nil, timeZone: nil)])
        let results = cameraResults(route: route, fileURL: cameraResultsFileURL())

        await results.submit(transcript: "", listenMs: 0, photo: jpeg)

        XCTAssertEqual(route.photosSeen, [jpeg])
        let card = results.log[0]
        XCTAssertEqual(card.hasPhoto, true)
        XCTAssertEqual(results.photo(for: card.id), jpeg, "kept on the phone for the card")
        XCTAssertEqual(VoiceReminderCopy.workdeskLine(card), "Added Dentist")
    }

    func testASpokenRequestSendsNoPhoto() async {
        let route = PhotoRoute(answers: [.done(text: "Added Milk", at: nil, allDay: nil, timeZone: nil)])
        let results = cameraResults(route: route, fileURL: cameraResultsFileURL())
        await results.submit(transcript: "add milk", listenMs: 900)
        XCTAssertEqual(route.photosSeen, [nil])
        XCTAssertNil(results.log[0].hasPhoto)
    }

    func testACutOffPhotoRequestSendsThePhotoAgainAfterReopening() async {
        let fileURL = cameraResultsFileURL()
        let firstRoute = PhotoRoute(answers: [.cutOff(transcript: "")])
        let first = cameraResults(route: firstRoute, fileURL: fileURL)
        await first.submit(transcript: "", listenMs: 0, photo: jpeg)
        XCTAssertEqual(first.log[0].kind, .waitingForConnection)
        XCTAssertEqual(VoiceReminderCopy.workdeskLine(first.log[0]), VoiceReminderCopy.photo, "no words: the card says Photo")

        let secondRoute = PhotoRoute(answers: [.done(text: "Added Dentist", at: nil, allDay: nil, timeZone: nil)])
        let reopened = cameraResults(route: secondRoute, fileURL: fileURL)
        await reopened.resume()

        XCTAssertEqual(secondRoute.photosSeen, [jpeg], "the photo went again")
        XCTAssertEqual(reopened.log[0].hasPhoto, true)
    }

    func testDeletingTheCardDeletesThePhoto() async {
        let route = PhotoRoute(answers: [.done(text: "Added Dentist", at: nil, allDay: nil, timeZone: nil)])
        let results = cameraResults(route: route, fileURL: cameraResultsFileURL())
        await results.submit(transcript: "add this", listenMs: 900, photo: jpeg)
        let cardId = results.log[0].id
        XCTAssertNotNil(results.photo(for: cardId))

        results.removeFromLog(cardId: cardId)

        XCTAssertNil(results.photo(for: cardId))
    }

    func testTheWorkdeskShowsTheCardsPhoto() throws {
        let source = try String(contentsOf: cameraShellRoot().appending(path: "Midas/JessWorkdeskView.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("photo: entry.card.hasPhoto == true ? photoFor(entry.card.id) : nil"))
        XCTAssertTrue(source.contains("JessCardPhoto(jpeg: photo, size: 52)"))
        let capture = try String(contentsOf: cameraShellRoot().appending(path: "Midas/VoiceCaptureView.swift"), encoding: .utf8)
        XCTAssertTrue(capture.contains("photoFor: results.photo(for:)"))
    }
}
