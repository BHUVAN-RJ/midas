// The Midas keyboard's model (TEST BUILD, founder 2026-11-14; branch agent/dictation-test, never
// merged; docs/briefs/dictation-keyboard-test.md). Pages and keys come from DictationKeyboardLayout
// (shared with the app, so its tests cover them); this file carries out their effects: typing
// through the text proxy, and asking Midas Test to listen through the App Group.
//
// Build 34 (founder 2026-11-19): with settings:main keyboardMic "keyboard" (the default) the
// keyboard first tries its own microphone (DictationKeyboardMicListener); the attempt's answer is
// the one line on the listening panel and a dictation.probe the app saves. A failed attempt falls
// back to asking Midas Test, as in build 33.
//
// Build 35 (founder 2026-11-19): keyboardMic "keyboard-only" never opens Midas Test and never falls
// back (a failure shows its exact error where Start Dictation would be); a large KEYBOARD MIC or
// APP MIC label says which microphone records; every step goes into the keyboard log in the App
// Group (DictationKeyboardLog.swift), which Midas Test saves as log:keyboard.
//
// Build 40 (founder 2026-11-22): keyboardMic "apple" uses Apple's own dictation (iOS's 🎙 under the
// keyboard). The keyboard never records and never opens Midas Test; it reads every public signal
// (the input mode, textWillChange / textDidChange, the text around the cursor every 150 ms, showing
// and hiding), shows the dictated words with jess's orb and APPLE MIC while Apple types, and when
// dictation ends replaces the dictated span with the gate's text (DictationKeyboardApple.swift).
//
// Build 41 (founder 2026-11-22): in "apple" mode the keyboard is numbers first, like Wispr Flow (a
// top bar with undo and, while Apple listens, ✕ cancel; numbers and symbols; ABC · space · return,
// ABC going to the next keyboard). Apple's key sounds and a light haptic on every key, a soft one
// when listening starts and when the cleaned text lands; ✕ deletes what the running dictation
// typed; undo takes back the last cleanup or cancel (DictationKeyboardExperience.swift).
import Foundation
import Observation

/// What the keyboard needs from its view controller.
@MainActor
protocol MidasKeyboardHost: AnyObject {
    var contextBeforeInput: String? { get }
    /// Build 40: the text after the cursor (dictation leaves it as it is; the cursor moving does not).
    var contextAfterInput: String? { get }
    /// Build 40: the host document's identity, to tell the same text field from another one.
    var documentIdentifier: UUID { get }
    /// Build 40: the input mode's primary language ("dictation" while Apple dictates, if iOS says so).
    var inputModeLanguage: String? { get }
    /// Build 40, for the keyboard log: the input modes and hasDictationKey.
    var signalDetail: String { get }
    func insertText(_ text: String)
    func deleteBackward()
    func advanceToNextKeyboard()
    /// Opens Midas Test at midastest://dictation.
    func openStartURL()
    /// Build 41: plays a key's or a moment's sound and haptic.
    func playFeedback(_ plan: DictationKeyboardFeedbackPlan)
    /// Build 41, for the keyboard log: the input view's enableInputClicksWhenVisible.
    var inputClicksEnabled: Bool { get }
    /// Build 41, for the keyboard log: UIAccessibility.isReduceMotionEnabled.
    var reduceMotion: Bool { get }
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
    /// Build 35: KEYBOARD MIC or APP MIC, whichever records now; nil without Full Access.
    private(set) var micLabel: String?
    /// Build 35, keyboard-only: the exact error, shown where Start Dictation would be.
    private(set) var micError: String?
    /// Build 40, apple: "Tap 🎙 below" until Apple's dictation is seen.
    private(set) var panelHint: String?
    /// Build 41: the numbers-first keyboard (keyboardMic "apple").
    private(set) var usesNumbersLayout = false
    private(set) var numbersLayout = DictationNumbersLayout()
    /// Build 41: the last cleanups and cancels, for the undo key.
    private(set) var undo = DictationKeyboardUndo()
    /// Build 41: the words on the listening view (Apple's so far; the cleaned text as it lands).
    private(set) var appleWords = ""

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
    /// The attempt step last written to the log, so each step is logged once.
    @ObservationIgnored private var loggedStep: DictationKeyboardProbeStep?
    // Build 40: Apple's dictation
    @ObservationIgnored private var appleTracker = DictationAppleTracker()
    @ObservationIgnored private var applePoll: Task<Void, Never>?
    /// Whether the tracker has a baseline from this keyboard process (the first appearance has none).
    @ObservationIgnored private var appleTrackerPrimed = false
    @ObservationIgnored private var lastInputModeLanguage: String?
    /// The signals already logged in the running dictation (each logged once, then counted).
    @ObservationIgnored private var appleSignalsLogged: Set<DictationAppleSignal> = []
    /// The document and when the keyboard went away, to tell the same field when it comes back.
    @ObservationIgnored private var hiddenDocument: UUID?
    @ObservationIgnored private var hiddenAt: Date?
    @ObservationIgnored private var appleCounter = 0
    // Build 41: what Apple's dictation does after ✕ (logged for 3 s)
    @ObservationIgnored private var cancelWatchUntil: Date?
    @ObservationIgnored private var cancelWatchStartedAt: Date?
    @ObservationIgnored private var cancelWatchLines = 0
    @ObservationIgnored private var cancelWatchContext: String?
    @ObservationIgnored private var cancelWatchLanguage: String?

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
        logAppeared()
        prepareKeyboardMic()
        logRoute()
        usesNumbersLayout = isAppleMode
        numbersLayout.appeared()
        logFeedbackAvailability()
        appleAppeared()
        perform(layout.appeared())
        insertWaitingDelivery()
        layout.autoCapitalize(before: host?.contextBeforeInput)
    }

    func disappeared() {
        // Build 35: not shown before listening stops, so an answer that comes while the keyboard
        // goes away never asks Midas Test to listen (build 34 did)
        isShown = false
        // Build 41: the next appearance may be another text field
        undo.clear()
        cancelWatchUntil = nil
        perform(layout.disappeared())
        answerCheck?.cancel()
        appleDisappeared()
        log("disappeared", DictationKeyboardLog.memoryDetail())
        DictationKeyboardDarwin.post(DictationKeyboardConstants.keyboardRecordsNotification)
    }

    // MARK: The keyboard log (build 35)

    /// One line in the App Group's ring log; a line that cannot be written is dropped.
    private func log(_ event: String, _ detail: String) {
        guard let mailbox else {
            return
        }
        let entry = DictationKeyboardLogEntry(at: Date(), event: event, detail: detail)
        try? mailbox.appendLog(entry)
    }

    private func logAppeared() {
        let context = DictationKeyboardProbeContext.current(fullAccess: hasFullAccess)
        let detail = "full access " + (hasFullAccess ? "on" : "off") + ", microphone " + context.microphone + ", speech " + context.speech
            + ", build " + context.build + ", iOS " + context.ios + ", " + DictationKeyboardLog.memoryDetail()
        log("appeared", detail)
    }

    private func logRoute() {
        let reason = DictationKeyboardMicRoute.reason(mode: micMode, hasFullAccess: hasFullAccess, keyboardMicFailed: keyboardMicFailed)
        log("route", (route?.label ?? "NONE") + ": " + reason)
    }

    /// The text around the cursor changed (typing, or the host moved the cursor).
    func textChanged() {
        layout.autoCapitalize(before: host?.contextBeforeInput)
        appleObserve(by: .textDidChange)
    }

    // MARK: Keys

    func tap(_ control: DictationKeyboardControl) {
        // Build 40: a Midas key while Apple is still typing ends that dictation first
        if isAppleMode && appleTracker.phase == .dictating {
            handleApple(appleTracker.end(.midasKey))
        }
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
        // Build 41: apple mode types from the numbers-first keyboard
        if usesNumbersLayout {
            perform(numbersLayout.handle(resolved))
        } else {
            perform(layout.handle(resolved))
        }
        let typed: Bool
        switch control {
        case .character, .space, .backspace, .returnKey:
            typed = true
        default:
            typed = false
        }
        if typed {
            // Undo is for Midas's cleanups and cancels; typing makes them stale
            undo.clear()
            layout.autoCapitalize(before: host?.contextBeforeInput)
        }
    }

    // MARK: Sounds and haptics (build 41)

    /// A key went down: Apple's sound for its kind and a light haptic (touch down, as Apple's keyboard).
    func keyPressed(_ control: DictationKeyboardControl) {
        let kind = DictationKeyKind.of(control)
        host?.playFeedback(DictationKeyboardFeedbackPlan.forKey(kind, hasFullAccess: hasFullAccess))
    }

    /// Undo and ✕ sound like modifier keys.
    func topBarPressed() {
        host?.playFeedback(DictationKeyboardFeedbackPlan.forKey(.modifier, hasFullAccess: hasFullAccess))
    }

    private func playMoment(_ moment: DictationFeedbackMoment) {
        host?.playFeedback(DictationKeyboardFeedbackPlan.forMoment(moment, hasFullAccess: hasFullAccess))
    }

    private func logFeedbackAvailability() {
        guard isAppleMode, let host else {
            return
        }
        log("feedback", DictationKeyboardFeedbackPlan.availabilityDetail(hasFullAccess: hasFullAccess, inputClicksEnabled: host.inputClicksEnabled,
                                                                         reduceMotion: host.reduceMotion))
    }

    // MARK: Cancel and undo (build 41)

    /// Whether the listening view covers the keys (apple mode, while Apple types or the text lands).
    var appleCovering: Bool {
        guard usesNumbersLayout else {
            return false
        }
        switch panel {
        case .listening, .inserted:
            return true
        default:
            return false
        }
    }

    /// ✕ shows while Apple's dictation is running.
    var showsCancel: Bool {
        guard usesNumbersLayout, case .listening = panel else {
            return false
        }
        return true
    }

    /// ✕: delete exactly what this dictation typed (when the text still ends with it), close the
    /// listening view, then log for 3 s what Apple's dictation does next.
    func cancelApple() {
        guard isAppleMode, appleTracker.phase == .dictating, let host else {
            return
        }
        let now = Date()
        let contextNow = host.contextBeforeInput
        let plan = DictationAppleCancel.plan(span: appleTracker.span, contextNow: contextNow)
        for _ in 0..<plan.deleteCount {
            host.deleteBackward()
        }
        let contextAfter = plan.contextAfter(contextNow)
        if plan.result == .deleted {
            undo.record(DictationKeyboardEdit(removed: plan.removed, added: "", contextAfter: contextAfter))
        }
        // Waiting again; what Apple types after this is a new dictation
        appleTracker.reset(context: contextAfter, after: host.contextAfterInput)
        appleTracker.midasTyped(expected: contextAfter, at: now)
        appleSignalsLogged = []
        log("apple cancel", plan.detail + ", " + host.signalDetail)
        cancelWatchUntil = now.addingTimeInterval(DictationKeyboardExperienceConstants.cancelWatch)
        cancelWatchStartedAt = now
        cancelWatchLines = 0
        cancelWatchContext = contextAfter
        cancelWatchLanguage = host.inputModeLanguage
        insertedFlash?.cancel()
        insertedFlash = nil
        refreshPanel()
    }

    /// Undo: the last cleanup or cancel back as it was, while the text is as Midas left it.
    func undoLast() {
        guard let host else {
            return
        }
        let plan = undo.undo(contextNow: host.contextBeforeInput)
        log("undo", plan.detail)
        guard plan.result == .undone else {
            return
        }
        for _ in 0..<plan.deleteCount {
            host.deleteBackward()
        }
        host.insertText(plan.insertText)
        // Midas's own text, not dictation
        appleTracker.reset(context: plan.contextAfter, after: host.contextAfterInput)
        appleTracker.midasTyped(expected: plan.contextAfter, at: Date())
    }

    /// For 3 s after ✕: each change in the input mode or the text before the cursor, one line each.
    private func watchAfterCancel(language: String?, context: String?, at now: Date) {
        guard let cancelWatchUntil, let cancelWatchStartedAt else {
            return
        }
        guard now < cancelWatchUntil, cancelWatchLines < DictationKeyboardExperienceConstants.cancelWatchLines else {
            self.cancelWatchUntil = nil
            log("apple after cancel", "watch ended, " + String(cancelWatchLines) + " changes")
            return
        }
        let text = context ?? ""
        guard language != cancelWatchLanguage || text != cancelWatchContext else {
            return
        }
        let since = String(format: "+%.2f s", now.timeIntervalSince(cancelWatchStartedAt))
        let change = text.count - (cancelWatchContext ?? "").count
        log("apple after cancel", since + ": input mode " + (language ?? "none") + ", before " + String(text.count) + " chars ("
            + (change >= 0 ? "+" : "") + String(change) + ")")
        cancelWatchLines += 1
        cancelWatchLanguage = language
        cancelWatchContext = text
    }

    /// Start Dictation: ask to listen, then open Midas Test to turn the microphone on.
    func startDictation() {
        log("start dictation", "opening Midas Test")
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
                let before = host?.contextBeforeInput ?? ""
                host?.insertText(text)
                noteMidasEdit(expected: before + text)
            case .deleteBackward:
                let before = host?.contextBeforeInput ?? ""
                host?.deleteBackward()
                noteMidasEdit(expected: String(before.dropLast()))
            }
        }
    }

    // MARK: Which microphone

    private var route: DictationKeyboardMicRoute? {
        DictationKeyboardMicRoute.route(mode: micMode, hasFullAccess: hasFullAccess, keyboardMicFailed: keyboardMicFailed)
    }

    private func startListening() {
        micLabel = route?.label
        switch route {
        case .keyboardMic:
            startKeyboardMic()
        case .app:
            sendRequest(wantsListening: true)
        case .apple:
            // Apple's 🎙 starts it; the panel waits for it
            refreshPanel()
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
        case .apple, nil:
            // Apple's dictation is not the keyboard's to stop; the keyboard keeps watching
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
        micError = nil
        loggedStep = nil
        listener?.reset()
        // The line answers this appearance's attempt, not the last one's
        micLine = nil
        if let leftOver = mailbox.readProbeAttempt() {
            mailbox.writeProbeAttempt(nil)
            let probe = leftOver.ended(at: Date())
            micLine = probe.panelLine
            log("probe", "left over from the last appearance: " + probe.panelLine)
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
                                                             stoppedListening: makeStoppedHandler(), listenFailed: makeListenFailedHandler())
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
            self?.attemptChanged(attempt)
        }
    }

    private func makeListenFailedHandler() -> @MainActor (DictationKeyboardProbeStep, DictationKeyboardProbeError) -> Void {
        { [weak self] step, error in
            self?.listenFailed(step: step, error: error)
        }
    }

    /// Every listen that would not start goes in the log; keyboard-only shows the newest error.
    private func listenFailed(step: DictationKeyboardProbeStep, error: DictationKeyboardProbeError) {
        let line = "Mic in keyboard: " + step.label + ", " + error.summary
        log("mic failed", line + ", " + DictationKeyboardLog.memoryDetail())
        if micMode == .keyboardOnly {
            micError = line
        }
    }

    private func makeStoppedHandler() -> @MainActor () -> Void {
        { [weak self] in
            self?.refreshPanel()
        }
    }

    /// The attempt kept in the App Group at each step; each new step logged once.
    private func attemptChanged(_ attempt: DictationKeyboardProbeAttempt?) {
        mailbox?.writeProbeAttempt(attempt)
        guard let attempt, attempt.step != loggedStep else {
            return
        }
        loggedStep = attempt.step
        log("mic step", attempt.step.label + " started, " + DictationKeyboardLog.memoryDetail())
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
        let audioText = "buffers \(probe.audio.buffers), peak " + String(format: "%.3f", probe.audio.peak)
        log("probe", probe.panelLine + ", " + audioText)
        queueKeyboardRecord(probe, id: probe.id, in: DictationKeyboardMailbox.probesFolder)
        guard probe.result == .failed else {
            return
        }
        // Keyboard only: no fallback; the exact error stays on the panel
        if micMode == .keyboardOnly {
            micError = probe.panelLine
            log("route", "KEYBOARD MIC: keyboardMic keyboard-only, no fallback")
            refreshPanel()
            return
        }
        keyboardMicFailed = true
        micLabel = route?.label
        log("route", (route?.label ?? "NONE") + ": keyboard mic failed, falling back to Midas Test")
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
        do {
            try mailbox.queue(value, id: id, in: folderName)
        } catch {
            // Build 34 dropped this silently
            log("queue failed", folderName + "/" + id + ": " + DictationKeyboardProbeError(error).summary)
        }
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
        if route == .apple {
            refreshApplePanel()
            return
        }
        panelHint = nil
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

    // MARK: Apple's dictation (build 40)

    private var isAppleMode: Bool {
        route == .apple
    }

    /// The listening look while Apple types (orb listening, the words, APPLE MIC); else the hint.
    private func refreshApplePanel() {
        guard appleTracker.phase == .dictating else {
            micLabel = nil
            panelHint = DictationAppleConstants.hint
            panel = .idle
            return
        }
        micLabel = DictationAppleConstants.label
        panelHint = nil
        let heard = appleTracker.span ?? ""
        let words = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        appleWords = words
        panel = .listening(heard: words)
    }

    /// Each appearance in apple mode: what iOS reports, the text found now (dictation that ran while
    /// the keyboard was hidden ends here), then the 150 ms watch.
    private func appleAppeared() {
        guard isAppleMode, let host else {
            stopApplePoll()
            return
        }
        let now = Date()
        lastInputModeLanguage = host.inputModeLanguage
        let hiddenFor = hiddenAt.map { now.timeIntervalSince($0) }
        let sameDocument = appleTrackerPrimed && hiddenDocument == host.documentIdentifier
        let hiddenText = hiddenFor.map { String(format: "%.1f s", $0) } ?? "first"
        log("apple appeared", host.signalDetail + ", hidden " + hiddenText + ", same document " + (sameDocument ? "yes" : "no")
            + ", before " + String(host.contextBeforeInput?.count ?? 0) + " chars, tracker " + (appleTracker.phase == .dictating ? "dictating" : "waiting"))
        if appleTrackerPrimed {
            handleApple(appleTracker.appeared(context: host.contextBeforeInput, after: host.contextAfterInput, sameDocument: sameDocument, at: now))
        } else {
            appleTracker.reset(context: host.contextBeforeInput, after: host.contextAfterInput)
            appleTrackerPrimed = true
        }
        startApplePoll()
    }

    /// viewDidAppear: logged in apple mode (does iOS bring the keyboard back after dictation?).
    func didAppear() {
        guard isAppleMode, let host else {
            return
        }
        log("apple did appear", host.signalDetail)
    }

    private func appleDisappeared() {
        stopApplePoll()
        guard isAppleMode, let host else {
            return
        }
        hiddenDocument = host.documentIdentifier
        hiddenAt = Date()
        let state = appleTracker.phase == .dictating ? "dictating, " + String(appleTracker.span?.count ?? 0) + " chars" : "waiting"
        log("apple hidden", host.signalDetail + ", tracker " + state)
    }

    private func startApplePoll() {
        applePoll?.cancel()
        let interval = DictationAppleConstants.pollInterval
        applePoll = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else {
                    return
                }
                self?.applePollTick()
            }
        }
    }

    private func stopApplePoll() {
        applePoll?.cancel()
        applePoll = nil
    }

    /// Every 150 ms while shown: the input mode, the text around the cursor, the quiet end.
    private func applePollTick() {
        guard isAppleMode, isShown, let host else {
            return
        }
        let language = host.inputModeLanguage
        watchAfterCancel(language: language, context: host.contextBeforeInput, at: Date())
        if language != lastInputModeLanguage {
            log("apple input mode", "poll: " + (lastInputModeLanguage ?? "none") + " → " + (language ?? "none"))
            lastInputModeLanguage = language
            handleApple(appleTracker.inputModeChanged(isDictation: DictationAppleConstants.isDictation(language: language), at: Date()))
        }
        appleObserve(by: .poll)
        handleApple(appleTracker.tick(at: Date()))
    }

    /// UITextInputMode.currentInputModeDidChangeNotification, with the language it carried.
    func inputModeChanged(notificationLanguage: String?) {
        guard isAppleMode, let host else {
            return
        }
        let language = host.inputModeLanguage
        log("apple input mode", "notification: " + (notificationLanguage ?? "none") + ", " + host.signalDetail)
        lastInputModeLanguage = language
        let isDictation = DictationAppleConstants.isDictation(language: notificationLanguage) || DictationAppleConstants.isDictation(language: language)
        handleApple(appleTracker.inputModeChanged(isDictation: isDictation, at: Date()))
    }

    /// textWillChange: counted, and logged once per dictation.
    func textWillChange() {
        guard isAppleMode else {
            return
        }
        appleTracker.textWillChange()
        logAppleSignalOnce(.textWillChange)
    }

    private func appleObserve(by signal: DictationAppleSignal) {
        guard isAppleMode, isShown, let host else {
            return
        }
        handleApple(appleTracker.observed(context: host.contextBeforeInput, after: host.contextAfterInput, by: signal, at: Date()))
        if signal != .poll {
            logAppleSignalOnce(signal)
        }
    }

    /// The first time a signal fires in a dictation: one log line with the time and the text's length.
    private func logAppleSignalOnce(_ signal: DictationAppleSignal) {
        guard appleTracker.phase == .dictating, !appleSignalsLogged.contains(signal) else {
            return
        }
        appleSignalsLogged.insert(signal)
        log("apple signal", signal.rawValue + ", span " + String(appleTracker.span?.count ?? 0) + " chars")
    }

    /// Midas typed or deleted: its own text, not dictation.
    private func noteMidasEdit(expected: String) {
        guard isAppleMode else {
            return
        }
        appleTracker.midasTyped(expected: expected, at: Date())
    }

    private func handleApple(_ events: [DictationAppleEvent]) {
        for event in events {
            switch event {
            case .began(let signal):
                appleSignalsLogged = [signal]
                let since = host?.contextBeforeInput?.count ?? 0
                log("apple start", signal.rawValue + ", before " + String(since) + " chars, start " + String(appleTracker.startContext.count) + " chars, "
                    + (host?.signalDetail ?? ""))
                playMoment(.listeningStarted)
                refreshPanel()
            case .heard:
                refreshPanel()
            case .ended(let finished):
                cleanUpApple(finished)
            }
        }
    }

    /// The gate on the dictated span; replaced when the text still ends with it; the run queued for
    /// Midas Test either way.
    private func cleanUpApple(_ finished: DictationAppleFinished) {
        let contextNow = host?.contextBeforeInput
        let plan = DictationAppleCleanup.plan(span: finished.span, contextNow: contextNow, settings: gateSettings)
        log("apple end", finished.end.rawValue + ", span " + String(finished.span?.count ?? 0) + " chars, " + DictationAppleLog.countsDetail(finished))
        if plan.replaces, let host {
            for _ in 0..<plan.deleteCount {
                host.deleteBackward()
            }
            host.insertText(plan.insertText)
        }
        let cleanedAt = Date()
        let contextAfter = DictationAppleCleanup.contextAfter(plan, contextNow: contextNow)
        // Build 41: undo puts back what Apple typed
        if plan.replaces, let span = finished.span {
            undo.record(DictationKeyboardEdit(removed: String(span.suffix(plan.deleteCount)), added: plan.insertText, contextAfter: contextAfter))
            appleWords = plan.cleaned
            playMoment(.textLanded)
        }
        appleTracker.reset(context: contextAfter, after: host?.contextAfterInput)
        // The replacement landing late in the host's text is not dictation
        appleTracker.midasTyped(expected: contextAfter, at: cleanedAt)
        appleSignalsLogged = []
        log("apple cleanup", DictationAppleLog.cleanupDetail(plan) + ", " + String(Int((cleanedAt.timeIntervalSince(finished.lastChangeAt) * 1000).rounded())) + " ms")
        appleCounter += 1
        let runId = DictationKeyboardProbeAttempt.newId(at: cleanedAt, counter: appleCounter)
        let run = DictationAppleRun(id: runId, plan: plan, finished: finished, cleanedAt: cleanedAt, thermal: .current())
        queueKeyboardRecord(run, id: run.id, in: DictationAppleConstants.runsFolder)
        refreshPanel()
        if plan.replaces {
            flashInserted()
        }
    }
}
