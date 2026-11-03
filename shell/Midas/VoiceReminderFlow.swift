import Foundation
import Observation

// Voice reminders (midas-intel docs/plans/2026-10-15-voice-action-button-brief.md, founder
// 2026-10-15): Action button, speak, leave. "Ask jess" opens the Listening screen; it ends by
// itself after 1.2 s of silence or 15 s; the transcript goes to the server; a reminder that comes
// back is saved at once (no Add, no Undo) and a banner at the top of Midas says so. Anything
// else saves nothing and the banner keeps what was said, with Try Again.
//
// jess router (founder, 2026-10-21): with `route` set (the live app), the same Listening screen
// sends the sentence to jess instead, which runs one Sidekick tool. jess in the background
// (founder, 2026-10-22): the request is finished by JessResults whether or not the screen is still
// up, and its result is one card at the top of the home page (JessResults.swift); the flow only
// closes the screen.

/// Why the Listening screen cannot listen.
enum VoiceCaptureProblem: Equatable, Sendable {
    /// Microphone or speech recognition declined (asked when Midas opens).
    case permissionDenied
    /// No on-device speech model; audio never goes to a server instead.
    case onDeviceUnavailable
}

/// What the Listening screen shows.
enum VoiceCapturePhase: Equatable, Sendable {
    case listening
    /// The last word is in; waiting for the server.
    case sending
    /// jess's Workdesk (founder, 2026-10-22): the request is on its card; the screen stays up
    /// until Done, and tapping the orb listens again.
    case ready
    case unavailable(VoiceCaptureProblem)

    var orbState: JessOrbState {
        switch self {
        case .listening:
            return .listening
        case .sending:
            return .thinking
        case .ready, .unavailable:
            return .idle
        }
    }
}

/// The result banner at the top of Midas.
struct VoiceBanner: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        case added(VoiceResolvedReminder)
        case notAdded(transcript: String)
        /// Try Again was tapped; the same transcript is on its way.
        case retrying(transcript: String)
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }

    var orbState: JessOrbState {
        switch kind {
        case .added:
            return .added
        case .notAdded:
            return .failed
        case .retrying:
            return .thinking
        }
    }

    /// Banners that report something done leave by themselves.
    var hidesByItself: Bool {
        switch kind {
        case .added:
            return true
        case .notAdded, .retrying:
            return false
        }
    }
}

/// The Listening screen's settings for the shared transcriber (brief item 3). Listening ends 2.5 s
/// after the last word, at most 30 s in all (founder, 2026-10-31; was 1.2 s and 15 s).
enum VoiceReminderListening {
    static let endOfSpeechSilence: Duration = .milliseconds(2500)
    static let maximumDuration: Duration = .seconds(30)

    /// Hint words: the user's Reminders list names.
    static func transcriberOptions(lists: [VoiceReminderList]) -> VoiceTranscriberOptions {
        var hintWords: [String] = []
        for list in lists {
            hintWords.append(list.name)
        }
        return VoiceTranscriberOptions(hintWords: hintWords, endOfSpeechSilence: endOfSpeechSilence, maximumDuration: maximumDuration)
    }
}

/// What the flow needs from the rest of the shell; tests pass stand-ins.
struct VoiceReminderDependencies {
    var isSignedIn: @MainActor () -> Bool
    var lists: @MainActor () -> [VoiceReminderList]
    var makeTranscriber: @MainActor (VoiceTranscriberOptions, VoiceAudioLevelMeter) -> VoiceTranscribing
    var api: VoiceReminderParsing
    /// Saves the reminder (through `RecordWriter`); throws when the record is refused.
    var save: @MainActor (VoiceResolvedReminder) throws -> Void
    var now: @MainActor () -> Date
    var timeZone: @MainActor () -> TimeZone
    var app: @MainActor () -> VoiceParseApp
    /// The jess router: one sentence to one Sidekick tool, finished in the background with its
    /// result on a home page card (JessResults.submit). Nil keeps the reminder parse above.
    var route: (@MainActor (_ transcript: String, _ listenMs: Int) async -> Void)? = nil
    /// jess's camera (founder, 2026-11-02): the words heard and a JPEG, finished like `route`.
    /// Nil: no camera button.
    var routePhoto: (@MainActor (_ transcript: String, _ listenMs: Int, _ photo: Data) async -> Void)? = nil
    /// The jess screen opened (the queue sends a cut-off request again).
    var opened: (@MainActor () -> Void)? = nil
    /// "Allow AI?" (founder, 2026-11-02): whether the person allowed sending to AI. Nil: no ask.
    var aiAllowed: (@MainActor () -> Bool)? = nil
    /// Shows "Allow AI?" and keeps the request for Allow (AIConsentCenter.run).
    var askForAI: (@MainActor (_ onAllow: @escaping @MainActor () -> Void) -> Void)? = nil
}

@MainActor
@Observable
final class VoiceReminderFlow {
    /// The Listening screen is up.
    var isPresented = false
    private(set) var phase: VoiceCapturePhase = .listening
    private(set) var transcript = ""
    var banner: VoiceBanner?
    /// How loud the microphone is, for the orb.
    let audioLevel = VoiceAudioLevelMeter()

    @ObservationIgnored private let dependencies: VoiceReminderDependencies
    @ObservationIgnored private var transcriber: VoiceTranscribing?
    @ObservationIgnored private var listeningStartedAt: Date?
    @ObservationIgnored private var listenMs = 0
    /// Bumped by Cancel and by every new listen, so an answer for an older one is dropped.
    @ObservationIgnored private var attempt = 0
    /// A request went to jess since the screen opened: an empty listen then returns to the
    /// Workdesk instead of closing it.
    @ObservationIgnored private var hasSentSinceOpen = false
    /// Words heard before the camera opened, waiting for the photo.
    @ObservationIgnored private var heldWords = ""

    init(dependencies: VoiceReminderDependencies) {
        self.dependencies = dependencies
    }

    /// "Ask jess" (the intent): shows the Listening screen. Signed out, nothing happens; the
    /// Welcome screen is what Midas shows then.
    func request() {
        guard dependencies.isSignedIn() else {
            return
        }
        // Not allowed yet (never asked, or Not Now): "Allow AI?" first; Allow opens the screen
        if let aiAllowed = dependencies.aiAllowed, !aiAllowed() {
            dependencies.askForAI?(request)
            return
        }
        transcript = ""
        phase = .listening
        isPresented = true
        hasSentSinceOpen = false
        dependencies.opened?()
    }

    /// Called by the Listening screen once it is on screen, so the microphone starts with Midas
    /// in front.
    func startListening() async {
        attempt += 1
        let listenAttempt = attempt
        transcript = ""
        phase = .listening
        let options = VoiceReminderListening.transcriberOptions(lists: dependencies.lists())
        let newTranscriber = dependencies.makeTranscriber(options, audioLevel)
        transcriber = newTranscriber
        listeningStartedAt = dependencies.now()
        do {
            try await newTranscriber.start(sessionStartedAt: dependencies.now(), onUpdate: { [weak self] heard in
                self?.hear(heard, attempt: listenAttempt)
            }, onEnd: { [weak self] reason in
                self?.listeningEnded(reason, attempt: listenAttempt)
            })
        } catch VoiceTranscriberError.notAuthorized {
            phase = .unavailable(.permissionDenied)
        } catch {
            phase = .unavailable(.onDeviceUnavailable)
        }
    }

    /// The words are in and jess finishes in the background (router only): the screen's button
    /// closes it instead of cancelling.
    var finishesInBackground: Bool {
        phase == .sending && dependencies.route != nil
    }

    /// The Workdesk's button: Cancel while nothing has been said, Done once words are in
    /// (founder, 2026-10-22).
    var buttonTitle: String {
        switch phase {
        case .listening:
            return transcript.isEmpty ? VoiceReminderCopy.cancel : VoiceReminderCopy.done
        case .sending, .ready:
            return dependencies.route == nil ? VoiceReminderCopy.cancel : VoiceReminderCopy.done
        case .unavailable:
            return VoiceReminderCopy.cancel
        }
    }

    /// Tapping the orb on the Workdesk once a request is on its card: listen again.
    func listenAgain() async {
        guard phase == .ready, isPresented else {
            return
        }
        await startListening()
    }

    /// The orb answers a tap while listening or once a request is on its card (founder,
    /// 2026-11-02, build 22 feedback: tap to start, tap again to stop).
    var orbTapWorks: Bool {
        phase == .listening || phase == .ready
    }

    /// The camera button shows where photos can be sent, and works while listening or waiting.
    var hasCamera: Bool {
        dependencies.routePhoto != nil
    }

    var cameraTapWorks: Bool {
        hasCamera && (phase == .listening || phase == .ready)
    }

    /// The camera opened: listening stops so the silence timer cannot send the words without the
    /// photo; the words heard so far wait for it.
    func holdForCamera() {
        guard cameraTapWorks, isPresented else {
            return
        }
        guard phase == .listening else {
            heldWords = ""
            return
        }
        attempt += 1
        let stoppingTranscriber = transcriber
        transcriber = nil
        stoppingTranscriber?.stop()
        if let listeningStartedAt {
            listenMs = Int((dependencies.now().timeIntervalSince(listeningStartedAt) * 1000).rounded())
        }
        heldWords = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        phase = .ready
    }

    /// Use Photo: the photo and the words held for it go to jess together.
    func sendPhoto(_ jpeg: Data) {
        guard let routePhoto = dependencies.routePhoto, isPresented else {
            return
        }
        let words = heldWords
        heldWords = ""
        attempt += 1
        let sendAttempt = attempt
        transcript = words
        hasSentSinceOpen = true
        phase = .sending
        let heardMs = listenMs
        Task { @MainActor [weak self] in
            await routePhoto(words, heardMs, jpeg)
            guard let self, sendAttempt == self.attempt else {
                return
            }
            self.phase = .ready
        }
    }

    /// The camera closed without a photo: words held for it are sent as they are; with none, jess
    /// listens again.
    func cameraCancelled() async {
        let words = heldWords
        heldWords = ""
        guard isPresented, phase == .ready else {
            return
        }
        guard !words.isEmpty else {
            await startListening()
            return
        }
        transcript = words
        if dependencies.route != nil {
            hasSentSinceOpen = true
        }
        attempt += 1
        let sendAttempt = attempt
        phase = .sending
        await send(words, attempt: sendAttempt)
    }

    /// Tapping the orb on the Workdesk: listening stops (what was heard is sent); otherwise it
    /// listens again.
    func orbTapped() async {
        if phase == .listening {
            stopListeningAndSend()
            return
        }
        await listenAgain()
    }

    /// Ends listening now, as the silence timer would: the words heard are sent; with nothing
    /// heard nothing is sent and the Workdesk stays up with the orb idle.
    func stopListeningAndSend() {
        guard phase == .listening, isPresented else {
            return
        }
        // A new attempt, so the transcriber's own "stopped" end is ignored
        attempt += 1
        let sendAttempt = attempt
        let stoppingTranscriber = transcriber
        transcriber = nil
        stoppingTranscriber?.stop()
        if let listeningStartedAt {
            listenMs = Int((dependencies.now().timeIntervalSince(listeningStartedAt) * 1000).rounded())
        }
        let saidText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !saidText.isEmpty else {
            phase = .ready
            return
        }
        if dependencies.route != nil {
            hasSentSinceOpen = true
        }
        phase = .sending
        Task { @MainActor [weak self] in
            await self?.send(saidText, attempt: sendAttempt)
        }
    }

    /// A Workdesk card is about to open its Sidekick over jess. While listening with no words yet,
    /// listening stops quietly and jess stays up; with words heard the tap is ignored, so nothing
    /// said is lost. Returns whether the Sidekick may open.
    func prepareToOpenSidekick() -> Bool {
        guard phase == .listening else {
            return true
        }
        guard transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        attempt += 1
        let stoppingTranscriber = transcriber
        transcriber = nil
        stoppingTranscriber?.stop()
        phase = .ready
        return true
    }

    /// Cancel: nothing is sent, nothing saved, no banner. Once the words are in, jess's request
    /// is not stopped by this: the screen closes and the result shows on the home page.
    func cancel() {
        attempt += 1
        let stoppingTranscriber = transcriber
        transcriber = nil
        stoppingTranscriber?.stop()
        isPresented = false
        phase = .listening
    }

    /// Try Again on the banner: the same transcript, sent again; no listening.
    func retry() {
        guard case .notAdded(let saidText)? = banner?.kind else {
            return
        }
        banner = VoiceBanner(kind: .retrying(transcript: saidText))
        attempt += 1
        let retryAttempt = attempt
        Task { @MainActor [weak self] in
            await self?.send(saidText, attempt: retryAttempt)
        }
    }

    func dismissBanner() {
        banner = nil
    }

    private func hear(_ heard: VoiceTranscript, attempt listenAttempt: Int) {
        guard listenAttempt == attempt else {
            return
        }
        transcript = heard.text
    }

    private func listeningEnded(_ reason: VoiceTranscriptionEnd, attempt listenAttempt: Int) {
        guard listenAttempt == attempt else {
            return
        }
        transcriber = nil
        if let listeningStartedAt {
            listenMs = Int((dependencies.now().timeIntervalSince(listeningStartedAt) * 1000).rounded())
        }
        let saidText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        // Nothing heard (or Cancel, which already closed the screen): close without a banner
        guard reason != .stopped, !saidText.isEmpty else {
            if hasSentSinceOpen && reason != .stopped {
                phase = .ready
            } else {
                isPresented = false
            }
            return
        }
        if dependencies.route != nil {
            hasSentSinceOpen = true
        }
        phase = .sending
        Task { @MainActor [weak self] in
            await self?.send(saidText, attempt: listenAttempt)
        }
    }

    private func send(_ saidText: String, attempt sendAttempt: Int) async {
        if let route = dependencies.route {
            await route(saidText, listenMs)
            guard sendAttempt == attempt else {
                return
            }
            // The Workdesk stays up with the result on its card; Done closes it
            phase = .ready
            return
        }
        let request = makeRequest(transcript: saidText)
        let result = await dependencies.api.parse(request)
        guard sendAttempt == attempt else {
            return
        }
        isPresented = false
        phase = .listening
        guard case .done(let reminder) = result else {
            banner = VoiceBanner(kind: .notAdded(transcript: saidText))
            return
        }
        do {
            try dependencies.save(reminder)
            banner = VoiceBanner(kind: .added(reminder))
        } catch {
            banner = VoiceBanner(kind: .notAdded(transcript: saidText))
        }
    }

    private func makeRequest(transcript saidText: String) -> VoiceParseRequest {
        VoiceParseRequest(
            transcript: saidText,
            now: ReminderRecord.formatDate(dependencies.now()),
            timeZone: dependencies.timeZone().identifier,
            locale: Locale.current.identifier(.bcp47),
            lists: dependencies.lists(),
            app: dependencies.app(),
            listenMs: listenMs
        )
    }
}

/// Words on the Listening screen and the banner (docs/WRITING.md; wording mockup approved,
/// docs/mockups/jess-orb-2026-10-15.html).
enum VoiceReminderCopy {
    static let cancel = "Cancel"
    static let added = "Added"
    static let notAdded = "Not Added"
    static let tryAgain = "Try Again"
    static let adding = "Adding…"
    static let microphoneOff = "Microphone Off"
    static let openSettings = "Open Settings"
    static let voiceUnavailable = "Voice Not Available"
    static let notDone = "Not Done"
    /// "Repair" is "Edit" everywhere a person sees it (founder, 2026-10-31).
    static let sentToRepair = "Sent to Edit"
    /// A repair jess sent that the agent could not make, while the founder makes it by hand
    /// (founder, 2026-11-01): the same words as the Edit tag.
    static let takingDeeperLook = RepairTagCopy.couldntFix

    static func problemTitle(_ problem: VoiceCaptureProblem) -> String {
        switch problem {
        case .permissionDenied:
            return microphoneOff
        case .onDeviceUnavailable:
            return voiceUnavailable
        }
    }

    static let close = "Close"
    static let dismiss = "Dismiss"
    static let working = "Working…"
    static let done = "Done"
    /// The Workdesk (founder, 2026-10-22): words only where the Sidekick is not known yet.
    static let onIt = "On It"
    static let waitingForConnection = "Waiting for Connection"

    static func title(for kind: VoiceBanner.Kind) -> String {
        switch kind {
        case .added:
            return added
        case .notAdded:
            return notAdded
        case .retrying:
            return adding
        }
    }

    /// Added: "Call Mom · Tomorrow, 6:00 PM". Not added: what was said, in quotes.
    static func body(for kind: VoiceBanner.Kind, now: Date, calendar: Calendar, locale: Locale) -> String {
        switch kind {
        case .added(let reminder):
            guard let when = whenText(for: reminder, now: now, calendar: calendar, locale: locale) else {
                return reminder.title
            }
            return reminder.title + " · " + when
        case .notAdded(let saidText), .retrying(let saidText):
            return "“" + saidText + "”"
        }
    }

    /// The home page card (founder, 2026-10-22): done, the Sidekick's own line over the time it
    /// set; Sent to Repair over the Sidekick's name; Not Done (or Working… while sent) over what
    /// was said, in quotes.
    static func cardTitle(_ card: JessResultCard) -> String {
        switch card.kind {
        case .working:
            return working
        case .done(let text, _, _, _):
            return text
        case .notDone:
            return notDone
        case .sentToRepair:
            return card.takingDeeperLook == true ? takingDeeperLook : sentToRepair
        case .waitingForConnection:
            return waitingForConnection
        }
    }

    static func cardBody(_ card: JessResultCard, now: Date, calendar: Calendar, locale: Locale) -> String {
        switch card.kind {
        case .working, .notDone, .waitingForConnection:
            return card.transcript.isEmpty ? "" : "“" + card.transcript + "”"
        case .done(_, let at, let allDay, let timeZone):
            guard let at, let when = whenText(at: at, allDay: allDay, timeZone: timeZone, now: now, calendar: calendar, locale: locale) else {
                return ""
            }
            return when
        case .sentToRepair(let sidekickName, _):
            return sidekickName
        }
    }

    /// The Workdesk card's main line (founder, 2026-10-22): the whole task; the Sidekick's own line
    /// once done; what was said, in quotes, while jess is on it.
    /// A card for a photo sent with no words (jess's camera, founder 2026-11-02).
    static let photo = "Photo"

    static func workdeskLine(_ card: JessResultCard) -> String {
        if card.transcript.isEmpty, card.hasPhoto == true {
            if case .done(let text, _, _, _) = card.kind {
                return text
            }
            return photo
        }
        switch card.kind {
        case .working:
            return card.transcript.isEmpty ? "" : "“" + card.transcript + "”"
        case .done(let text, _, _, _):
            return text
        case .notDone, .sentToRepair, .waitingForConnection:
            return workdeskTask(card.transcript)
        }
    }

    /// The second line: only the Sidekick's name, or a status where the Sidekick is not known yet.
    static func workdeskMeta(_ card: JessResultCard) -> String {
        switch card.kind {
        case .working:
            return card.sidekickName ?? onIt
        case .waitingForConnection:
            return waitingForConnection
        case .sentToRepair(let sidekickName, _):
            if card.takingDeeperLook == true {
                return takingDeeperLook
            }
            return card.sidekickName ?? sidekickName
        case .done, .notDone:
            return card.sidekickName ?? ""
        }
    }

    /// What was said as a task: its first letter upper case.
    static func workdeskTask(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.uppercased() + text.dropFirst()
    }

    /// Only Not Done has a button.
    static func cardActionTitle(_ card: JessResultCard) -> String? {
        card.kind == .notDone ? tryAgain : nil
    }

    static func actionTitle(for kind: VoiceBanner.Kind) -> String? {
        if case .notAdded = kind {
            return tryAgain
        }
        return nil
    }

    /// "Today", "Tomorrow", a weekday within the week, else the date; then the time unless all-day.
    static func whenText(for reminder: VoiceResolvedReminder, now: Date, calendar: Calendar, locale: Locale) -> String? {
        guard let atText = reminder.at else {
            return nil
        }
        return whenText(at: atText, allDay: reminder.allDay, timeZone: reminder.timeZone, now: now, calendar: calendar, locale: locale)
    }

    static func whenText(at atText: String, allDay: Bool, timeZone: String?, now: Date, calendar: Calendar, locale: Locale) -> String? {
        guard let at = ReminderRecord.parseDate(.string(atText)) else {
            return nil
        }
        var zonedCalendar = calendar
        zonedCalendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
        let day = dayText(for: at, now: now, calendar: zonedCalendar, locale: locale)
        if allDay {
            return day
        }
        let timeFormatter = DateFormatter()
        timeFormatter.locale = locale
        timeFormatter.timeZone = zonedCalendar.timeZone
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        return day + ", " + timeFormatter.string(from: at)
    }

    static func dayText(for date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDay = calendar.startOfDay(for: date)
        let dayCount = calendar.dateComponents([.day], from: startOfToday, to: startOfDay).day ?? 0
        if dayCount == 0 {
            return "Today"
        }
        if dayCount == 1 {
            return "Tomorrow"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        if dayCount > 1 && dayCount < 7 {
            formatter.setLocalizedDateFormatFromTemplate("EEEE")
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        }
        return formatter.string(from: date)
    }
}
