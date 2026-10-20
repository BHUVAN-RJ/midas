import Foundation
import Observation

// Voice reminders (midas-intel docs/plans/2026-10-15-voice-action-button-brief.md, founder
// 2026-10-15): Action button, speak, leave. "New Reminder" opens the Listening screen; it ends by
// itself after 1.2 s of silence or 15 s; the transcript goes to the server; a reminder that comes
// back is saved at once (no Add, no Undo) and a banner at the top of Midas says so. Anything
// else saves nothing and the banner keeps what was said, with Try Again.

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

    init(dependencies: VoiceReminderDependencies) {
        self.dependencies = dependencies
    }

    /// "New Reminder" (the intent): shows the Listening screen. Signed out, nothing happens; the
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

    static func actionTitle(for kind: VoiceBanner.Kind) -> String? {
        if case .notAdded = kind {
            return tryAgain
        }
        return nil
    }

    /// "Today", "Tomorrow", a weekday within the week, else the date; then the time unless all-day.
    static func whenText(for reminder: VoiceResolvedReminder, now: Date, calendar: Calendar, locale: Locale) -> String? {
        guard let atText = reminder.at, let at = ReminderRecord.parseDate(.string(atText)) else {
            return nil
        }
        var zonedCalendar = calendar
        zonedCalendar.timeZone = TimeZone(identifier: reminder.timeZone) ?? calendar.timeZone
        let day = dayText(for: at, now: now, calendar: zonedCalendar, locale: locale)
        if reminder.allDay {
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
