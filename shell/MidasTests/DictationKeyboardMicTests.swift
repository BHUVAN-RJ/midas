#if MIDAS_TEST_BUILD
// Build 34: mic inside the keyboard (TEST BUILD, founder 2026-11-19; docs/briefs/dictation-keyboard-test.md,
// "Build 34"; branch agent/dictation-test, never merged). Compiled only against a Test build: run
// with the "Midas Test" scheme's test action.
//
// The keyboardMic setting and the fallback to the app switch; the step-by-step result mapping
// (which step failed and with which error, the audio when no words came, an attempt iOS ended);
// the `dictation.probe` record; the App Group files (settings, the attempt, the queued probes and
// runs); the keyboard's listener on a stand-in engine (fails at a step, works at the first words
// and inserts the gate's text after a pause, no words at stop); and Midas Test saving what the
// keyboard queued.
import AVFoundation
import Speech
import XCTest
@testable import Midas

/// A stand-in microphone and recogniser: each step can throw; the recogniser's callback is kept.
@MainActor
private final class StandInMicEngine: DictationKeyboardMicEngine {
    var onStep: ((DictationKeyboardProbeStep) -> Void)?
    private(set) var lastStepFailure: (step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError)?
    var lastRecogniserError: DictationKeyboardProbeError?
    var audioCount = DictationKeyboardAudioCount(buffers: 120, peak: 0.4)
    var isOnDeviceAvailable = true
    /// The step that throws this error, if any.
    var failingStep: DictationKeyboardProbeStep?
    var failingError = NSError(domain: "com.apple.coreaudio.avfaudio", code: 561_145_187, userInfo: [NSLocalizedDescriptionKey: "Session activation failed"])
    private(set) var stepsSeen: [DictationKeyboardProbeStep] = []
    private(set) var audioStarts = 0
    private(set) var audioStops = 0

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        lastStepFailure = nil
        audioStarts += 1
        for step in [DictationKeyboardProbeStep.sessionCategory, .activate, .engineStart] {
            stepsSeen.append(step)
            onStep?(step)
            if step == failingStep {
                lastStepFailure = (step, DictationKeyboardProbeError(failingError))
                throw failingError
            }
        }
        stepsSeen.append(.audio)
        onStep?(.audio)
    }

    func stopAudio() {
        audioStops += 1
    }

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        stepsSeen.append(.recogniser)
        onStep?(.recogniser)
    }

    func cancelRecognition() {}
}

/// What the listener told the keyboard.
@MainActor
private final class ListenerLog {
    var heard: [String] = []
    var inserted: [String] = []
    var probes: [DictationKeyboardProbe] = []
    var runs: [DictationKeyboardMicRun] = []
    var attempts: [DictationKeyboardProbeAttempt?] = []
    var stoppedCount = 0
    var onInsert: (() -> Void)?

    func handlers() -> DictationKeyboardMicListener.Handlers {
        DictationKeyboardMicListener.Handlers(heard: recordHeard, insert: recordInsert, answered: recordProbe, inserted: recordRun,
                                              attemptChanged: recordAttempt, stoppedListening: recordStopped)
    }

    private func recordHeard(_ text: String) {
        heard.append(text)
    }

    private func recordInsert(_ text: String) -> Date {
        inserted.append(text)
        onInsert?()
        return Date()
    }

    private func recordProbe(_ probe: DictationKeyboardProbe) {
        probes.append(probe)
    }

    private func recordRun(_ run: DictationKeyboardMicRun) {
        runs.append(run)
    }

    private func recordAttempt(_ attempt: DictationKeyboardProbeAttempt?) {
        attempts.append(attempt)
    }

    private func recordStopped() {
        stoppedCount += 1
    }
}

@MainActor
final class DictationKeyboardMicTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_763_590_000)
    private let context = DictationKeyboardProbeContext(fullAccess: true, microphone: "granted", speech: "authorized", build: "34", ios: "27.1")
    private var temporaryFolder: URL!

    override func setUp() {
        super.setUp()
        temporaryFolder = FileManager.default.temporaryDirectory.appending(path: "dictation-keyboard-mic-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: temporaryFolder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: temporaryFolder)
        super.tearDown()
    }

    private func seconds(_ offset: TimeInterval) -> Date {
        startedAt.addingTimeInterval(offset)
    }

    private func attempt() -> DictationKeyboardProbeAttempt {
        DictationKeyboardProbeAttempt(id: "1763590000000-0001", startedAt: startedAt, context: context)
    }

    private func settingsValue(_ fields: [String: JSONValue]) -> JSONValue {
        .object(fields)
    }

    // MARK: The setting and the fallback

    func testKeyboardMicIsKeyboardUnlessSettingsSayApp() {
        XCTAssertEqual(DictationKeyboardMicMode.builtIn, .keyboard)
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: nil), .keyboard)
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: settingsValue([:])), .keyboard)
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: settingsValue(["keyboardMic": .string("app")])), .app)
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: settingsValue(["keyboardMic": .string("keyboard")])), .keyboard)
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: settingsValue(["keyboardMic": .string("phone")])), .keyboard)
        XCTAssertEqual(DictationKeyboardMicMode.from(settings: settingsValue(["keyboardMic": .number(1)])), .keyboard)
    }

    func testTheGateStillReadsSettingsThatCarryKeyboardMic() {
        guard case .object(var fields) = DictationGateSettings.builtIn.recordValue else {
            return XCTFail("built-in settings are not an object")
        }
        fields["fillers"] = .array([.string("um"), .string("er")])
        let withoutMode = DictationGateSettings.resolved(.object(fields))
        fields["keyboardMic"] = .string("app")
        let withMode = DictationGateSettings.resolved(.object(fields))
        XCTAssertTrue(withoutMode.isSaved)
        XCTAssertTrue(withMode.isSaved)
        XCTAssertEqual(withoutMode.settings.keyboardMic, .keyboard)
        XCTAssertEqual(withMode.settings.keyboardMic, .app)
        // Apart from the mode, the gate reads the same settings
        var sameApartFromMode = withMode.settings
        sameApartFromMode.keyboardMic = .keyboard
        XCTAssertEqual(sameApartFromMode, withoutMode.settings)
        fields["keyboardMic"] = .string("phone")
        XCTAssertFalse(DictationGateSettings.resolved(.object(fields)).isSaved)
        XCTAssertEqual(withMode.settings.fillers, ["um", "er"])
    }

    func testRouteTriesTheKeyboardFirstAndFallsBackToTheAppSwitch() {
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .keyboard, hasFullAccess: true, keyboardMicFailed: false), .keyboardMic)
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .keyboard, hasFullAccess: true, keyboardMicFailed: true), .app)
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .app, hasFullAccess: true, keyboardMicFailed: false), .app)
        XCTAssertEqual(DictationKeyboardMicRoute.route(mode: .app, hasFullAccess: true, keyboardMicFailed: true), .app)
        XCTAssertNil(DictationKeyboardMicRoute.route(mode: .keyboard, hasFullAccess: false, keyboardMicFailed: false))
        XCTAssertNil(DictationKeyboardMicRoute.route(mode: .app, hasFullAccess: false, keyboardMicFailed: false))
    }

    // MARK: The step-by-step result mapping

    func testStepsAreInOrderWithTheManifestsNames() {
        let names = DictationKeyboardProbeStep.allCases.map(\.rawValue)
        XCTAssertEqual(names, ["session-category", "activate", "engine-start", "audio", "recogniser"])
        XCTAssertEqual(DictationKeyboardProbeStep.engineStart.label, "engine start")
        XCTAssertEqual(DictationKeyboardProbeStep.sessionCategory.label, "session category")
    }

    func testNoWordsPointsAtTheAudioOrTheRecogniser() {
        let none = DictationKeyboardProbeAttempt.noWordsFailure(audio: DictationKeyboardAudioCount(buffers: 0, peak: 0))
        XCTAssertEqual(none.step, .audio)
        XCTAssertEqual(none.error, .noAudio)
        let zeros = DictationKeyboardProbeAttempt.noWordsFailure(audio: DictationKeyboardAudioCount(buffers: 80, peak: 0))
        XCTAssertEqual(zeros.step, .audio)
        XCTAssertEqual(zeros.error, .silentAudio)
        let sound = DictationKeyboardProbeAttempt.noWordsFailure(audio: DictationKeyboardAudioCount(buffers: 80, peak: 0.02))
        XCTAssertEqual(sound.step, .recogniser)
        XCTAssertEqual(sound.error, .noWords)
    }

    func testStartFailureKeepsTheEnginesStepAndIOSsError() {
        let iosError = NSError(domain: "NSOSStatusErrorDomain", code: -50, userInfo: [NSLocalizedDescriptionKey: "Bad param"])
        let engineFailure = (step: DictationKeyboardProbeStep.activate, error: DictationKeyboardProbeError(iosError))
        let mapped = DictationKeyboardProbeAttempt.startFailure(engineFailure: engineFailure, thrown: VoiceTranscriberError.audioFailed)
        XCTAssertEqual(mapped.step, .activate)
        XCTAssertEqual(mapped.error, DictationKeyboardProbeError(domain: "NSOSStatusErrorDomain", code: -50, message: "Bad param"))
        // No model is the recogniser, even with an older engine failure left over
        let noModel = DictationKeyboardProbeAttempt.startFailure(engineFailure: engineFailure, thrown: VoiceTranscriberError.onDeviceUnavailable)
        XCTAssertEqual(noModel.step, .recogniser)
        XCTAssertEqual(noModel.error, .noOnDeviceModel)
        let unknown = DictationKeyboardProbeAttempt.startFailure(engineFailure: nil, thrown: iosError)
        XCTAssertEqual(unknown.step, .engineStart)
        XCTAssertEqual(unknown.error.code, -50)
    }

    func testAnAttemptIOSEndedFailsAtTheLastStepReached() {
        var current = attempt()
        XCTAssertEqual(current.step, .sessionCategory)
        current.reached(.activate)
        current.reached(.engineStart)
        let probe = current.ended(at: seconds(3))
        XCTAssertEqual(probe.result, .failed)
        XCTAssertEqual(probe.step, .engineStart)
        XCTAssertEqual(probe.error, .keyboardEnded)
        XCTAssertEqual(probe.id, "1763590000000-0001")
        XCTAssertEqual(probe.at, seconds(3))
    }

    func testThePanelLineSaysWorksOrTheStepAndExactError() {
        let works = attempt().works(audio: DictationKeyboardAudioCount(buffers: 40, peak: 0.3), at: seconds(2))
        XCTAssertEqual(works.panelLine, "Mic in keyboard: works")
        let error = DictationKeyboardProbeError(domain: "com.apple.coreaudio.avfaudio", code: 561_145_187, message: "Session activation failed")
        let failed = attempt().failed(at: .activate, error: error, audio: .none, date: seconds(1))
        XCTAssertEqual(failed.panelLine, "Mic in keyboard: activate, com.apple.coreaudio.avfaudio 561145187: Session activation failed")
    }

    // MARK: The probe record

    func testAFailedProbeRecordCarriesTheStepTheErrorAndTheContext() {
        let error = DictationKeyboardProbeError(domain: "com.apple.coreaudio.avfaudio", code: -11800, message: String(repeating: "x", count: 500))
        let probe = attempt().failed(at: .engineStart, error: error, audio: DictationKeyboardAudioCount(buffers: 0, peak: 0), date: seconds(1.5))
        let value = DictationProbeRecord.value(probe)
        XCTAssertEqual(value["result"]?.stringValue, "failed")
        XCTAssertEqual(value["step"]?.stringValue, "engine-start")
        XCTAssertEqual(value["errorDomain"]?.stringValue, "com.apple.coreaudio.avfaudio")
        XCTAssertEqual(value["errorCode"]?.numberValue, -11800)
        XCTAssertEqual(value["errorMessage"]?.stringValue?.count, 400)
        XCTAssertEqual(value["fullAccess"], .bool(true))
        XCTAssertEqual(value["microphone"]?.stringValue, "granted")
        XCTAssertEqual(value["speech"]?.stringValue, "authorized")
        XCTAssertEqual(value["build"]?.stringValue, "34")
        XCTAssertEqual(value["ios"]?.stringValue, "27.1")
        XCTAssertEqual(value["buffers"]?.numberValue, 0)
        XCTAssertEqual(value["at"]?.stringValue, DictationProbeRecord.timestamp(seconds(1.5)))
    }

    func testAWorkingProbeRecordHasNoStepOrError() {
        let probe = attempt().works(audio: DictationKeyboardAudioCount(buffers: 212, peak: 1.7), at: seconds(2))
        let value = DictationProbeRecord.value(probe)
        XCTAssertEqual(value["result"]?.stringValue, "works")
        XCTAssertNil(value["step"])
        XCTAssertNil(value["errorDomain"])
        XCTAssertNil(value["errorCode"])
        XCTAssertNil(value["errorMessage"])
        XCTAssertEqual(value["buffers"]?.numberValue, 212)
        // The manifest's peak is 0 to 1
        XCTAssertEqual(value["peak"]?.numberValue, 1)
        XCTAssertEqual(DictationProbeRecord.keyPrefix, "probe:")
    }

    func testTheCenterSavesAProbeAsAProbeRecord() throws {
        let store = LocalRecordStore(fileURL: temporaryFolder.appending(path: "records.json"))
        let center = DictationTestCenter(store: store, device: DictationDeviceInfo(device: "iPhone17,1", ios: "27.1", build: "34"))
        let probe = attempt().works(audio: DictationKeyboardAudioCount(buffers: 9, peak: 0.2), at: seconds(4))
        center.saveProbe(probe)
        let saved = store.query(sidekickId: DictationRunRecord.sidekickId, keyPrefix: DictationProbeRecord.keyPrefix)
        XCTAssertEqual(saved.count, 1)
        let record = try XCTUnwrap(saved.first)
        XCTAssertTrue(record.key.hasPrefix("probe:"))
        XCTAssertEqual(record.value["result"]?.stringValue, "works")
        XCTAssertNil(center.lastSaveError)
        XCTAssertEqual(store.query(sidekickId: DictationRunRecord.sidekickId, keyPrefix: DictationRunRecord.keyPrefix).count, 0)
    }

    // MARK: The App Group files

    func testHandoffEncodingRoundTripsProbesAttemptsAndRuns() throws {
        var current = attempt()
        current.reached(.recogniser)
        let probe = current.failed(at: .recogniser, error: .noOnDeviceModel, audio: DictationKeyboardAudioCount(buffers: 3, peak: 0.1), date: seconds(1))
        let decodedProbe = DictationKeyboardHandoff.decode(DictationKeyboardProbe.self, from: try DictationKeyboardHandoff.encode(probe))
        XCTAssertEqual(decodedProbe, probe)
        let decodedAttempt = DictationKeyboardHandoff.decode(DictationKeyboardProbeAttempt.self, from: try DictationKeyboardHandoff.encode(current))
        XCTAssertEqual(decodedAttempt, current)
        XCTAssertEqual(decodedAttempt?.step, .recogniser)
        let run = try micRun(raw: "uh tell mom im on my way")
        let decodedRun = try XCTUnwrap(DictationKeyboardHandoff.decode(DictationKeyboardMicRun.self, from: try DictationKeyboardHandoff.encode(run)))
        XCTAssertEqual(decodedRun.id, run.id)
        XCTAssertEqual(decodedRun.raw, run.raw)
        XCTAssertEqual(decodedRun.text, run.text)
        XCTAssertEqual(decodedRun.path, run.path)
        XCTAssertEqual(decodedRun.matched, run.matched)
        XCTAssertEqual(decodedRun.gateMs, run.gateMs)
        XCTAssertEqual(decodedRun.thermal, run.thermal)
        // The handoff keeps dates to the millisecond
        XCTAssertEqual(decodedRun.endOfSpeechAt.timeIntervalSince1970, run.endOfSpeechAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decodedRun.rawFinalAt.timeIntervalSince1970, run.rawFinalAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(decodedRun.insertedAt.timeIntervalSince1970, run.insertedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testMailboxKeepsSettingsAndTheAttemptAndQueuesOneFilePerItem() throws {
        let mailbox = DictationKeyboardMailbox(folder: temporaryFolder)
        XCTAssertNil(mailbox.readSettings())
        let settings = settingsValue(["keyboardMic": .string("app")])
        try mailbox.writeSettings(settings)
        XCTAssertEqual(mailbox.readSettings(), settings)
        try mailbox.writeSettings(nil)
        XCTAssertNil(mailbox.readSettings())

        XCTAssertNil(mailbox.readProbeAttempt())
        mailbox.writeProbeAttempt(attempt())
        XCTAssertEqual(mailbox.readProbeAttempt(), attempt())
        mailbox.writeProbeAttempt(nil)
        XCTAssertNil(mailbox.readProbeAttempt())

        let later = attempt().works(audio: .none, at: seconds(5))
        let earlier = DictationKeyboardProbeAttempt(id: "1763589999000-0001", startedAt: startedAt, context: context).works(audio: .none, at: seconds(1))
        try mailbox.queue(later, id: later.id, in: DictationKeyboardMailbox.probesFolder)
        try mailbox.queue(earlier, id: earlier.id, in: DictationKeyboardMailbox.probesFolder)
        // A file nobody can read is dropped, not kept forever
        let probesFolder = temporaryFolder.appending(path: DictationKeyboardMailbox.probesFolder)
        try Data("not json".utf8).write(to: probesFolder.appending(path: "0000-broken.json"))
        let queued = mailbox.queued(DictationKeyboardProbe.self, in: DictationKeyboardMailbox.probesFolder)
        XCTAssertEqual(probeIds(queued), [earlier.id, later.id])
        XCTAssertFalse(FileManager.default.fileExists(atPath: probesFolder.appending(path: "0000-broken.json").path))
        mailbox.removeQueued(queued[0].file)
        let remaining = mailbox.queued(DictationKeyboardProbe.self, in: DictationKeyboardMailbox.probesFolder)
        XCTAssertEqual(probeIds(remaining), [later.id])
        XCTAssertTrue(mailbox.queued(DictationKeyboardMicRun.self, in: DictationKeyboardMailbox.keyboardRunsFolder).isEmpty)
    }

    private func probeIds(_ items: [(file: URL, value: DictationKeyboardProbe)]) -> [String] {
        var ids: [String] = []
        for item in items {
            ids.append(item.value.id)
        }
        return ids
    }

    // MARK: Runs the keyboard's microphone inserted

    private func micRun(raw: String) throws -> DictationKeyboardMicRun {
        let outcome = try XCTUnwrap(DictationKeyboardInsertText.make(raw: raw, settings: .builtIn))
        return DictationKeyboardMicRun(id: "1763590004000-0002", raw: raw, outcome: outcome, endOfSpeechAt: seconds(1), rawFinalAt: seconds(1.4),
                                       insertedAt: seconds(1.5), thermal: .fair)
    }

    func testAMicRunBecomesAKeyboardRunWithTheGatesPathAndTimes() throws {
        let micRunValue = try micRun(raw: "uh tell mom im on my way")
        let expectedText = try XCTUnwrap(DictationKeyboardInsertText.make(raw: "uh tell mom im on my way", settings: .builtIn)).text
        let run = try XCTUnwrap(DictationTestRuns.keyboard(micRun: micRunValue, modelStatus: "Available"))
        XCTAssertEqual(run.source, .keyboard)
        XCTAssertEqual(run.raw, "uh tell mom im on my way")
        XCTAssertEqual(run.cleaned, expectedText)
        XCTAssertEqual(run.path, .rule)
        XCTAssertEqual(run.matched, ["uh"])
        XCTAssertEqual(run.cleanupMs, 0)
        XCTAssertEqual(run.releaseToRawMs, 400)
        XCTAssertEqual(run.totalMs, 500)
        XCTAssertEqual(run.thermal, .fair)
        XCTAssertEqual(run.at, seconds(1.5))
    }

    func testAMicRunWithAPathThisBuildDoesNotKnowIsNotSaved() throws {
        let known = try micRun(raw: "send the deck to Priya by friday")
        var fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: DictationKeyboardHandoff.encode(known)) as? [String: Any])
        fields["path"] = "teleport"
        let data = try JSONSerialization.data(withJSONObject: fields)
        let unknown = try XCTUnwrap(DictationKeyboardHandoff.decode(DictationKeyboardMicRun.self, from: data))
        XCTAssertNil(DictationTestRuns.keyboard(micRun: unknown, modelStatus: "Available"))
        XCTAssertNotNil(DictationTestRuns.keyboard(micRun: known, modelStatus: "Available"))
    }

    // MARK: Midas Test saves what the keyboard queued

    func testTheSessionSavesQueuedProbesAndRunsOnceAndPublishesSettings() throws {
        let mailbox = DictationKeyboardMailbox(folder: temporaryFolder)
        var savedRuns: [DictationRun] = []
        var savedProbes: [DictationKeyboardProbe] = []
        let settings = settingsValue(["keyboardMic": .string("app")])
        func saveRun(_ run: DictationRun) {
            savedRuns.append(run)
        }
        func saveProbe(_ probe: DictationKeyboardProbe) {
            savedProbes.append(probe)
        }
        func currentSettings() -> DictationGateSettings {
            .builtIn
        }
        func storedSettings() -> JSONValue? {
            settings
        }
        let session = DictationKeyboardSession(settings: currentSettings, saveRun: saveRun, mailbox: mailbox, saveProbe: saveProbe, settingsValue: storedSettings)
        let probe = attempt().works(audio: DictationKeyboardAudioCount(buffers: 7, peak: 0.2), at: seconds(2))
        try mailbox.queue(probe, id: probe.id, in: DictationKeyboardMailbox.probesFolder)
        let run = try micRun(raw: "uh tell mom im on my way")
        try mailbox.queue(run, id: run.id, in: DictationKeyboardMailbox.keyboardRunsFolder)

        session.saveKeyboardRecords()
        XCTAssertEqual(savedProbes, [probe])
        XCTAssertEqual(savedRuns.count, 1)
        XCTAssertEqual(savedRuns.first?.source, .keyboard)
        XCTAssertEqual(savedRuns.first?.raw, "uh tell mom im on my way")
        // Saved once: the files are gone
        session.saveKeyboardRecords()
        XCTAssertEqual(savedProbes.count, 1)
        XCTAssertEqual(savedRuns.count, 1)

        session.publishSettingsToKeyboard()
        XCTAssertEqual(mailbox.readSettings(), settings)
    }

    // MARK: The keyboard's listener on a stand-in engine

    private func makeListener(engine: StandInMicEngine, log: ListenerLog) -> DictationKeyboardMicListener {
        func builtInSettings() -> DictationGateSettings {
            .builtIn
        }
        return DictationKeyboardMicListener(engine: engine, settings: builtInSettings, handlers: log.handlers())
    }

    func testAStepThatThrowsFailsTheAttemptAtThatStepWithIOSsError() async {
        let engine = StandInMicEngine()
        engine.failingStep = .activate
        let log = ListenerLog()
        let listener = makeListener(engine: engine, log: log)
        await listener.start(context: context)
        XCTAssertEqual(engine.stepsSeen, [.sessionCategory, .activate])
        XCTAssertEqual(log.probes.count, 1)
        let probe = log.probes[0]
        XCTAssertEqual(probe.result, .failed)
        XCTAssertEqual(probe.step, .activate)
        XCTAssertEqual(probe.error, DictationKeyboardProbeError(domain: "com.apple.coreaudio.avfaudio", code: 561_145_187, message: "Session activation failed"))
        XCTAssertEqual(probe.context, context)
        XCTAssertFalse(listener.isListening)
        XCTAssertFalse(listener.wantsListening)
        // The attempt was kept at each step, then cleared once answered
        var keptSteps: [DictationKeyboardProbeStep] = []
        for kept in log.attempts {
            if let kept {
                keptSteps.append(kept.step)
            }
        }
        XCTAssertEqual(keptSteps, [.sessionCategory, .sessionCategory, .activate])
        XCTAssertEqual(log.attempts.count, 4)
        XCTAssertNil(log.attempts.last ?? nil)
        XCTAssertTrue(log.inserted.isEmpty)
    }

    func testEngineStartFailureNamesEngineStart() async {
        let engine = StandInMicEngine()
        engine.failingStep = .engineStart
        let log = ListenerLog()
        let listener = makeListener(engine: engine, log: log)
        await listener.start(context: context)
        XCTAssertEqual(log.probes.first?.step, .engineStart)
        XCTAssertEqual(log.probes.first?.error?.code, 561_145_187)
    }

    func testNoOnDeviceModelFailsAtTheRecogniserBeforeTheMicrophone() async {
        let engine = StandInMicEngine()
        engine.isOnDeviceAvailable = false
        let log = ListenerLog()
        let listener = makeListener(engine: engine, log: log)
        await listener.start(context: context)
        XCTAssertEqual(engine.audioStarts, 0)
        XCTAssertEqual(log.probes.first?.step, .recogniser)
        XCTAssertEqual(log.probes.first?.error, .noOnDeviceModel)
    }

    func testFirstWordsAnswerWorksAndAPauseInsertsTheGatesTextThenListensAgain() async throws {
        let engine = StandInMicEngine()
        let log = ListenerLog()
        let listener = makeListener(engine: engine, log: log)
        await listener.start(context: context)
        XCTAssertTrue(listener.isListening)
        XCTAssertTrue(log.probes.isEmpty)
        XCTAssertEqual(engine.stepsSeen, [.sessionCategory, .activate, .engineStart, .audio, .recogniser])

        let inserted = expectation(description: "a pause inserts")
        log.onInsert = inserted.fulfill
        listener.transcriberForTests.receive(.heard(VoiceTranscript(text: "uh tell mom", words: [])))
        XCTAssertEqual(log.probes.map(\.result), [.works])
        XCTAssertEqual(log.probes.first?.audio, DictationKeyboardAudioCount(buffers: 120, peak: 0.4))
        listener.transcriberForTests.receive(.heard(VoiceTranscript(text: "uh tell mom im on my way", words: [])))
        XCTAssertEqual(log.heard, ["uh tell mom", "uh tell mom im on my way"])
        // 1 s of silence after the last new words
        await fulfillment(of: [inserted], timeout: 4)
        let expectedText = try XCTUnwrap(DictationKeyboardInsertText.make(raw: "uh tell mom im on my way", settings: .builtIn)).text
        XCTAssertEqual(log.inserted, [expectedText])
        XCTAssertEqual(log.runs.count, 1)
        XCTAssertEqual(log.runs.first?.path, "rule")
        XCTAssertEqual(log.runs.first?.raw, "uh tell mom im on my way")
        // Listening again, with no second probe
        for _ in 0..<50 where engine.audioStarts < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(engine.audioStarts, 2)
        XCTAssertTrue(listener.isListening)
        XCTAssertEqual(log.probes.count, 1)
        listener.stop()
    }

    func testStoppingWithNoWordsFailsAtTheAudioOrTheRecogniser() async {
        let cases: [(DictationKeyboardAudioCount, DictationKeyboardProbeStep, DictationKeyboardProbeError)] = [
            (DictationKeyboardAudioCount(buffers: 0, peak: 0), .audio, .noAudio),
            (DictationKeyboardAudioCount(buffers: 90, peak: 0), .audio, .silentAudio),
            (DictationKeyboardAudioCount(buffers: 90, peak: 0.05), .recogniser, .noWords),
        ]
        for (audio, step, error) in cases {
            let engine = StandInMicEngine()
            engine.audioCount = audio
            let log = ListenerLog()
            let listener = makeListener(engine: engine, log: log)
            await listener.start(context: context)
            listener.stop()
            XCTAssertTrue(log.probes.isEmpty, "no answer before the last words are in")
            // The recogniser's last (empty) words end the listen
            listener.transcriberForTests.receive(.heardFinal(VoiceTranscript.empty))
            XCTAssertEqual(log.probes.count, 1)
            XCTAssertEqual(log.probes.first?.step, step)
            XCTAssertEqual(log.probes.first?.error, error)
            XCTAssertEqual(log.probes.first?.audio, audio)
            XCTAssertTrue(log.inserted.isEmpty)
        }
    }

    func testWordsSaidBeforeStopStillGoIn() async throws {
        let engine = StandInMicEngine()
        let log = ListenerLog()
        let listener = makeListener(engine: engine, log: log)
        await listener.start(context: context)
        listener.transcriberForTests.receive(.heard(VoiceTranscript(text: "send the deck to Priya", words: [])))
        listener.stop()
        listener.transcriberForTests.receive(.heardFinal(VoiceTranscript(text: "send the deck to Priya by friday", words: [])))
        let expectedText = try XCTUnwrap(DictationKeyboardInsertText.make(raw: "send the deck to Priya by friday", settings: .builtIn)).text
        XCTAssertEqual(log.inserted, [expectedText])
        XCTAssertEqual(log.probes.map(\.result), [.works])
        XCTAssertFalse(listener.isListening)
        XCTAssertEqual(engine.audioStarts, 1)
    }

    func testARecogniserErrorBeforeWordsFailsAtTheRecogniserWithItsMessage() async {
        let engine = StandInMicEngine()
        let log = ListenerLog()
        let listener = makeListener(engine: engine, log: log)
        await listener.start(context: context)
        let recogniserError = DictationKeyboardProbeError(domain: "kAFAssistantErrorDomain", code: 1101, message: "Speech service unavailable")
        engine.lastRecogniserError = recogniserError
        listener.transcriberForTests.receive(.failedWith(VoiceFailure(domain: "kAFAssistantErrorDomain", code: 1101)))
        XCTAssertEqual(log.probes.count, 1)
        XCTAssertEqual(log.probes.first?.step, .recogniser)
        XCTAssertEqual(log.probes.first?.error, recogniserError)
        XCTAssertEqual(log.stoppedCount, 1)
        XCTAssertFalse(listener.wantsListening)
    }

    func testANewAppearanceIsANewAttempt() async {
        let engine = StandInMicEngine()
        engine.failingStep = .sessionCategory
        let log = ListenerLog()
        let listener = makeListener(engine: engine, log: log)
        await listener.start(context: context)
        // Same appearance: no second probe
        await listener.start(context: context)
        XCTAssertEqual(log.probes.count, 1)
        listener.reset()
        await listener.start(context: context)
        XCTAssertEqual(log.probes.count, 2)
        XCTAssertNotEqual(log.probes[0].id, log.probes[1].id)
    }
}
#endif
