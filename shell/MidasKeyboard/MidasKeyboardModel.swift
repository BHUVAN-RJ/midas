// The Midas keyboard's model (TEST BUILD, founder 2026-11-14; branch agent/dictation-test, never
// merged; docs/briefs/dictation-keyboard-test.md). Pages and keys come from DictationKeyboardLayout
// (shared with the app, so its tests cover them); this file carries out their effects: typing
// through the text proxy, and asking Midas Test to listen through the App Group.
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

    @ObservationIgnored weak var host: MidasKeyboardHost?
    @ObservationIgnored private let mailbox: DictationKeyboardMailbox?
    @ObservationIgnored private var lastRequest: DictationKeyboardRequest?
    @ObservationIgnored private var darwinObserver: DictationDarwinObserver?
    @ObservationIgnored private var answerCheck: Task<Void, Never>?
    @ObservationIgnored private var insertedFlash: Task<Void, Never>?
    @ObservationIgnored private var lastShiftTapAt: Date?

    init(hasFullAccess: Bool, appGroup: String) {
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
        perform(layout.appeared())
        insertWaitingDelivery()
        layout.autoCapitalize(before: host?.contextBeforeInput)
    }

    func disappeared() {
        perform(layout.disappeared())
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
        sendRequest(wantsListening: true)
    }

    private func perform(_ effects: [DictationKeyboardEffect]) {
        for effect in effects {
            switch effect {
            case .startListening:
                sendRequest(wantsListening: true)
            case .stopListening:
                sendRequest(wantsListening: false)
            case .nextKeyboard:
                host?.advanceToNextKeyboard()
            case .insert(let text):
                host?.insertText(text)
            case .deleteBackward:
                host?.deleteBackward()
            }
        }
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
