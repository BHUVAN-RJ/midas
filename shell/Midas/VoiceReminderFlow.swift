import Foundation
import Observation

// Voice reminders (midas-intel docs/plans/2026-10-15-voice-action-button-brief.md, founder
// 2026-10-15): Action button, speak, leave. "Ask jess" opens the Listening screen; it ends by
// itself after 1.2 s of silence or 15 s; the transcript goes to the server; a reminder that comes
// back is saved at once (no Add, no Undo) and a banner at the top of Midas says so. Anything
// else saves nothing and the banner keeps what was said, with Try Again.
//
// jess router (founder, 2026-10-21): with `route` set (the live app), the same Listening screen
// sends the sentence to jess instead, which runs one Sidekick tool. Done: a banner with the
// Sidekick's own line ("Added Bananas", "Marked done: Call Mom", "Sent to Repair"). Not done:
// nothing changed, and a card at the top of the home page keeps what was said, with Try Again.

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
    case unavailable(VoiceCaptureProblem)

    var orbState: JessOrbState {
        switch self {
        case .listening:
            return .listening
        case .sending:
            return .thinking
        case .unavailable:
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
        /// jess ran a Sidekick tool: its own line and the time it set, if any.
        case acted(text: String, at: String?, allDay: Bool, timeZone: String?)
        /// jess queued a repair of the named Sidekick.
        case sentToRepair(sidekickName: String)
    }

    let id: UUID
    let kind: Kind

    init(kind: Kind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }

    var orbState: JessOrbState {
        switch kind {
        case .added, .acted, .sentToRepair:
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
        case .added, .acted, .sentToRepair:
            return true
        case .notAdded, .retrying:
            return false
        }
    }
}

/// The card at the top of the home page when jess could not act (founder, 2026-10-21): what was
/// said, "Not Done", Try Again. It stays until Try Again works or it is dismissed.
struct JessNotDoneCard: Equatable, Identifiable, Sendable {
    let id: UUID
    let transcript: String
    /// Try Again was tapped; the same sentence is on its way.
    var isRetrying: Bool

    init(transcript: String, isRetrying: Bool = false, id: UUID = UUID()) {
        self.id = id
        self.transcript = transcript
        self.isRetrying = isRetrying
    }

    var orbState: JessOrbState {
        isRetrying ? .thinking : .failed
    }
}

/// The Listening screen's settings for the shared transcriber (brief item 3).
enum VoiceReminderListening {
    static let endOfSpeechSilence: Duration = .milliseconds(1200)
    static let maximumDuration: Duration = .seconds(15)

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
    /// The jess router: one sentence to one Sidekick tool. Nil keeps the reminder parse above.
    var route: (@MainActor (_ transcript: String, _ listenMs: Int) async -> JessResult)? = nil
}

@MainActor
@Observable
final class VoiceReminderFlow {
    /// The Listening screen is up.
    var isPresented = false
    private(set) var phase: VoiceCapturePhase = .listening
    private(set) var transcript = ""
    var banner: VoiceBanner?
    /// jess could not act on the last sentence (router only).
    var notDoneCard: JessNotDoneCard?
    /// How loud the microphone is, for the orb.
    let audioLevel = VoiceAudioLevelMeter()

    @ObservationIgnored private let dependencies: VoiceReminderDependencies
    @ObservationIgnored private var transcriber: VoiceTranscribing?
    @ObservationIgnored private var listeningStartedAt: Date?
    @ObservationIgnored private var listenMs = 0
    /// Bumped by Cancel and by every new listen, so an answer for an older one is dropped.
    @ObservationIgnored private var attempt = 0

    init(dependencies: VoiceReminderDependencies) {
        self.dependencies = dependencies
    }

    /// "Ask jess" (the intent): shows the Listening screen. Signed out, nothing happens; the
    /// Welcome screen is what Midas shows then.
    func request() {
        guard dependencies.isSignedIn() else {
            return
        }
        transcript = ""
        phase = .listening
        isPresented = true
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

    /// Cancel: nothing is sent, nothing saved, no banner.
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

    /// Try Again on the home page card: the same sentence, sent to jess again; no listening.
    func retryNotDone() {
        guard let card = notDoneCard, !card.isRetrying else {
            return
        }
        notDoneCard = JessNotDoneCard(transcript: card.transcript, isRetrying: true, id: card.id)
        attempt += 1
        let retryAttempt = attempt
        Task { @MainActor [weak self] in
            await self?.send(card.transcript, attempt: retryAttempt)
        }
    }

    func dismissNotDone() {
        notDoneCard = nil
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
            isPresented = false
            return
        }
        phase = .sending
        Task { @MainActor [weak self] in
            await self?.send(saidText, attempt: listenAttempt)
        }
    }

    private func send(_ saidText: String, attempt sendAttempt: Int) async {
        if let route = dependencies.route {
            let result = await route(saidText, listenMs)
            guard sendAttempt == attempt else {
                return
            }
            isPresented = false
            phase = .listening
            show(result)
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

    /// A result that did not come from the Listening screen: a request jess grew a Sidekick for,
    /// finished by the backend (JessGrowFollowUp).
    func present(_ result: JessResult) {
        show(result)
    }

    private func show(_ result: JessResult) {
        switch result {
        case .done(let text, let at, let allDay, let timeZone):
            notDoneCard = nil
            banner = VoiceBanner(kind: .acted(text: text, at: at, allDay: allDay ?? false, timeZone: timeZone))
        case .sentToRepair(let sidekickName):
            notDoneCard = nil
            banner = VoiceBanner(kind: .sentToRepair(sidekickName: sidekickName))
        case .notDone(let saidText):
            banner = nil
            notDoneCard = JessNotDoneCard(transcript: saidText)
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
    static let sentToRepair = "Sent to Repair"
    static let trying = "Trying…"

    static func problemTitle(_ problem: VoiceCaptureProblem) -> String {
        switch problem {
        case .permissionDenied:
            return microphoneOff
        case .onDeviceUnavailable:
            return voiceUnavailable
        }
    }

    static func title(for kind: VoiceBanner.Kind) -> String {
        switch kind {
        case .added:
            return added
        case .notAdded:
            return notAdded
        case .retrying:
            return adding
        case .acted(let text, _, _, _):
            return text
        case .sentToRepair:
            return sentToRepair
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
        case .acted(_, let at, let allDay, let timeZone):
            guard let at, let when = whenText(at: at, allDay: allDay, timeZone: timeZone, now: now, calendar: calendar, locale: locale) else {
                return ""
            }
            return when
        case .sentToRepair(let sidekickName):
            return sidekickName
        }
    }

    /// The home page card: "Not Done" (or "Trying…") over what was said, in quotes.
    static func cardTitle(_ card: JessNotDoneCard) -> String {
        card.isRetrying ? trying : notDone
    }

    static func cardBody(_ card: JessNotDoneCard) -> String {
        "“" + card.transcript + "”"
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
