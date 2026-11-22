#if MIDAS_TEST_BUILD
// The dictation session behind the Midas keyboard (TEST BUILD, founder 2026-11-14; branch
// agent/dictation-test, never merged; docs/briefs/dictation-keyboard-test.md). Compiled only in the
// Test configuration.
//
// A keyboard extension cannot record, so the microphone runs here. The keyboard's Start Dictation
// opens midastest://dictation; Midas Test turns the microphone on (background audio keeps it on
// after the person swipes back) and listens whenever the keyboard asks. Each pause (1 s of
// silence) runs the gate on the raw words and hands the text to the keyboard through the App
// Group (DictationKeyboardShared.swift). When the keyboard says it went in, the run is saved as a
// `dictation.run` record (source `keyboard`) by DictationTestCenter.save, like the test screen's.
// The session ends 5 minutes after the last use, or when Midas Test is swiped away.
//
// Build 34 (mic inside the keyboard, founder 2026-11-19): the keyboard may record itself
// (DictationKeyboardShared/DictationKeyboardMic.swift). This session also hands it settings:main
// (keyboardMic and the gate settings) through the App Group, and saves what it queued there: each
// attempt as a `dictation.probe`, each pause it inserted as a `dictation.run` (source keyboard).
//
// Build 35 (founder 2026-11-19): a queued probe is removed only once its record is stored (build
// 34 removed it even when the store refused it, which lost every probe on a phone whose Sidekick
// list predated the `probe:` type); an attempt the keyboard never answered is answered here once it
// is older than any listen; each keyboard run records its `mic`; the keyboard log is saved as
// `log:keyboard`.
//
// Build 40 (founder 2026-11-22): with keyboardMic "apple" the keyboard queues each Apple dictation
// it saw in `apple-runs/`; saved here as a `dictation.run` (source keyboard, mic apple).
import AVFoundation
import Foundation
import Observation
import Speech
import SwiftUI
import UIKit

/// The session's states and what each event leads to. Pure, so the tests drive it with fixed times.
struct DictationKeyboardSessionMachine: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// No session: the microphone is off.
        case off
        /// The microphone is on; nothing is being listened for.
        case live
        case listening
        /// The keyboard stopped listening; the last words are still being recognised.
        case finishing
    }

    /// What the session must do.
    enum Effect: Equatable, Sendable {
        case startMicrophone
        case startListening
        /// Stop the microphone feed and wait for the last words (they still go in).
        case finishListening
        /// Drop the listen without inserting (the session ended).
        case cancelListening
        case deliver(raw: String)
        case stopMicrophone
        case publishState
    }

    private(set) var phase: Phase = .off
    private(set) var lastUseAt: Date?
    private(set) var wantsListening = false
    /// The newest keyboard request acted on.
    private(set) var handledSeq = 0

    /// When the session ends unless it is used again; nil when off.
    var endsAt: Date? {
        guard phase != .off, let lastUseAt else {
            return nil
        }
        return lastUseAt.addingTimeInterval(DictationKeyboardConstants.sessionIdleTimeout)
    }

    /// Start Dictation in the keyboard opened Midas Test. A request the keyboard wrote just before
    /// is taken at once.
    mutating func start(at now: Date, pendingRequest: DictationKeyboardRequest? = nil) -> [Effect] {
        lastUseAt = now
        var effects: [Effect] = []
        if phase == .off {
            phase = .live
            effects.append(.startMicrophone)
        }
        if let pendingRequest {
            effects += request(pendingRequest, at: now)
        }
        if effects.last != .publishState {
            effects.append(.publishState)
        }
        return effects
    }

    /// The keyboard asked to listen or to stop. Older requests than the last one are ignored.
    mutating func request(_ request: DictationKeyboardRequest, at now: Date) -> [Effect] {
        guard request.seq > handledSeq else {
            return []
        }
        handledSeq = request.seq
        wantsListening = request.wantsListening
        // The keyboard learns from the state that there is no session
        guard phase != .off else {
            wantsListening = false
            return [.publishState]
        }
        lastUseAt = now
        switch phase {
        case .live where wantsListening:
            phase = .listening
            return [.startListening, .publishState]
        case .listening where !wantsListening:
            phase = .finishing
            return [.finishListening, .publishState]
        default:
            // Already as asked; finishing turns back to listening when its last words are in
            return [.publishState]
        }
    }

    /// New words were heard: the session is in use.
    mutating func heard(at now: Date) {
        guard phase == .listening else {
            return
        }
        lastUseAt = now
    }

    /// A listen ended (a pause, or the keyboard stopped it): its words go in, and listening starts
    /// again if the keyboard still wants it.
    mutating func listenEnded(raw: String, at now: Date) -> [Effect] {
        guard phase == .listening || phase == .finishing else {
            return []
        }
        var effects: [Effect] = []
        let hasWords = !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasWords {
            lastUseAt = now
            effects.append(.deliver(raw: raw))
        }
        if wantsListening {
            phase = .listening
            effects.append(.startListening)
        } else {
            phase = .live
        }
        effects.append(.publishState)
        return effects
    }

    /// The recogniser failed or could not start: what was heard still goes in; no new listen
    /// until the keyboard asks again (no loop of failures).
    mutating func listenFailed(raw: String, at now: Date) -> [Effect] {
        guard phase == .listening || phase == .finishing else {
            return []
        }
        wantsListening = false
        phase = .live
        let hasWords = !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasWords ? [.deliver(raw: raw), .publishState] : [.publishState]
    }

    /// Text went in: the session is in use.
    mutating func inserted(at now: Date) {
        guard phase != .off else {
            return
        }
        lastUseAt = now
    }

    /// Checked every few seconds: ends the session 5 minutes after the last use.
    mutating func tick(at now: Date) -> [Effect] {
        guard let endsAt, now >= endsAt else {
            return []
        }
        return end()
    }

    /// Ends the session (timeout, Midas Test swiped away, the microphone taken by a call).
    mutating func end() -> [Effect] {
        guard phase != .off else {
            return []
        }
        let wasListening = phase == .listening || phase == .finishing
        phase = .off
        wantsListening = false
        lastUseAt = nil
        let cancelling: [Effect] = wasListening ? [.cancelListening] : []
        return cancelling + [.stopMicrophone, .publishState]
    }

    /// What the keyboard reads.
    func state(heard: String, now: Date) -> DictationKeyboardState {
        let isListening = phase == .listening
        return DictationKeyboardState(live: phase != .off, listening: isListening, heard: isListening ? heard : "", handledSeq: handledSeq,
                                      updatedAt: now, endsAt: endsAt)
    }
}

/// Hands each microphone buffer to the listen that wants it, or drops it between listens. Set on
/// the main actor, read on iOS's audio thread.
final class DictationHotMicTapRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var storedTap: VoiceAudioTap?

    func set(_ tap: VoiceAudioTap?) {
        lock.withLock {
            storedTap = tap
        }
    }

    func forward(_ buffer: AVAudioPCMBuffer, _ time: AVAudioTime) {
        let tap = lock.withLock {
            storedTap
        }
        tap?(buffer, time)
    }
}

/// The microphone kept running for the whole session, so listening can start while Midas Test is
/// in the background (iOS does not let a background app start recording). The shared transcriber
/// drives it like the live engine; between listens the audio is dropped. Recognition is the live
/// engine's on-device recogniser.
@MainActor
final class DictationHotMicEngine: SpeechRecognitionEngine {
    private let audioEngine = AVAudioEngine()
    private let recognition = LiveSpeechRecognitionEngine()
    private let relay = DictationHotMicTapRelay()
    private(set) var isRunning = false

    var isOnDeviceAvailable: Bool {
        recognition.isOnDeviceAvailable
    }

    /// Turns the microphone on (in the foreground). Mixes with other audio so the app being typed
    /// in keeps its sound.
    func activate() throws {
        guard !isRunning else {
            return
        }
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker])
        try audioSession.setActive(true)
        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // No input (another app holds the microphone): installing a tap would raise, not throw
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw NSError(domain: "MidasAudioInput", code: Int(format.sampleRate))
        }
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeRelayTap(relay))
        audioEngine.prepare()
        try audioEngine.start()
        isRunning = true
        voiceLog.info("keyboard dictation: microphone on")
    }

    /// Runs on iOS's audio thread: no actor.
    nonisolated static func makeRelayTap(_ relay: DictationHotMicTapRelay) -> VoiceAudioTap {
        { buffer, time in
            relay.forward(buffer, time)
        }
    }

    func startAudio(tap: @escaping VoiceAudioTap) throws {
        try activate()
        relay.set(tap)
    }

    /// Between listens: the microphone stays on, its audio goes nowhere.
    func stopAudio() {
        relay.set(nil)
    }

    func startRecognition(request: SFSpeechAudioBufferRecognitionRequest, resultHandler: @escaping VoiceRecognitionHandler) {
        recognition.startRecognition(request: request, resultHandler: resultHandler)
    }

    func cancelRecognition() {
        recognition.cancelRecognition()
    }

    /// The session ended: the microphone off, the orange dot gone.
    func shutDown() {
        relay.set(nil)
        guard isRunning else {
            return
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        voiceLog.info("keyboard dictation: microphone off")
    }
}

/// One delivered text waiting for the keyboard to say it went in.
struct DictationKeyboardPendingRun: Equatable, Sendable {
    let raw: String
    let text: String
    let gate: DictationGateOutcome
    let endOfSpeechAt: Date
    let rawFinalAt: Date
}

/// The session: the machine's effects carried out with the microphone, the files and the records.
@MainActor
@Observable
final class DictationKeyboardSession {
    /// The microphone is on for the keyboard.
    private(set) var isLive = false
    /// "Swipe back to keep typing." on screen (from Start Dictation until Midas Test leaves).
    var showsSwipeBack = false
    /// Why the last start or listen failed; nil when it did not.
    private(set) var lastProblem: String?

    @ObservationIgnored private var machine = DictationKeyboardSessionMachine()
    @ObservationIgnored private let mailbox: DictationKeyboardMailbox?
    @ObservationIgnored private let microphone: DictationHotMicEngine
    @ObservationIgnored private let transcriber: OnDeviceSpeechTranscriber
    @ObservationIgnored private let settings: @MainActor () -> DictationGateSettings
    @ObservationIgnored private let saveRun: @MainActor (DictationRun) -> Void
    @ObservationIgnored private let saveProbe: @MainActor (DictationKeyboardProbe) throws -> Void
    @ObservationIgnored private let saveLog: @MainActor ([DictationKeyboardLogEntry]) throws -> Void
    /// The newest log line saved, so an unchanged log is not written again.
    @ObservationIgnored private var savedLogThrough: DictationKeyboardLogEntry?
    @ObservationIgnored private let settingsValue: @MainActor () -> JSONValue?
    @ObservationIgnored private var darwinObserver: DictationDarwinObserver?
    @ObservationIgnored private var systemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var idleTimer: Task<Void, Never>?
    /// The current listen's raw words, when they last changed and when the keyboard asked to stop.
    @ObservationIgnored private var heard = ""
    @ObservationIgnored private var lastWordsAt: Date?
    @ObservationIgnored private var stopAskedAt: Date?
    /// End of speech and final raw text of the listen that just ended, for its delivery.
    @ObservationIgnored private var endedListen: (endOfSpeechAt: Date, rawFinalAt: Date)?
    @ObservationIgnored private var pendingRuns: [String: DictationKeyboardPendingRun] = [:]
    @ObservationIgnored private var deliveryCounter = 0

    init(settings: @escaping @MainActor () -> DictationGateSettings, saveRun: @escaping @MainActor (DictationRun) -> Void,
         mailbox: DictationKeyboardMailbox? = DictationKeyboardMailbox.shared(appGroup: WidgetShared.appGroupIdentifier),
         saveProbe: @escaping @MainActor (DictationKeyboardProbe) throws -> Void = DictationKeyboardSession.dropProbe,
         settingsValue: @escaping @MainActor () -> JSONValue? = DictationKeyboardSession.noSettingsValue,
         saveLog: @escaping @MainActor ([DictationKeyboardLogEntry]) throws -> Void = DictationKeyboardSession.dropLog) {
        self.settings = settings
        self.saveRun = saveRun
        self.saveProbe = saveProbe
        self.saveLog = saveLog
        self.settingsValue = settingsValue
        self.mailbox = mailbox
        let microphone = DictationHotMicEngine()
        self.microphone = microphone
        self.transcriber = OnDeviceSpeechTranscriber(options: .keyboardDictation, engine: microphone)
        // A session from before a crash or a swipe-away is over
        publish()
        let names = [DictationKeyboardConstants.requestNotification, DictationKeyboardConstants.ackNotification,
                     DictationKeyboardConstants.keyboardRecordsNotification]
        darwinObserver = DictationDarwinObserver(names: names, handler: makeNotificationHandler())
        observeSystem()
    }

    static func dropProbe(_ probe: DictationKeyboardProbe) {}

    static func dropLog(_ entries: [DictationKeyboardLogEntry]) {}

    static func noSettingsValue() -> JSONValue? {
        nil
    }

    // MARK: Build 34, mic inside the keyboard

    /// settings:main as the keyboard reads it (keyboardMic and the gate settings). Called when
    /// Midas Test opens (after its sync) and when it leaves.
    func publishSettingsToKeyboard() {
        try? mailbox?.writeSettings(settingsValue())
    }

    /// The probes and runs the keyboard's own microphone queued: each saved once as a record, then
    /// its file removed. Called when Midas Test opens (before its sync) and when the keyboard says.
    func saveKeyboardRecords(now: Date = Date()) {
        guard let mailbox else {
            return
        }
        answerAbandonedAttempt(in: mailbox, now: now)
        for item in mailbox.queued(DictationKeyboardProbe.self, in: DictationKeyboardMailbox.probesFolder) {
            // Build 35: kept when the store refuses it (an old Sidekick list); tried again next time
            do {
                try saveProbe(item.value)
            } catch {
                lastProblem = "Can't Save Probe: \(error)"
                continue
            }
            mailbox.removeQueued(item.file)
        }
        let modelStatus = DictationModelStatus.current().label
        for item in mailbox.queued(DictationKeyboardMicRun.self, in: DictationKeyboardMailbox.keyboardRunsFolder) {
            if var run = DictationTestRuns.keyboard(micRun: item.value, modelStatus: modelStatus) {
                run.mic = .keyboard
                saveRun(run)
            }
            mailbox.removeQueued(item.file)
        }
        // Build 40: each Apple dictation the keyboard saw and cleaned up (or skipped)
        for item in mailbox.queued(DictationAppleRun.self, in: DictationAppleConstants.runsFolder) {
            saveRun(DictationTestRuns.keyboard(appleRun: item.value, modelStatus: modelStatus))
            mailbox.removeQueued(item.file)
        }
        saveKeyboardLog(from: mailbox)
    }

    /// An attempt the keyboard left and never came back to answer (iOS ended it while it waited
    /// for words): answered here as ended at its last step, once no listen can still be running.
    private func answerAbandonedAttempt(in mailbox: DictationKeyboardMailbox, now: Date) {
        guard let attempt = mailbox.readProbeAttempt(), attempt.isAbandoned(now: now) else {
            return
        }
        let probe = attempt.ended(at: now)
        do {
            try mailbox.queue(probe, id: probe.id, in: DictationKeyboardMailbox.probesFolder)
            mailbox.writeProbeAttempt(nil)
        } catch {
            lastProblem = "Can't Queue Probe: \(error)"
        }
    }

    /// The keyboard's ring log as `log:keyboard`, when it has lines not saved yet.
    private func saveKeyboardLog(from mailbox: DictationKeyboardMailbox) {
        let entries = mailbox.readLog()
        guard let newest = entries.last, newest != savedLogThrough else {
            return
        }
        do {
            try saveLog(entries)
            savedLogThrough = newest
        } catch {
            lastProblem = "Can't Save Keyboard Log: \(error)"
        }
    }

    private func makeNotificationHandler() -> @MainActor @Sendable (String) -> Void {
        { [weak self] name in
            self?.notified(name)
        }
    }

    /// Midas Test swiped away, or a call took the microphone: the session ends.
    private func observeSystem() {
        let center = NotificationCenter.default
        let terminate = center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main, using: makeEndObserver())
        let interruption = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main, using: makeInterruptionObserver())
        systemObservers = [terminate, interruption]
    }

    private func makeEndObserver() -> @Sendable (Notification) -> Void {
        { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endSession()
            }
        }
    }

    private func makeInterruptionObserver() -> @Sendable (Notification) -> Void {
        { [weak self] notification in
            let typeNumber = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = typeNumber == AVAudioSession.InterruptionType.began.rawValue
            guard began else {
                return
            }
            MainActor.assumeIsolated {
                self?.endSession()
            }
        }
    }

    // MARK: Events

    /// midastest://dictation: the keyboard's Start Dictation.
    func startFromKeyboardLink() {
        showsSwipeBack = true
        lastProblem = nil
        Task { @MainActor in
            await startSession()
        }
    }

    private func startSession() async {
        let permission = await VoicePermissions.askAtLaunch()
        guard permission == .granted else {
            lastProblem = "Microphone or Speech Recognition Off"
            return
        }
        let now = Date()
        apply(machine.start(at: now, pendingRequest: recentRequest(now: now)))
        startIdleTimer()
        // Build 35: what the keyboard queued while Midas Test was not running (its wake-up was lost)
        saveKeyboardRecords(now: now)
    }

    /// The keyboard's request written just before it opened Midas Test; an old one is ignored, so a
    /// keyboard long gone does not start a listen.
    private func recentRequest(now: Date) -> DictationKeyboardRequest? {
        guard let request = mailbox?.readRequest() else {
            return nil
        }
        let age = now.timeIntervalSince(request.at)
        return age < 60 ? request : nil
    }

    /// Midas Test went to the background: the swipe-back line has done its job.
    func appLeftForeground() {
        showsSwipeBack = false
    }

    func endSession() {
        apply(machine.end())
    }

    private func notified(_ name: String) {
        switch name {
        case DictationKeyboardConstants.requestNotification:
            guard let request = mailbox?.readRequest() else {
                return
            }
            apply(machine.request(request, at: Date()))
        case DictationKeyboardConstants.ackNotification:
            saveInsertedRuns()
        case DictationKeyboardConstants.keyboardRecordsNotification:
            saveKeyboardRecords()
        default:
            break
        }
    }

    // MARK: Effects

    private func apply(_ effects: [DictationKeyboardSessionMachine.Effect]) {
        for effect in effects {
            perform(effect)
        }
        isLive = machine.phase != .off
    }

    private func perform(_ effect: DictationKeyboardSessionMachine.Effect) {
        switch effect {
        case .startMicrophone:
            startMicrophone()
        case .startListening:
            beginListening()
        case .finishListening:
            stopAskedAt = Date()
            transcriber.stopAndAwaitFinal()
        case .cancelListening:
            transcriber.stop()
        case .deliver(let raw):
            deliver(raw)
        case .stopMicrophone:
            microphone.shutDown()
            idleTimer?.cancel()
            idleTimer = nil
        case .publishState:
            publish()
        }
    }

    private func startMicrophone() {
        do {
            try microphone.activate()
        } catch {
            lastProblem = "Can't Start Microphone: \(VoiceFailure(error).summary)"
            apply(machine.end())
        }
    }

    private func beginListening() {
        heard = ""
        lastWordsAt = nil
        stopAskedAt = nil
        let listenStartedAt = Date()
        Task { @MainActor in
            await startTranscriber(at: listenStartedAt)
        }
    }

    private func startTranscriber(at listenStartedAt: Date) async {
        do {
            try await transcriber.start(sessionStartedAt: listenStartedAt, onUpdate: heardWords, onEnd: listenEnded)
        } catch {
            lastProblem = "Can't Listen: \(error)"
            apply(machine.listenFailed(raw: "", at: Date()))
            return
        }
        // The keyboard changed its mind while the recogniser was starting
        switch machine.phase {
        case .finishing:
            stopAskedAt = stopAskedAt ?? Date()
            transcriber.stopAndAwaitFinal()
        case .off, .live:
            transcriber.stop()
        case .listening:
            break
        }
    }

    private func heardWords(_ transcript: VoiceTranscript) {
        guard transcript.text != heard else {
            return
        }
        heard = transcript.text
        lastWordsAt = Date()
        machine.heard(at: Date())
        publish()
    }

    private func listenEnded(_ reason: VoiceTranscriptionEnd) {
        let rawFinalAt = Date()
        let raw = heard
        heard = ""
        // A pause: speech ended with the last new words. Stopped by the keyboard: when it asked.
        let endOfSpeechAt: Date
        switch reason {
        case .silence:
            endOfSpeechAt = lastWordsAt ?? rawFinalAt
        default:
            endOfSpeechAt = stopAskedAt ?? lastWordsAt ?? rawFinalAt
        }
        endedListen = (endOfSpeechAt, rawFinalAt)
        if reason == .failed {
            let failure = transcriber.lastFailure?.summary ?? "no details"
            lastProblem = "Recogniser Failed: \(failure)"
            apply(machine.listenFailed(raw: raw, at: rawFinalAt))
        } else {
            apply(machine.listenEnded(raw: raw, at: rawFinalAt))
        }
    }

    /// The gate on the raw words; the text goes to the keyboard and waits for its ack.
    private func deliver(_ raw: String) {
        guard let outcome = DictationKeyboardInsertText.make(raw: raw, settings: settings()), let mailbox else {
            return
        }
        let now = Date()
        let timing = endedListen ?? (endOfSpeechAt: now, rawFinalAt: now)
        deliveryCounter += 1
        let millisecondsNow = Int((now.timeIntervalSince1970 * 1000).rounded(.down))
        let deliveryId = "\(millisecondsNow)-\(deliveryCounter)"
        let delivery = DictationKeyboardDelivery(id: deliveryId, text: outcome.text, endOfSpeechAt: timing.endOfSpeechAt, deliveredAt: now)
        pendingRuns[deliveryId] = DictationKeyboardPendingRun(raw: raw, text: outcome.text, gate: outcome.gate, endOfSpeechAt: timing.endOfSpeechAt,
                                                              rawFinalAt: timing.rawFinalAt)
        do {
            try mailbox.writeDelivery(delivery)
            DictationKeyboardDarwin.post(DictationKeyboardConstants.deliveryNotification)
        } catch {
            lastProblem = "Can't Hand Over Text: \(error)"
        }
    }

    /// The keyboard inserted text: each waiting run is saved once, as a `dictation.run` record.
    private func saveInsertedRuns() {
        guard let mailbox else {
            return
        }
        for ack in mailbox.readAcks() {
            guard let pending = pendingRuns.removeValue(forKey: ack.id) else {
                continue
            }
            machine.inserted(at: ack.insertedAt)
            var run = DictationTestRuns.keyboard(raw: pending.raw, inserted: pending.text, gate: pending.gate, endOfSpeechAt: pending.endOfSpeechAt,
                                                 rawFinalAt: pending.rawFinalAt, insertedAt: ack.insertedAt,
                                                 modelStatus: DictationModelStatus.current().label, thermal: .current())
            // Build 35: Midas Test's microphone heard it
            run.mic = .app
            saveRun(run)
        }
    }

    private func publish() {
        guard let mailbox else {
            return
        }
        let state = machine.state(heard: heard, now: Date())
        try? mailbox.writeState(state)
        DictationKeyboardDarwin.post(DictationKeyboardConstants.stateNotification)
    }

    private func startIdleTimer() {
        idleTimer?.cancel()
        idleTimer = Task { @MainActor [weak self] in
            await self?.runIdleTimer()
        }
    }

    // Every 10 s while the session is live; the background audio keeps Midas Test running
    private func runIdleTimer() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else {
                return
            }
            apply(machine.tick(at: Date()))
            if machine.phase == .off {
                return
            }
        }
    }
}

/// Shown after Start Dictation: jess's orb listening and one line. A tap closes it.
struct DictationKeyboardSwipeBackView: View {
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            JessOrb(state: .listening)
                .frame(width: 120, height: 120)
            Text(DictationKeyboardConstants.swipeBackLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .onTapGesture(perform: onClose)
    }
}

/// Puts the swipe-back screen over everything while the session asks for it.
struct DictationKeyboardSwipeBackOverlay: ViewModifier {
    let session: DictationKeyboardSession

    func body(content: Content) -> some View {
        content.overlay {
            if session.showsSwipeBack {
                DictationKeyboardSwipeBackView(onClose: closeSwipeBack)
                    .transition(.opacity)
            }
        }
    }

    private func closeSwipeBack() {
        session.showsSwipeBack = false
    }
}

extension View {
    func dictationKeyboardSwipeBack(_ session: DictationKeyboardSession) -> some View {
        modifier(DictationKeyboardSwipeBackOverlay(session: session))
    }
}
#endif
