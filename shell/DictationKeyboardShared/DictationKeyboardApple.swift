#if MIDAS_TEST_BUILD
// Build 40: our UI while Apple listens (TEST BUILD, founder 2026-11-22; branch agent/dictation-test,
// never merged; docs/briefs/dictation-keyboard-test.md, "Build 40"). Compiled into the Midas Test
// app and the MidasKeyboard extension.
//
// Build 38 showed a keyboard cannot record (engine start, 'what'). iOS draws its own 🎙 under the
// Midas keyboard; a keyboard cannot move, restyle or start it (no public API, no private calls).
// With settings:main `keyboardMic` "apple" the keyboard watches for Apple's dictation through public
// signals only (the input mode, textWillChange / textDidChange, the text before the cursor): text
// that changes without a Midas key counts as dictated. While it is dictated the panel shows the
// words with jess's orb listening and APPLE MIC; when dictation ends (the input mode is back, or no
// change for 1.5 s) the gate runs on the dictated span and, when the text still ends with exactly
// that span, the span is replaced with the gate's text (`appleCleanup`, on by default).
//
// This file is the pure part (the tests drive it with fixed text and times): the span, the
// tracker's states, the cleanup plan and the run the keyboard queues for Midas Test to save.
import Foundation

/// The fixed numbers and words of the Apple dictation test.
enum DictationAppleConstants {
    /// No change in the dictated text for this long ends a dictation (when the input mode does not
    /// say dictation is still on).
    static let quietEnd: TimeInterval = 1.5
    /// How often the keyboard reads the text before the cursor while it is shown.
    static let pollInterval: Duration = .milliseconds(150)
    /// A change this soon after a Midas key is that key landing, not dictation.
    static let midasKeyGrace: TimeInterval = 0.4
    /// iOS's context window may drop text from the front: the old text's end must still lead the
    /// new text by at least this many characters (or all of it, when shorter).
    static let minimumOverlap = 12
    /// The panel's one line in "apple" mode until dictation is seen (docs/WRITING.md).
    static let hint = "Tap 🎙 below"
    /// The large label while Apple's dictation is seen.
    static let label = "APPLE MIC"
    /// The settings:main field that turns cleanup on or off.
    static let cleanupField = "appleCleanup"
    /// The App Group folder of dictations waiting for Midas Test to save.
    static let runsFolder = "apple-runs"
    /// The input mode language iOS reports while dictating.
    static let dictationLanguage = "dictation"

    /// Whether an input mode's primary language is iOS's dictation mode.
    static func isDictation(language: String?) -> Bool {
        language?.lowercased() == dictationLanguage
    }
}

// MARK: The dictated span

enum DictationAppleSpan {
    /// The text added after `start` to make `now`: `now` minus `start` at its front. When iOS's
    /// context window dropped text from the front, the end of `start` must lead `now` instead
    /// (at least `minimumOverlap` characters, or all of `start`). Nil when neither holds (the text
    /// was changed elsewhere, so the span is unknown).
    static func dictated(from start: String, to now: String) -> String? {
        if now.hasPrefix(start) {
            return String(now.dropFirst(start.count))
        }
        let startCharacters = Array(start)
        let nowCharacters = Array(now)
        let longest = min(startCharacters.count, nowCharacters.count)
        let shortest = min(startCharacters.count, DictationAppleConstants.minimumOverlap)
        guard shortest >= 1, longest >= shortest else {
            return nil
        }
        // The longest overlap first: start's last k characters are now's first k
        for overlap in stride(from: longest, through: shortest, by: -1) {
            let startTail = startCharacters[(startCharacters.count - overlap)...]
            let nowHead = nowCharacters[..<overlap]
            if Array(startTail) == Array(nowHead) {
                return String(nowCharacters[overlap...])
            }
        }
        return nil
    }

    /// The span's whitespace before and after its words, and the words.
    static func parts(of span: String) -> (leading: String, core: String, trailing: String) {
        let leading = String(span.prefix(while: isWhitespace))
        let afterLeading = span.dropFirst(leading.count)
        let trailingCount = afterLeading.reversed().prefix(while: isWhitespace).count
        let core = String(afterLeading.dropLast(trailingCount))
        let trailing = String(afterLeading.suffix(trailingCount))
        return (leading, core, trailing)
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.isWhitespace
    }
}

// MARK: The tracker

/// How a dictation was seen to end.
enum DictationAppleEnd: String, Codable, Equatable, Sendable, CaseIterable {
    /// The input mode went back from dictation.
    case inputMode = "input-mode"
    /// No change for 1.5 s.
    case quiet
    /// The keyboard came back after iOS hid it.
    case keyboardShown = "keyboard-shown"
    /// A Midas key was tapped while text was still being dictated.
    case midasKey = "midas-key"
    /// The keyboard went away.
    case keyboardHidden = "keyboard-hidden"
}

/// Which public signal saw a dictation (counted per dictation for the keyboard log).
enum DictationAppleSignal: String, Codable, Equatable, Sendable, CaseIterable {
    /// UITextInputMode.currentInputModeDidChangeNotification, or the input mode read on a poll.
    case inputMode = "input-mode"
    case textWillChange = "text-will-change"
    case textDidChange = "text-did-change"
    /// The text before the cursor, read every 150 ms.
    case poll
    /// The keyboard appeared again with new text before the cursor.
    case appeared
}

/// One ended dictation: what was there before, what Apple added, and how it ended.
struct DictationAppleFinished: Equatable, Sendable {
    /// The span Apple typed; nil when the text changed elsewhere and the span is unknown.
    let span: String?
    let end: DictationAppleEnd
    let startedAt: Date
    /// The last change to the dictated text (the end of speech, as far as the keyboard can see).
    let lastChangeAt: Date
    /// The signals that saw it, in the order first seen.
    let signals: [DictationAppleSignal]
    /// How many times each signal fired during it.
    let signalCounts: [DictationAppleSignal: Int]
}

/// What the keyboard does after a tracker event.
enum DictationAppleEvent: Equatable, Sendable {
    /// Dictation was first seen, by this signal.
    case began(DictationAppleSignal)
    /// The dictated words so far changed.
    case heard(String)
    case ended(DictationAppleFinished)
}

/// The keyboard's view of Apple's dictation. Pure: the keyboard feeds it the text before the cursor,
/// the input mode and its own keys, with the time.
struct DictationAppleTracker: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        /// No dictation seen; `baseline` is the text before the cursor as Midas left it.
        case waiting
        case dictating
    }

    private(set) var phase: Phase = .waiting
    /// The text before the cursor with no dictation running (after the last Midas key or cleanup).
    private(set) var baseline = ""
    /// The text after the cursor then: dictation types at the cursor and leaves it as it is, so a
    /// change here is the cursor moving (the person tapped elsewhere), not dictation.
    private(set) var baselineAfter = ""
    /// The text before the cursor when the dictation began.
    private(set) var startContext = ""
    /// The words Apple added so far; nil when the span is unknown.
    private(set) var span: String? = ""
    private(set) var startedAt: Date?
    private(set) var lastChangeAt: Date?
    /// The input mode says dictation now.
    private(set) var modeSaysDictation = false
    private(set) var signals: [DictationAppleSignal] = []
    private(set) var signalCounts: [DictationAppleSignal: Int] = [:]
    private var lastMidasKeyAt: Date?

    /// The keyboard appeared, or a dictation was cleaned up: no dictation, this text as Midas's.
    mutating func reset(context: String?, after: String?) {
        baselineAfter = after ?? ""
        reset(context: context)
    }

    private mutating func reset(context: String?) {
        phase = .waiting
        baseline = context ?? ""
        startContext = baseline
        span = ""
        startedAt = nil
        lastChangeAt = nil
        modeSaysDictation = false
        signals = []
        signalCounts = [:]
    }

    /// A Midas key typed or deleted; `expected` is the text before the cursor after it.
    mutating func midasTyped(expected: String, at now: Date) {
        lastMidasKeyAt = now
        guard phase == .waiting else {
            return
        }
        baseline = expected
    }

    private mutating func count(_ signal: DictationAppleSignal) {
        if signalCounts[signal] == nil {
            signals.append(signal)
        }
        signalCounts[signal, default: 0] += 1
    }

    private mutating func begin(by signal: DictationAppleSignal, at now: Date) {
        phase = .dictating
        startContext = baseline
        span = ""
        startedAt = now
        lastChangeAt = now
        signals = []
        signalCounts = [:]
        count(signal)
    }

    /// The text before and after the cursor as read now (a poll, textDidChange or the keyboard
    /// appearing). A change before the cursor that Midas did not make counts as dictated; a change
    /// after it is the cursor moving.
    mutating func observed(context: String?, after: String?, by signal: DictationAppleSignal, at now: Date) -> [DictationAppleEvent] {
        let text = context ?? ""
        let afterText = after ?? ""
        switch phase {
        case .waiting:
            // The cursor moved: the text there is the person's, not dictated
            guard afterText == baselineAfter else {
                reset(context: text, after: afterText)
                return []
            }
            guard text != baseline else {
                return []
            }
            // A Midas key landing late in the host's text is not dictation
            if let lastMidasKeyAt, now.timeIntervalSince(lastMidasKeyAt) < DictationAppleConstants.midasKeyGrace {
                baseline = text
                return []
            }
            begin(by: signal, at: now)
            span = DictationAppleSpan.dictated(from: startContext, to: text)
            return [.began(signal), .heard(span ?? "")]
        case .dictating:
            count(signal)
            // The cursor moved during it: the span can no longer be told apart
            let newSpan = afterText == baselineAfter ? DictationAppleSpan.dictated(from: startContext, to: text) : nil
            guard newSpan != span else {
                return []
            }
            span = newSpan
            lastChangeAt = now
            return [.heard(newSpan ?? "")]
        }
    }

    /// textWillChange: counted while dictating; on its own it does not start a dictation (the
    /// text that follows does).
    mutating func textWillChange() {
        if phase == .dictating {
            count(.textWillChange)
        }
    }

    /// The input mode changed. Into dictation: a dictation begins (no words yet). Back from it: a
    /// running dictation ends.
    mutating func inputModeChanged(isDictation: Bool, at now: Date) -> [DictationAppleEvent] {
        let wasDictation = modeSaysDictation
        modeSaysDictation = isDictation
        if isDictation && !wasDictation {
            guard phase == .waiting else {
                count(.inputMode)
                return []
            }
            begin(by: .inputMode, at: now)
            return [.began(.inputMode)]
        }
        if !isDictation && wasDictation && phase == .dictating {
            count(.inputMode)
            return finish(.inputMode)
        }
        return []
    }

    /// Checked on every poll: no change for 1.5 s ends a dictation with words, unless the input
    /// mode still says dictation (then it ends when the mode goes back).
    mutating func tick(at now: Date) -> [DictationAppleEvent] {
        guard phase == .dictating, !modeSaysDictation, let lastChangeAt else {
            return []
        }
        guard now.timeIntervalSince(lastChangeAt) >= DictationAppleConstants.quietEnd else {
            return []
        }
        // Dictation seen with no words yet (a lost input-mode signal): nothing to clean
        let hasWords = span.map(Self.hasWords) ?? true
        guard hasWords else {
            reset(context: startContext)
            return []
        }
        return finish(.quiet)
    }

    /// The keyboard appeared again (iOS may hide it while Apple listens). A dictation seen before it
    /// hid ends with the text found now; in the same document, text added at the cursor while it
    /// was hidden counts as dictated too. Anything else (another field, another app) is the
    /// person's text: the new baseline.
    mutating func appeared(context: String?, after: String?, sameDocument: Bool, at now: Date) -> [DictationAppleEvent] {
        let wasDictating = phase == .dictating
        guard wasDictating || sameDocument else {
            reset(context: context, after: after)
            return []
        }
        // A Midas key long ago: no grace for the text found now
        lastMidasKeyAt = nil
        var events = observed(context: context, after: after, by: .appeared, at: now)
        guard phase == .dictating else {
            return events
        }
        let hasWords = span.map(Self.hasWords) ?? true
        guard hasWords else {
            reset(context: context, after: after)
            return []
        }
        modeSaysDictation = false
        events += finish(.keyboardShown)
        return events
    }

    /// Ends a running dictation now (a Midas key, the keyboard going away).
    mutating func end(_ reason: DictationAppleEnd) -> [DictationAppleEvent] {
        guard phase == .dictating else {
            return []
        }
        let hasWords = span.map(Self.hasWords) ?? true
        guard hasWords else {
            reset(context: startContext)
            return []
        }
        return finish(reason)
    }

    private mutating func finish(_ reason: DictationAppleEnd) -> [DictationAppleEvent] {
        let finished = DictationAppleFinished(span: span, end: reason, startedAt: startedAt ?? Date(), lastChangeAt: lastChangeAt ?? Date(),
                                              signals: signals, signalCounts: signalCounts)
        // Waiting again; the keyboard resets the baseline to the text after its cleanup
        phase = .waiting
        modeSaysDictation = false
        return [.ended(finished)]
    }

    private static func hasWords(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: The cleanup

/// What became of a dictation: cleaned up, or why not. The run record's `cleanup`.
enum DictationAppleCleanupResult: String, Codable, Equatable, Sendable, CaseIterable {
    /// The span was replaced with the gate's text.
    case applied
    /// The gate's text is the span as it is: nothing to replace.
    case unchanged
    /// settings:main appleCleanup is off.
    case off
    /// The text before the cursor no longer ends with the span.
    case textChanged = "text-changed"
    /// The span was only whitespace.
    case empty
    /// The text changed elsewhere, so the span is unknown.
    case contextLost = "context-lost"
}

/// How the keyboard replaces a span: delete this many characters, then insert this text.
struct DictationAppleCleanupPlan: Equatable, Sendable {
    let result: DictationAppleCleanupResult
    /// The dictated words, trimmed (the run's raw).
    let raw: String
    /// The gate's text (the run's cleaned); the raw words when the gate did not run.
    let cleaned: String
    let gate: DictationGateOutcome?
    /// Characters to delete backward from the cursor (only what differs from the cleaned text).
    let deleteCount: Int
    let insertText: String

    var replaces: Bool {
        result == .applied
    }
}

enum DictationAppleCleanup {
    /// settings:main appleCleanup: on when missing or not a true/false.
    static func isOn(_ settings: DictationGateSettings) -> Bool {
        settings.appleCleanup
    }

    /// The plan for one dictated span, with the text before the cursor now and the gate settings.
    static func plan(span: String?, contextNow: String?, settings: DictationGateSettings) -> DictationAppleCleanupPlan {
        guard let span else {
            return skipped(.contextLost, raw: "")
        }
        let parts = DictationAppleSpan.parts(of: span)
        guard !parts.core.isEmpty else {
            return skipped(.empty, raw: "")
        }
        guard settings.appleCleanup else {
            return skipped(.off, raw: parts.core)
        }
        let outcome = DictationKeyboardInsertText.make(raw: parts.core, settings: settings)
        // Fillers only: the cleaned text is nothing, and the span goes
        let cleaned = outcome?.text ?? ""
        let gate = outcome?.gate
        guard let contextNow, contextNow.hasSuffix(span) else {
            return DictationAppleCleanupPlan(result: .textChanged, raw: parts.core, cleaned: cleaned, gate: gate, deleteCount: 0, insertText: "")
        }
        let replacement = cleaned.isEmpty ? parts.leading : parts.leading + cleaned + parts.trailing
        guard replacement != span else {
            return DictationAppleCleanupPlan(result: .unchanged, raw: parts.core, cleaned: cleaned, gate: gate, deleteCount: 0, insertText: "")
        }
        // Only what differs: the shared start stays where it is
        let shared = sharedPrefixCount(span, replacement)
        let deleteCount = span.count - shared
        let insertText = String(replacement.dropFirst(shared))
        return DictationAppleCleanupPlan(result: .applied, raw: parts.core, cleaned: cleaned, gate: gate, deleteCount: deleteCount, insertText: insertText)
    }

    private static func skipped(_ result: DictationAppleCleanupResult, raw: String) -> DictationAppleCleanupPlan {
        DictationAppleCleanupPlan(result: result, raw: raw, cleaned: raw, gate: nil, deleteCount: 0, insertText: "")
    }

    /// How many characters two texts share at their start.
    static func sharedPrefixCount(_ first: String, _ second: String) -> Int {
        var shared = 0
        for (firstCharacter, secondCharacter) in zip(first, second) {
            guard firstCharacter == secondCharacter else {
                break
            }
            shared += 1
        }
        return shared
    }

    /// The text before the cursor after the plan is carried out (the tracker's new baseline).
    static func contextAfter(_ plan: DictationAppleCleanupPlan, contextNow: String?) -> String {
        let text = contextNow ?? ""
        guard plan.replaces else {
            return text
        }
        return String(text.dropLast(plan.deleteCount)) + plan.insertText
    }
}

// MARK: The run Midas Test saves

/// One Apple dictation the keyboard saw, waiting in the App Group for Midas Test to save as a
/// `dictation.run` (source keyboard, mic apple).
struct DictationAppleRun: Codable, Equatable, Sendable {
    let id: String
    /// What Apple typed (trimmed).
    let raw: String
    /// The gate's text; the raw words when the gate did not run.
    let cleaned: String
    let cleanup: DictationAppleCleanupResult
    let end: DictationAppleEnd
    let path: String?
    let trigger: String?
    let matched: [String]
    let gateMs: Double?
    /// The last change to the dictated text.
    let lastChangeAt: Date
    /// When the cleanup went in, or was skipped.
    let cleanedAt: Date
    let thermal: String
    let signals: [DictationAppleSignal]

    init(id: String, plan: DictationAppleCleanupPlan, finished: DictationAppleFinished, cleanedAt: Date, thermal: DictationThermal) {
        self.id = id
        self.raw = plan.raw
        self.cleaned = plan.cleaned
        self.cleanup = plan.result
        self.end = finished.end
        self.path = plan.gate?.decision.path.rawValue
        self.trigger = plan.gate?.decision.trigger
        self.matched = plan.gate?.decision.matched ?? []
        self.gateMs = plan.gate?.gateMs
        self.lastChangeAt = finished.lastChangeAt
        self.cleanedAt = cleanedAt
        self.thermal = thermal.rawValue
        self.signals = finished.signals
    }

    /// The gate's outcome again; nil when the gate did not run or its path is unknown here.
    var gateOutcome: DictationGateOutcome? {
        guard let path, let decodedPath = DictationPath(rawValue: path), let gateMs else {
            return nil
        }
        let decision = DictationGateDecision(path: decodedPath, trigger: trigger, matched: matched, text: cleaned, instruction: nil)
        return DictationGateOutcome(decision: decision, gateMs: gateMs)
    }
}

/// The keyboard log's lines for Apple dictation (each one 300 characters at most).
enum DictationAppleLog {
    /// "text-did-change 12, poll 30, input-mode 2", in the order first seen.
    static func countsDetail(_ finished: DictationAppleFinished) -> String {
        var parts: [String] = []
        for signal in finished.signals {
            parts.append(signal.rawValue + " " + String(finished.signalCounts[signal] ?? 0))
        }
        return parts.isEmpty ? "no signals" : parts.joined(separator: ", ")
    }

    /// "applied: deleted 3, inserted 27" or "skipped: text-changed".
    static func cleanupDetail(_ plan: DictationAppleCleanupPlan) -> String {
        switch plan.result {
        case .applied:
            return "applied: deleted \(plan.deleteCount), inserted \(plan.insertText.count), \"" + plan.cleaned + "\""
        case .unchanged:
            return "unchanged: \"" + plan.cleaned + "\""
        default:
            return "skipped: " + plan.result.rawValue
        }
    }
}
#endif
