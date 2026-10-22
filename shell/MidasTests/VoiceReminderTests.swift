import AVFoundation
import Speech
import SwiftUI
import XCTest
@testable import Midas

// Voice reminders, step 2 (midas-intel docs/plans/2026-10-15-voice-action-button-brief.md, item 6):
// jess's orb state mapping; "New Reminder" opens the Listening screen; the silence and time
// limits; the record built passes the real Reminders schema; the banner's words per state; and
// the flow around them (saved at once on "done", nothing saved otherwise, Try Again re-sends).

private let pacificZone = TimeZone(identifier: "America/Los_Angeles")!
private let fixedNow = ISO8601DateFormatter().date(from: "2026-10-19T16:00:00Z")!
private let usLocale = Locale(identifier: "en_US")

private func gregorian() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = pacificZone
    return calendar
}

private func tomorrowAtSix() -> VoiceResolvedReminder {
    VoiceResolvedReminder(title: "Call Mom", notes: nil, list: nil, date: "2026-10-20", time: "18:00", allDay: false, at: "2026-10-21T01:00:00.000Z", repeat: nil, timeZone: pacificZone.identifier)
}

/// iOS writes "6:00 PM" with a narrow no-break space; compare with a plain one.
private func plainSpaces(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

/// Waits for something the flow does on the main actor after an await.
@MainActor
private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 2) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Stands in for the shared transcriber: the test says words and ends listening.
@MainActor
private final class ScriptedTranscriber: VoiceTranscribing {
    var onUpdate: (@MainActor (VoiceTranscript) -> Void)?
    var onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?
    var startError: Error?
    private(set) var stopCount = 0

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (VoiceTranscript) -> Void, onEnd: (@MainActor (VoiceTranscriptionEnd) -> Void)?) async throws {
        if let startError {
            throw startError
        }
        self.onUpdate = onUpdate
        self.onEnd = onEnd
    }

    func stop() {
        stopCount += 1
        end(.stopped)
    }

    func say(_ text: String) {
        onUpdate?(VoiceTranscript(text: text, words: []))
    }

    func end(_ reason: VoiceTranscriptionEnd) {
        let endHandler = onEnd
        onEnd = nil
        onUpdate = nil
        endHandler?(reason)
    }
}

/// Stands in for POST /voice/reminder/parse: answers from a list, after an optional delay.
private final class ScriptedParser: VoiceReminderParsing, @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [VoiceParseResult]
    private var receivedRequests: [VoiceParseRequest] = []
    let delay: Duration

    init(answers: [VoiceParseResult], delay: Duration = .zero) {
        self.answers = answers
        self.delay = delay
    }

    var requests: [VoiceParseRequest] {
        lock.withLock { receivedRequests }
    }

    func parse(_ request: VoiceParseRequest) async -> VoiceParseResult {
        let answer: VoiceParseResult = lock.withLock {
            receivedRequests.append(request)
            return answers.isEmpty ? .unreachable : answers.removeFirst()
        }
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
        return answer
    }
}

private struct SaveRefused: Error {}

@MainActor
private final class FlowHarness {
    let transcriber = ScriptedTranscriber()
    let parser: ScriptedParser
    var signedIn = true
    var saved: [VoiceResolvedReminder] = []
    var refuseSave = false
    var optionsSeen: [VoiceTranscriberOptions] = []
    let lists = [VoiceReminderList(id: "work", name: "Work"), VoiceReminderList(id: "groceries", name: "Groceries")]
    private(set) var flow: VoiceReminderFlow!

    init(answers: [VoiceParseResult], delay: Duration = .zero) {
        parser = ScriptedParser(answers: answers, delay: delay)
        flow = VoiceReminderFlow(dependencies: dependencies())
    }

    private func dependencies() -> VoiceReminderDependencies {
        func isSignedIn() -> Bool {
            signedIn
        }
        func currentLists() -> [VoiceReminderList] {
            lists
        }
        func makeTranscriber(options: VoiceTranscriberOptions, meter: VoiceAudioLevelMeter) -> VoiceTranscribing {
            optionsSeen.append(options)
            return transcriber
        }
        func save(_ reminder: VoiceResolvedReminder) throws {
            if refuseSave {
                throw SaveRefused()
            }
            saved.append(reminder)
        }
        func now() -> Date {
            fixedNow
        }
        func timeZone() -> TimeZone {
            pacificZone
        }
        func app() -> VoiceParseApp {
            VoiceParseApp(version: "0.1.0", build: "3", ios: "26.1", device: "iPhone17,1")
        }
        return VoiceReminderDependencies(isSignedIn: isSignedIn, lists: currentLists, makeTranscriber: makeTranscriber, api: parser, save: save, now: now, timeZone: timeZone, app: app)
    }

    /// "New Reminder", the screen appears and listens, the words come, then listening ends.
    func speak(_ text: String, endingWith reason: VoiceTranscriptionEnd = .silence) async {
        flow.request()
        await flow.startListening()
        transcriber.say(text)
        transcriber.end(reason)
    }
}

private struct GrantedVoicePermissions: VoicePermissionSystem {
    var microphone: VoicePermissionAnswer { .granted }
    var speech: VoicePermissionAnswer { .granted }
    func requestMicrophone() async {}
    func requestSpeech() async {}
}

@MainActor
private final class SilentSpeechEngine: SpeechRecognitionEngine {
    var isOnDeviceAvailable: Bool { true }
    private(set) var tap: VoiceAudioTap?
    private(set) var request: SFSpeechAudioBufferRecognitionRequest?
    func startAudio(tap: @escaping VoiceAudioTap) throws {
        self.tap = tap
    }
    func stopAudio() {}
    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        self.request = request
    }
    func cancelRecognition() {}
}

/// A mono buffer holding the same sample throughout.
private func constantBuffer(sample: Float, frames: AVAudioFrameCount = 1024) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let samples = buffer.floatChannelData![0]
    for index in 0..<Int(frames) {
        samples[index] = sample
    }
    return buffer
}

/// Records the meter's level from a queue that is not the main actor, as iOS's audio thread does.
private final class MeterReading: @unchecked Sendable {
    var level: Float = -1
}

// MARK: - jess's orb

@MainActor
final class JessOrbTests: XCTestCase {
    func testTheCoreAloneCarriesTheResultInBothModes() {
        let light = JessOrbPalette.forScheme(.light)
        let dark = JessOrbPalette.forScheme(.dark)
        XCTAssertEqual(light.coreColor(for: .added), JessOrbColor(hex: 0x00873A))
        XCTAssertEqual(light.coreColor(for: .failed), JessOrbColor(hex: 0xE00000))
        XCTAssertEqual(dark.coreColor(for: .added), JessOrbColor(hex: 0x3DDC84))
        XCTAssertEqual(dark.coreColor(for: .failed), JessOrbColor(hex: 0xFF5C5C))
        for state in [JessOrbState.idle, .thinking] {
            XCTAssertEqual(light.coreColor(for: state), JessOrbColor(hex: 0x000000), "light core is black while \(state)")
            XCTAssertEqual(dark.coreColor(for: state), JessOrbColor(hex: 0xFFFFFF), "dark core is white while \(state)")
        }
        // DESIGN.md §5a, founder 2026-10-22: while jess listens the core is Volt.
        XCTAssertEqual(light.coreColor(for: .listening), JessOrbColor(hex: 0xCEFF00), "light core is Volt while listening")
        XCTAssertEqual(dark.coreColor(for: .listening), JessOrbColor(hex: 0xE7FF85), "dark core is light Volt while listening")
        XCTAssertEqual(light.body, JessOrbColor(hex: 0xFFFFFF))
        XCTAssertEqual(light.ring, JessOrbColor(hex: 0x111111))
        XCTAssertEqual(dark.body, JessOrbColor(hex: 0x000000))
        XCTAssertEqual(dark.ring, JessOrbColor(hex: 0x2A2A2A))
    }

    func testNoPurpleAnywhere() {
        // DESIGN.md §5a: never purple or violet. Purple is blue well above green with red up too.
        for palette in [JessOrbPalette.light, JessOrbPalette.dark] {
            let colours = [palette.body, palette.bodyGlow, palette.ring, palette.core, palette.arc, palette.arcGlow, palette.listening, palette.added, palette.failed]
            for colour in colours {
                let isPurple = colour.blue > colour.green + 0.15 && colour.red > colour.green + 0.15
                XCTAssertFalse(isPurple, "\(colour) reads as purple")
            }
        }
    }

    func testFlowPhasesAndBannersMapToOrbStates() {
        XCTAssertEqual(VoiceCapturePhase.listening.orbState, .listening)
        XCTAssertEqual(VoiceCapturePhase.sending.orbState, .thinking)
        XCTAssertEqual(VoiceCapturePhase.unavailable(.permissionDenied).orbState, .idle)
        XCTAssertEqual(VoiceBanner(kind: .added(tomorrowAtSix())).orbState, .added)
        XCTAssertEqual(VoiceBanner(kind: .notAdded(transcript: "x")).orbState, .failed)
        XCTAssertEqual(VoiceBanner(kind: .retrying(transcript: "x")).orbState, .thinking)
    }

    func testOnlyListeningFollowsTheVoice() {
        let quiet = JessOrbMotion.drivingLevel(state: .listening, audioLevel: 0, time: 1)
        let loud = JessOrbMotion.drivingLevel(state: .listening, audioLevel: 1, time: 1)
        XCTAssertEqual(quiet, 0.25, accuracy: 0.0001)
        XCTAssertEqual(loud, 1, accuracy: 0.0001)
        XCTAssertEqual(JessOrbMotion.drivingLevel(state: .thinking, audioLevel: 1, time: 1), 0.18, accuracy: 0.0001)
        XCTAssertLessThan(JessOrbMotion.drivingLevel(state: .idle, audioLevel: 1, time: 1), 0.12)

        let quietCore = JessOrbMotion.coreRadius(bodyRadius: 100, state: .listening, level: quiet)
        let loudCore = JessOrbMotion.coreRadius(bodyRadius: 100, state: .listening, level: loud)
        XCTAssertGreaterThan(loudCore, quietCore)
        XCTAssertEqual(JessOrbMotion.coreRadius(bodyRadius: 100, state: .idle, level: 1), 30, accuracy: 0.0001)
        XCTAssertEqual(JessOrbMotion.coreRadius(bodyRadius: 100, state: .added, level: 1), 30, accuracy: 0.0001)
    }

    func testALouderVoiceRipplesTheOutlineMore() {
        var quietMotion = JessOrbMotion()
        var loudMotion = JessOrbMotion()
        for _ in 0..<120 {
            quietMotion.step(level: JessOrbMotion.drivingLevel(state: .listening, audioLevel: 0, time: 0), thinking: false)
            loudMotion.step(level: JessOrbMotion.drivingLevel(state: .listening, audioLevel: 1, time: 0), thinking: false)
        }
        let quietSum = quietMotion.amplitudes.reduce(0, +)
        let loudSum = loudMotion.amplitudes.reduce(0, +)
        XCTAssertGreaterThan(loudSum, quietSum * 2)
    }

    func testThinkingSweepsTheArcAndPushesTheWallOutAheadOfIt() {
        var motion = JessOrbMotion()
        for _ in 0..<30 {
            motion.step(level: 0.18, thinking: true)
        }
        XCTAssertEqual(motion.arcAngle, 30 * 0.06, accuracy: 0.0001)
        let underArc = motion.outlineOffset(at: motion.arcAngle, thinking: true)
        let opposite = motion.outlineOffset(at: motion.arcAngle + Double.pi, thinking: true)
        XCTAssertGreaterThan(underArc - opposite, 0.03)
        XCTAssertEqual(motion.outlineOffset(at: motion.arcAngle, thinking: false) + 0.05, underArc, accuracy: 0.0001)
        var still = JessOrbMotion()
        still.step(level: 0.18, thinking: false)
        XCTAssertEqual(still.arcAngle, 0)
    }

    func testReduceMotionDrawsAStillOrb() {
        XCTAssertFalse(JessOrb.isAnimated(reduceMotion: true))
        XCTAssertTrue(JessOrb.isAnimated(reduceMotion: false))
    }

    func testMotionAdvancesAtSixtyStepsASecondAndSkipsLongPauses() {
        var motion = JessOrbMotion()
        motion.advance(to: 10, state: .thinking, audioLevel: 0)
        let settledArc = motion.arcAngle
        motion.advance(to: 10.5, state: .thinking, audioLevel: 0)
        XCTAssertEqual(motion.arcAngle - settledArc, 30 * 0.06, accuracy: 0.0001)
        let beforePause = motion.arcAngle
        motion.advance(to: 1000, state: .thinking, audioLevel: 0)
        XCTAssertEqual(motion.arcAngle - beforePause, Double(JessOrbMotion.maximumStepsPerAdvance) * 0.06, accuracy: 0.0001)
    }

    func testTheOrbRendersInBothModesAndEveryState() throws {
        for scheme in [ColorScheme.light, .dark] {
            for state in [JessOrbState.idle, .listening, .thinking, .added, .failed] {
                let renderer = ImageRenderer(content: JessOrb(state: state).frame(width: 120, height: 120).environment(\.colorScheme, scheme))
                let image = try XCTUnwrap(renderer.uiImage, "\(state) in \(scheme) did not render")
                XCTAssertEqual(image.size.width, 120, accuracy: 0.5)
            }
        }
    }
}

// MARK: - The way in

@MainActor
final class VoiceReminderEntryTests: XCTestCase {
    override func tearDown() {
        VoiceReminderIntentBridge.open = MidasApp.openVoiceReminder
        super.tearDown()
    }

    func testTheAppRegistersNewReminderAtLaunch() {
        XCTAssertNotNil(VoiceReminderIntentBridge.open, "MidasApp.init plugs the handler in")
        XCTAssertTrue(StartVoiceReminderIntent.openAppWhenRun, "the intent must bring Midas to the front")
    }

    func testNewReminderOpensTheListeningScreen() async throws {
        let harness = FlowHarness(answers: [])
        let flow = harness.flow!
        func openTestFlow() {
            flow.request()
        }
        VoiceReminderIntentBridge.open = openTestFlow
        XCTAssertFalse(flow.isPresented)
        _ = try await StartVoiceReminderIntent().perform()
        XCTAssertTrue(flow.isPresented)
        XCTAssertEqual(flow.phase, .listening)
    }

    func testSignedOutNewReminderShowsNothing() async throws {
        let harness = FlowHarness(answers: [])
        harness.signedIn = false
        let flow = harness.flow!
        func openTestFlow() {
            flow.request()
        }
        VoiceReminderIntentBridge.open = openTestFlow
        _ = try await StartVoiceReminderIntent().perform()
        XCTAssertFalse(flow.isPresented)
    }

    func testTheListeningScreenRendersInBothModes() throws {
        let harness = FlowHarness(answers: [])
        harness.flow.request()
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: VoiceCaptureView(flow: harness.flow).frame(width: 393, height: 852).environment(\.colorScheme, scheme))
            XCTAssertNotNil(renderer.uiImage)
        }
    }
}

// MARK: - Silence and time limits

@MainActor
final class VoiceReminderListeningTests: XCTestCase {
    func testListeningEndsAfterOnePointTwoSecondsOfSilenceOrFifteenSecondsWithListNamesAsHints() {
        let options = VoiceReminderListening.transcriberOptions(lists: [VoiceReminderList(id: "work", name: "Work"), VoiceReminderList(id: "groceries", name: "Groceries")])
        XCTAssertEqual(options.endOfSpeechSilence, .milliseconds(1200))
        XCTAssertEqual(options.maximumDuration, .seconds(15))
        XCTAssertEqual(options.hintWords, ["Work", "Groceries"])
        XCTAssertNotEqual(options, .repair, "repair keeps its own settings")
    }

    func testTheFlowStartsTheTranscriberWithThoseLimits() async {
        let harness = FlowHarness(answers: [.done(tomorrowAtSix())])
        await harness.speak("Remind me to call Mom tomorrow at 6pm")
        XCTAssertEqual(harness.optionsSeen, [VoiceReminderListening.transcriberOptions(lists: harness.lists)])
    }

    func testTheRealTranscriberEndsOnSilenceWithTheseOptions() async throws {
        let engine = SilentSpeechEngine()
        let options = VoiceReminderListening.transcriberOptions(lists: [])
        let transcriber = OnDeviceSpeechTranscriber(options: options, permissions: GrantedVoicePermissions(), engine: engine)
        var endings: [VoiceTranscriptionEnd] = []
        func recordEnd(_ reason: VoiceTranscriptionEnd) {
            endings.append(reason)
        }
        func ignoreUpdate(_ transcript: VoiceTranscript) {}
        try await transcriber.start(sessionStartedAt: Date(), onUpdate: ignoreUpdate, onEnd: recordEnd)
        transcriber.receive(.heard(VoiceTranscript(text: "Call Mom", words: [])))
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(endings, [], "still listening before 1.2 s of silence")
        await waitFor({ !endings.isEmpty }, timeout: 2)
        XCTAssertEqual(endings, [.silence])
    }

    func testEndingOnSilenceSendsWhatWasSaid() async {
        let harness = FlowHarness(answers: [.done(tomorrowAtSix())])
        await harness.speak("Remind me to call Mom tomorrow at 6pm", endingWith: .silence)
        await waitFor({ harness.flow.banner != nil })
        XCTAssertEqual(harness.parser.requests.map(\.transcript), ["Remind me to call Mom tomorrow at 6pm"])
        let request = harness.parser.requests[0]
        XCTAssertEqual(request.timeZone, "America/Los_Angeles")
        XCTAssertEqual(request.now, "2026-10-19T16:00:00.000Z")
        XCTAssertEqual(request.lists, harness.lists)
        XCTAssertEqual(request.app.build, "3")
    }

    func testReachingFifteenSecondsSendsWhatWasSaid() async {
        let harness = FlowHarness(answers: [.done(tomorrowAtSix())])
        await harness.speak("Remind me to call Mom tomorrow at 6pm and also", endingWith: .maximumLength)
        await waitFor({ harness.flow.banner != nil })
        XCTAssertEqual(harness.parser.requests.count, 1)
    }

    func testCancelSendsNothingSavesNothingAndShowsNoBanner() async throws {
        let harness = FlowHarness(answers: [.done(tomorrowAtSix())])
        harness.flow.request()
        await harness.flow.startListening()
        harness.transcriber.say("Remind me to call Mom")
        harness.flow.cancel()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(harness.flow.isPresented)
        XCTAssertEqual(harness.transcriber.stopCount, 1)
        XCTAssertEqual(harness.parser.requests.count, 0)
        XCTAssertNil(harness.flow.banner)
        XCTAssertEqual(harness.saved, [])
    }

    func testCancelWhileSendingDropsTheAnswer() async throws {
        let harness = FlowHarness(answers: [.done(tomorrowAtSix())], delay: .milliseconds(200))
        await harness.speak("Remind me to call Mom tomorrow at 6pm")
        XCTAssertEqual(harness.flow.phase, .sending)
        harness.flow.cancel()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(harness.parser.requests.count, 1)
        XCTAssertEqual(harness.saved, [])
        XCTAssertNil(harness.flow.banner)
    }

    func testSilenceWithNothingSaidClosesWithoutSending() async throws {
        let harness = FlowHarness(answers: [])
        harness.flow.request()
        await harness.flow.startListening()
        harness.transcriber.end(.maximumLength)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(harness.flow.isPresented)
        XCTAssertEqual(harness.parser.requests.count, 0)
        XCTAssertNil(harness.flow.banner)
    }

    func testDeclinedPermissionShowsWhyInsteadOfListening() async {
        let harness = FlowHarness(answers: [])
        harness.transcriber.startError = VoiceTranscriberError.notAuthorized
        harness.flow.request()
        await harness.flow.startListening()
        XCTAssertEqual(harness.flow.phase, .unavailable(.permissionDenied))
        harness.transcriber.startError = VoiceTranscriberError.onDeviceUnavailable
        await harness.flow.startListening()
        XCTAssertEqual(harness.flow.phase, .unavailable(.onDeviceUnavailable))
    }
}

// MARK: - The save, the banner, Try Again

@MainActor
final class VoiceReminderResultTests: XCTestCase {
    func testADoneAnswerIsSavedAtOnceAndTheBannerSaysAdded() async {
        let harness = FlowHarness(answers: [.done(tomorrowAtSix())])
        await harness.speak("Remind me to call Mom tomorrow at 6pm")
        await waitFor({ harness.flow.banner != nil })
        XCTAssertEqual(harness.saved, [tomorrowAtSix()])
        XCTAssertEqual(harness.flow.banner?.kind, .added(tomorrowAtSix()))
        XCTAssertFalse(harness.flow.isPresented)
    }

    func testNotDoneSavesNothingAndKeepsWhatWasSaid() async {
        let harness = FlowHarness(answers: [.notDone(reason: "not-confident")])
        await harness.speak("Remind me about the thing with Sam")
        await waitFor({ harness.flow.banner != nil })
        XCTAssertEqual(harness.saved, [])
        XCTAssertEqual(harness.flow.banner?.kind, .notAdded(transcript: "Remind me about the thing with Sam"))
    }

    func testNoNetworkSavesNothingAndKeepsWhatWasSaid() async {
        let harness = FlowHarness(answers: [.unreachable])
        await harness.speak("Remind me to call Mom tomorrow at 6pm")
        await waitFor({ harness.flow.banner != nil })
        XCTAssertEqual(harness.saved, [])
        XCTAssertEqual(harness.flow.banner?.kind, .notAdded(transcript: "Remind me to call Mom tomorrow at 6pm"))
    }

    func testARefusedRecordIsNotAdded() async {
        let harness = FlowHarness(answers: [.done(tomorrowAtSix())])
        harness.refuseSave = true
        await harness.speak("Remind me to call Mom tomorrow at 6pm")
        await waitFor({ harness.flow.banner != nil })
        XCTAssertEqual(harness.flow.banner?.kind, .notAdded(transcript: "Remind me to call Mom tomorrow at 6pm"))
    }

    func testTryAgainResendsTheSameTranscriptWithoutListening() async {
        let harness = FlowHarness(answers: [.unreachable, .done(tomorrowAtSix())], delay: .milliseconds(50))
        await harness.speak("Remind me to call Mom tomorrow at 6pm")
        await waitFor({ harness.flow.banner != nil })
        harness.flow.retry()
        XCTAssertEqual(harness.flow.banner?.kind, .retrying(transcript: "Remind me to call Mom tomorrow at 6pm"))
        XCTAssertFalse(harness.flow.isPresented)
        await waitFor({ harness.flow.banner?.kind == .added(tomorrowAtSix()) })
        XCTAssertEqual(harness.parser.requests.map(\.transcript), ["Remind me to call Mom tomorrow at 6pm", "Remind me to call Mom tomorrow at 6pm"])
        XCTAssertEqual(harness.optionsSeen.count, 1, "Try Again does not listen again")
        XCTAssertEqual(harness.saved, [tomorrowAtSix()])
    }

    func testBannerWordsPerState() {
        let calendar = gregorian()
        func body(_ kind: VoiceBanner.Kind) -> String {
            plainSpaces(VoiceReminderCopy.body(for: kind, now: fixedNow, calendar: calendar, locale: usLocale))
        }
        let added = VoiceBanner.Kind.added(tomorrowAtSix())
        XCTAssertEqual(VoiceReminderCopy.title(for: added), "Added")
        XCTAssertEqual(body(added), "Call Mom · Tomorrow, 6:00 PM")
        XCTAssertNil(VoiceReminderCopy.actionTitle(for: added))

        let notAdded = VoiceBanner.Kind.notAdded(transcript: "Remind me about the thing with Sam")
        XCTAssertEqual(VoiceReminderCopy.title(for: notAdded), "Not Added")
        XCTAssertEqual(body(notAdded), "“Remind me about the thing with Sam”")
        XCTAssertEqual(VoiceReminderCopy.actionTitle(for: notAdded), "Try Again")

        let retrying = VoiceBanner.Kind.retrying(transcript: "Remind me about the thing with Sam")
        XCTAssertEqual(VoiceReminderCopy.title(for: retrying), "Adding…")
        XCTAssertEqual(body(retrying), "“Remind me about the thing with Sam”")
        XCTAssertNil(VoiceReminderCopy.actionTitle(for: retrying))

        let allDay = VoiceResolvedReminder(title: "Renew passport", notes: nil, list: nil, date: "2026-10-20", time: nil, allDay: true, at: "2026-10-20T16:00:00.000Z", repeat: nil, timeZone: pacificZone.identifier)
        XCTAssertEqual(body(.added(allDay)), "Renew passport · Tomorrow")
        let undated = VoiceResolvedReminder(title: "Bananas", notes: nil, list: "groceries", date: nil, time: nil, allDay: false, at: nil, repeat: nil, timeZone: pacificZone.identifier)
        XCTAssertEqual(body(.added(undated)), "Bananas")
        let laterToday = VoiceResolvedReminder(title: "Stretch", notes: nil, list: nil, date: "2026-10-19", time: "17:30", allDay: false, at: "2026-10-20T00:30:00.000Z", repeat: nil, timeZone: pacificZone.identifier)
        XCTAssertEqual(body(.added(laterToday)), "Stretch · Today, 5:30 PM")
        let friday = VoiceResolvedReminder(title: "Dry cleaning", notes: nil, list: nil, date: "2026-10-23", time: "18:00", allDay: false, at: "2026-10-24T01:00:00.000Z", repeat: VoiceReminderRepeat(every: "week", interval: nil, weekdays: [5]), timeZone: pacificZone.identifier)
        XCTAssertEqual(body(.added(friday)), "Dry cleaning · Friday, 6:00 PM")
        let later = VoiceResolvedReminder(title: "Dentist", notes: nil, list: nil, date: "2026-11-03", time: nil, allDay: true, at: "2026-11-03T17:00:00.000Z", repeat: nil, timeZone: pacificZone.identifier)
        XCTAssertEqual(body(.added(later)), "Dentist · Nov 3")

        XCTAssertEqual(VoiceReminderCopy.problemTitle(.permissionDenied), "Microphone Off")
        XCTAssertEqual(VoiceReminderCopy.problemTitle(.onDeviceUnavailable), "Voice Not Available")
        XCTAssertEqual(VoiceReminderCopy.cancel, "Cancel")
    }

    func testTheBannerRendersInEveryStateAndMode() {
        let kinds: [VoiceBanner.Kind] = [.added(tomorrowAtSix()), .notAdded(transcript: "Remind me about the thing with Sam"), .retrying(transcript: "x")]
        for scheme in [ColorScheme.light, .dark] {
            for kind in kinds {
                let view = VoiceResultBanner(banner: VoiceBanner(kind: kind), onRetry: {}, onDismiss: {}).frame(width: 393).environment(\.colorScheme, scheme)
                XCTAssertNotNil(ImageRenderer(content: view).uiImage)
            }
        }
    }
}

// MARK: - The record and the route's answers

@MainActor
final class VoiceReminderRecordTests: XCTestCase {
    private var folder: URL!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory.appending(path: "voice-record-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    /// The Reminders Sidekick's own manifest, the schema a user's copy starts from.
    private func remindersTypes() throws -> JSONValue {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let manifestURL = testsDirectory.appending(path: "../../sidekicks/reminders/manifest.json").standardizedFileURL
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        return try XCTUnwrap(manifest["types"])
    }

    private func gatedStore() throws -> LocalRecordStore {
        let engine = try RecordSchemaEngine(bundle: Bundle(for: RecordSchemaEngine.self))
        let types = try remindersTypes()
        func typesFor(sidekickId: String) -> JSONValue? {
            sidekickId == "reminders" ? types : nil
        }
        let store = LocalRecordStore(fileURL: folder.appending(path: "records.json"))
        store.writeGate = RecordTypeGate.make(engine: engine, typesProvider: typesFor)
        return store
    }

    func testTheRecordBuiltPassesTheRemindersSchemaAndMatchesThePagesShape() throws {
        let store = try gatedStore()
        let writer = RecordWriter(store: store)
        let reminder = VoiceResolvedReminder(title: "Pick up the dry cleaning", notes: "Blue jacket", list: "errands", date: "2026-10-23", time: "18:00", allDay: false, at: "2026-10-24T01:00:00.000Z", repeat: VoiceReminderRepeat(every: "week", interval: 2, weekdays: [5]), timeZone: pacificZone.identifier)

        let key = try VoiceReminderRecord.save(reminder, writer: writer, now: fixedNow)
        XCTAssertNotNil(key.range(of: "^reminder:[0-9a-z]{12}$", options: .regularExpression), key)
        let stored = try XCTUnwrap(store.get(sidekickId: "reminders", key: key))
        let expected: JSONValue = .object([
            "$type": .string("reminders.item"),
            "title": .string("Pick up the dry cleaning"),
            "notes": .string("Blue jacket"),
            "list": .string("errands"),
            "done": .bool(false),
            "timeZone": .string("America/Los_Angeles"),
            "createdAt": .string("2026-10-19T16:00:00.000Z"),
            "at": .string("2026-10-24T01:00:00.000Z"),
            "allDay": .bool(false),
            "repeat": .object(["every": .string("week"), "interval": .number(2), "weekdays": .array([.number(5)])]),
        ])
        XCTAssertEqual(stored, expected)
        XCTAssertNil(ReminderRecord.validationError(stored), "the notification engine accepts it")
        XCTAssertEqual(store.pendingOps().count, 1, "it goes to the outbox to sync")
    }

    func testAnUndatedReminderLeavesOutTheDateFields() throws {
        let store = try gatedStore()
        let writer = RecordWriter(store: store)
        let reminder = VoiceResolvedReminder(title: "Bananas", notes: nil, list: "groceries", date: nil, time: nil, allDay: false, at: nil, repeat: nil, timeZone: pacificZone.identifier)
        let key = try VoiceReminderRecord.save(reminder, writer: writer, now: fixedNow)
        let stored = try XCTUnwrap(store.get(sidekickId: "reminders", key: key))
        XCTAssertNil(stored["at"])
        XCTAssertNil(stored["allDay"])
        XCTAssertNil(stored["repeat"])
        XCTAssertNil(stored["notes"])
        XCTAssertEqual(stored["list"], JSONValue.string("groceries"))
        XCTAssertEqual(stored["done"], JSONValue.bool(false))
    }

    func testTheSchemaGateRefusesABrokenRecord() throws {
        let store = try gatedStore()
        let writer = RecordWriter(store: store)
        let broken = VoiceResolvedReminder(title: "", notes: nil, list: nil, date: nil, time: nil, allDay: false, at: nil, repeat: nil, timeZone: pacificZone.identifier)
        XCTAssertThrowsError(try VoiceReminderRecord.save(broken, writer: writer, now: fixedNow))
        XCTAssertEqual(store.query(sidekickId: "reminders", keyPrefix: "reminder:").count, 0)
    }

    func testIdsAreTwelveBase36CharactersAndDiffer() {
        var seen = Set<String>()
        for _ in 0..<200 {
            let id = VoiceReminderRecord.newId()
            XCTAssertNotNil(id.range(of: "^[0-9a-z]{12}$", options: .regularExpression))
            seen.insert(id)
        }
        XCTAssertEqual(seen.count, 200)
    }

    func testListsComeFromTheRemindersStore() throws {
        let store = LocalRecordStore(fileURL: folder.appending(path: "lists.json"))
        try store.set(sidekickId: "reminders", key: "list:work", value: .object(["name": .string("Work")]))
        try store.set(sidekickId: "reminders", key: "list:empty", value: .object(["name": .string("")]))
        try store.set(sidekickId: "care-reminders", key: "list:meds", value: .object(["name": .string("Meds")]))
        XCTAssertEqual(VoiceReminderRecord.lists(in: store), [VoiceReminderList(id: "work", name: "Work")])
    }

    func testTheRouteAnswersAreRead() throws {
        let done = Data(#"{"status":"done","reminder":{"title":"Call Mom","notes":null,"list":null,"date":"2026-10-20","time":"18:00","allDay":false,"at":"2026-10-21T01:00:00.000Z","repeat":null,"timeZone":"America/Los_Angeles"}}"#.utf8)
        XCTAssertEqual(RemoteVoiceReminderAPI.result(statusCode: 200, data: done), .done(tomorrowAtSix()))
        let notDone = Data(#"{"status":"not-done","reason":"past","transcript":"x"}"#.utf8)
        XCTAssertEqual(RemoteVoiceReminderAPI.result(statusCode: 200, data: notDone), .notDone(reason: "past"))
        XCTAssertEqual(RemoteVoiceReminderAPI.result(statusCode: 401, data: Data()), .unreachable)
        XCTAssertEqual(RemoteVoiceReminderAPI.result(statusCode: 200, data: Data("nonsense".utf8)), .unreachable)

        let body = VoiceParseRequest(transcript: "x", now: "2026-10-19T16:00:00.000Z", timeZone: "America/Los_Angeles", locale: "en-US", lists: [], app: VoiceParseApp(version: "0.1.0", build: "3", ios: "26.1", device: "iPhone17,1"), listenMs: 1200)
        let request = try RemoteVoiceReminderAPI.urlRequest(platformOrigin: URL(string: "https://midas-api-staging.midas-backend.workers.dev")!, body: body, token: "abc")
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api-staging.midas-backend.workers.dev/voice/reminder/parse")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(request.timeoutInterval, 15)
        let sent = try JSONDecoder().decode(JSONValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(sent["transcript"], .string("x"))
        XCTAssertEqual(sent["listenMs"], .number(1200))
    }
}

// MARK: - The shared transcriber's audio level

final class VoiceAudioLevelTests: XCTestCase {
    func testLoudnessMapsFromMinusFiftyToMinusTenDecibels() {
        XCTAssertEqual(VoiceAudioLevelMeter.level(fromRootMeanSquare: 0), 0)
        XCTAssertEqual(VoiceAudioLevelMeter.level(fromRootMeanSquare: 0.001), 0, accuracy: 0.0001)
        XCTAssertEqual(VoiceAudioLevelMeter.level(fromRootMeanSquare: 0.01), 0.25, accuracy: 0.001)
        XCTAssertEqual(VoiceAudioLevelMeter.level(fromRootMeanSquare: 0.1), 0.75, accuracy: 0.001)
        XCTAssertEqual(VoiceAudioLevelMeter.level(fromRootMeanSquare: 1), 1)
        XCTAssertEqual(VoiceAudioLevelMeter.level(of: constantBuffer(sample: 0.1)), 0.75, accuracy: 0.001)
        XCTAssertEqual(VoiceAudioLevelMeter.level(of: constantBuffer(sample: 0)), 0)
    }

    func testTheTapMeasuresOnTheAudioThread() {
        let meter = VoiceAudioLevelMeter()
        let box = VoiceRecognitionRequestBox(request: SFSpeechAudioBufferRecognitionRequest())
        let tap = OnDeviceSpeechTranscriber.makeAudioTap(feeding: box, meter: meter)
        let buffer = constantBuffer(sample: 0.1)
        let reading = MeterReading()
        let measured = expectation(description: "tap ran off the main thread")
        DispatchQueue.global(qos: .userInteractive).async {
            tap(buffer, AVAudioTime(sampleTime: 0, atRate: 16000))
            reading.level = meter.level
            measured.fulfill()
        }
        wait(for: [measured], timeout: 2)
        XCTAssertEqual(reading.level, 0.75, accuracy: 0.001)
        meter.reset()
        XCTAssertEqual(meter.level, 0)
    }

    @MainActor
    func testTheTranscriberFeedsItsMeterAndClearsItWhenListeningEnds() async throws {
        let engine = SilentSpeechEngine()
        let meter = VoiceAudioLevelMeter()
        let transcriber = OnDeviceSpeechTranscriber(options: VoiceReminderListening.transcriberOptions(lists: []), permissions: GrantedVoicePermissions(), engine: engine, audioLevel: meter)
        func ignoreUpdate(_ transcript: VoiceTranscript) {}
        try await transcriber.start(sessionStartedAt: Date(), onUpdate: ignoreUpdate, onEnd: nil)
        let tap = try XCTUnwrap(engine.tap)
        tap(constantBuffer(sample: 0.1), AVAudioTime(sampleTime: 0, atRate: 16000))
        XCTAssertEqual(meter.level, 0.75, accuracy: 0.001)
        XCTAssertIdentical(transcriber.audioLevel, meter)
        transcriber.stop()
        XCTAssertEqual(meter.level, 0)
    }
}
