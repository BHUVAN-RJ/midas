// The Midas keyboard's model (TEST BUILD, founder 2026-11-14; branch agent/dictation-test, never
// merged; docs/briefs/dictation-keyboard-test.md). Pages and keys come from DictationKeyboardLayout
// (shared with the app, so its tests cover them); this file carries out their effects: typing
// through the text proxy, and asking Midas Test to listen through the App Group.
//
// Build 34 (founder 2026-11-19): with settings:main keyboardMic "keyboard" (the default) the
// keyboard first tries its own microphone (DictationKeyboardMicListener); the attempt's answer is
// the one line on the listening panel and a dictation.probe the app saves. A failed attempt falls
// back to asking Midas Test, as in build 33.
import Foundation
import Observation

/// What the keyboard needs from its view controller.
@MainActor
protocol MidasKeyboardHost: AnyObject {
    var contextBeforeInput: String? { get }
    func insertText(_ text: String)
    func deleteBackward()
    func advanceToNextKeyboard()
    /// Opens Midas Test at midastest://dictation.
    func openStartURL()
}

@MainActor
@Observable
final class MidasKeyboardModel {
    private(set) var layout: DictationKeyboardLayout
    private(set) var panel: DictationKeyboardPanel = .connecting
    /// iOS draws no 🌐 on this phone (Home button iPhones): the keyboard shows its own.
    var needsGlobeKey = false
    /// "Mic in keyboard: works" or "Mic in keyboard: <step>, <error>" (build 34, while testing).
    private(set) var micLine: String?

    @ObservationIgnored weak var host: MidasKeyboardHost?
    @ObservationIgnored private let mailbox: DictationKeyboardMailbox?
    @ObservationIgnored private var lastRequest: DictationKeyboardRequest?
    @ObservationIgnored private var darwinObserver: DictationDarwinObserver?
    @ObservationIgnored private var answerCheck: Task<Void, Never>?
    @ObservationIgnored private var insertedFlash: Task<Void, Never>?
    @ObservationIgnored private var lastShiftTapAt: Date?
    // Build 34: the keyboard's own microphone
    @ObservationIgnored private let hasFullAccess: Bool
    @ObservationIgnored private var micMode: DictationKeyboardMicMode = .builtIn
    @ObservationIgnored private var gateSettings: DictationGateSettings = .builtIn
    @ObservationIgnored private var keyboardMicFailed = false
    @ObservationIgnored private var listener: DictationKeyboardMicListener?
    @ObservationIgnored private var micHeard = ""
    @ObservationIgnored private var isShown = false

    init(hasFullAccess: Bool, appGroup: String) {
        self.hasFullAccess = hasFullAccess
        layout = DictationKeyboardLayout(hasFullAccess: hasFullAccess)
        // Without Full Access the App Group is closed to the keyboard: letters only
        mailbox = hasFullAccess ? DictationKeyboardMailbox.shared(appGroup: appGroup) : nil
        guard mailbox != nil else {
            return
        }
        let names = [DictationKeyboardConstants.stateNotification, DictationKeyboardConstants.deliveryNotification]
        darwinObserver = DictationDarwinObserver(names: names, handler: makeNotificationHandler())
    }

    private func makeNotificationHandler() -> @MainActor @Sendable (String) -> Void {
        { [weak self] name in
            self?.notified(name)
        }
    }

    // MARK: Showing and hiding

    func appeared() {
        isShown = true
        prepareKeyboardMic()
        perform(layout.appeared())
        insertWaitingDelivery()
        layout.autoCapitalize(before: host?.contextBeforeInput)
    }

    func disappeared() {
        perform(layout.disappeared())
        isShown = false
        answerCheck?.cancel()
    }

    /// The text around the cursor changed (typing, or the host moved the cursor).
    func textChanged() {
        layout.autoCapitalize(before: host?.contextBeforeInput)
    }

    // MARK: Keys

    func tap(_ control: DictationKeyboardControl) {
        var resolved = control
        // Shift tapped twice within 0.3 s locks capitals
        if control == .shift {
            let now = Date()
            if let lastShiftTapAt, now.timeIntervalSince(lastShiftTapAt) < 0.3 {
                resolved = .shiftLock
                self.lastShiftTapAt = nil
            } else {
                lastShiftTapAt = now
            }
        }
        perform(layout.handle(resolved))
        let typed: Bool
        switch control {
        case .character, .space, .backspace, .returnKey:
            typed = true
        default:
            typed = false
        }
        if typed {
            layout.autoCapitalize(before: host?.contextBeforeInput)
        }
    }

    /// Start Dictation: ask to listen, then open Midas Test to turn the microphone on.
    func startDictation() {
        sendRequest(wantsListening: true)
        host?.openStartURL()
    }

    /// The orb while idle: listen again.
    func listenAgain() {
        startListening()
    }

    private func perform(_ effects: [DictationKeyboardEffect]) {
        for effect in effects {
            switch effect {
            case .startListening:
                startListening()
            case .stopListening:
                stopListening()
            case .nextKeyboard:
                host?.advanceToNextKeyboard()
            case .insert(let text):
                host?.insertText(text)
            case .deleteBackward:
                host?.deleteBackward()
            }
        }
    }

    // MARK: Which microphone

    private var route: DictationKeyboardMicRoute? {
        DictationKeyboardMicRoute.route(mode: micMode, hasFullAccess: hasFullAccess, keyboardMicFailed: keyboardMicFailed)
    }

    private func startListening() {
        switch route {
        case .keyboardMic:
            startKeyboardMic()
        case .app:
            sendRequest(wantsListening: true)
        case nil:
            break
        }
    }

    private func stopListening() {
        switch route {
        case .keyboardMic:
            listener?.stop()
            refreshPanel()
        case .app:
            sendRequest(wantsListening: false)
        case nil:
            break
        }
    }

    // MARK: The keyboard's own microphone (build 34)

    /// Each appearance: the synced setting and gate settings, a new attempt, and the answer for an
    /// attempt iOS ended last time.
    private func prepareKeyboardMic() {
        guard let mailbox else {
            return
        }
        let settingsValue = mailbox.readSettings()
        micMode = DictationKeyboardMicMode.from(settings: settingsValue)
        gateSettings = DictationGateSettings.resolved(settingsValue).settings
        keyboardMicFailed = false
        micHeard = ""
        listener?.reset()
        // The line answers this appearance's attempt, not the last one's
        micLine = nil
        if let leftOver = mailbox.readProbeAttempt() {
            mailbox.writeProbeAttempt(nil)
            let probe = leftOver.ended(at: Date())
            micLine = probe.panelLine
            queueKeyboardRecord(probe, id: probe.id, in: DictationKeyboardMailbox.probesFolder)
        }
    }

    private func startKeyboardMic() {
        let micListener = listener ?? makeListener()
        listener = micListener
        micHeard = ""
        panel = .listening(heard: "")
        let context = DictationKeyboardProbeContext.current(fullAccess: hasFullAccess)
        Task { @MainActor in
            await micListener.start(context: context)
        }
    }

    private func makeListener() -> DictationKeyboardMicListener {
        let handlers = DictationKeyboardMicListener.Handlers(heard: makeHeardHandler(), insert: makeInsertHandler(), answered: makeAnswerHandler(),
                                                             inserted: makeRunHandler(), attemptChanged: makeAttemptHandler(),
                                                             stoppedListening: makeStoppedHandler())
        return DictationKeyboardMicListener(engine: DictationKeyboardLiveMicEngine(), settings: makeSettingsReader(), handlers: handlers)
    }

    private func makeSettingsReader() -> @MainActor () -> DictationGateSettings {
        { [weak self] in
            self?.gateSettings ?? .builtIn
        }
    }

    private func makeHeardHandler() -> @MainActor (String) -> Void {
        { [weak self] heard in
            self?.micHeard = heard
            self?.refreshPanel()
        }
    }

    private func makeInsertHandler() -> @MainActor (String) -> Date {
        { [weak self] text in
            self?.insertDictated(text)
            return Date()
        }
    }

    private func makeAnswerHandler() -> @MainActor (DictationKeyboardProbe) -> Void {
        { [weak self] probe in
            self?.answered(probe)
        }
    }

    private func makeRunHandler() -> @MainActor (DictationKeyboardMicRun) -> Void {
        { [weak self] run in
            self?.queueKeyboardRecord(run, id: run.id, in: DictationKeyboardMailbox.keyboardRunsFolder)
        }
    }

    private func makeAttemptHandler() -> @MainActor (DictationKeyboardProbeAttempt?) -> Void {
        { [weak self] attempt in
            self?.mailbox?.writeProbeAttempt(attempt)
        }
    }

    private func makeStoppedHandler() -> @MainActor () -> Void {
        { [weak self] in
            self?.refreshPanel()
        }
    }

    private func insertDictated(_ text: String) {
        guard let host else {
            return
        }
        host.insertText(DictationKeyboardSpacing.textToInsert(text, before: host.contextBeforeInput))
        flashInserted()
    }

    /// The line shows the answer; a failure falls back to Midas Test while still listening.
    private func answered(_ probe: DictationKeyboardProbe) {
        micLine = probe.panelLine
        queueKeyboardRecord(probe, id: probe.id, in: DictationKeyboardMailbox.probesFolder)
        guard probe.result == .failed else {
            return
        }
        keyboardMicFailed = true
        if isShown && layout.page == .listening {
            sendRequest(wantsListening: true)
        } else {
            refreshPanel()
        }
    }

    private func queueKeyboardRecord<Value: Encodable>(_ value: Value, id: String, in folderName: String) {
        guard let mailbox else {
            return
        }
        try? mailbox.queue(value, id: id, in: folderName)
        DictationKeyboardDarwin.post(DictationKeyboardConstants.keyboardRecordsNotification)
    }

    // MARK: Midas Test

    private func sendRequest(wantsListening: Bool) {
        guard let mailbox else {
            return
        }
        let request = DictationKeyboardRequest.next(wantsListening: wantsListening, at: Date(), previousSeq: lastRequest?.seq ?? 0)
        lastRequest = request
        try? mailbox.writeRequest(request)
        DictationKeyboardDarwin.post(DictationKeyboardConstants.requestNotification)
        refreshPanel()
        scheduleAnswerCheck()
    }

    // No answer within the timeout means no session: the panel shows Start Dictation
    private func scheduleAnswerCheck() {
        answerCheck?.cancel()
        let waitMilliseconds = Int(DictationKeyboardConstants.answerTimeout * 1000) + 50
        answerCheck = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(waitMilliseconds))
            guard !Task.isCancelled else {
                return
            }
            self?.refreshPanel()
        }
    }

    private func notified(_ name: String) {
        switch name {
        case DictationKeyboardConstants.stateNotification:
            refreshPanel()
        case DictationKeyboardConstants.deliveryNotification:
            insertWaitingDelivery()
        default:
            break
        }
    }

    private func refreshPanel() {
        guard insertedFlash == nil else {
            return
        }
        if route == .keyboardMic {
            let listening = listener?.wantsListening ?? false
            panel = listening ? .listening(heard: micHeard) : .idle
            return
        }
        panel = DictationKeyboardPanel.from(state: mailbox?.readState(), request: lastRequest, now: Date())
    }

    /// The app's text for the last pause, with a space before it when needed; then the ack the app
    /// saves the run on.
    private func insertWaitingDelivery() {
        guard let mailbox, let host, let delivery = mailbox.readDelivery() else {
            return
        }
        let now = Date()
        guard DictationKeyboardHandoff.shouldInsert(delivery, acks: mailbox.readAcks(), now: now) else {
            return
        }
        let text = DictationKeyboardSpacing.textToInsert(delivery.text, before: host.contextBeforeInput)
        host.insertText(text)
        let ack = DictationKeyboardAck(id: delivery.id, insertedAt: Date())
        try? mailbox.appendAck(ack)
        DictationKeyboardDarwin.post(DictationKeyboardConstants.ackNotification)
        flashInserted()
    }

    // The orb's core goes green for a moment, then back to what the app says
    private func flashInserted() {
        guard layout.page == .listening else {
            return
        }
        insertedFlash?.cancel()
        panel = .inserted
        insertedFlash = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            self?.insertedFlash = nil
            self?.refreshPanel()
        }
    }
}
