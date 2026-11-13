#if MIDAS_TEST_BUILD
// Dictation test (TEST BUILD, founder 2026-11-13; branch agent/dictation-test, never merged).
// Measures on-device cleanup of dictated text with Apple's Foundation Models framework, on top of
// the shared on-device transcriber. Compiled only in the Test configuration (MIDAS_TEST_BUILD).
import Foundation
import FoundationModels

/// The cleanup instruction and the prompt built from raw dictated text.
enum DictationCleanup {
    /// The one place to tune the cleanup instruction.
    static let instructions = """
    You clean up dictated text. Rules:
    1. Remove filler words: um, uh, like, so, you know, I mean, when they are fillers.
    2. Apply self-corrections: keep only the corrected version. "be there at 5 no wait 6" becomes "Be there at 6."
    3. Add punctuation and capital letters, including names and the start of each sentence.
    4. Keep the person's own words otherwise. Do not rephrase, summarise or translate.
    5. Add nothing: no greeting, no explanation, no quotes, no notes.
    Reply with the cleaned text only, as plain text.
    """

    /// The prompt for one dictation; nil when there is nothing to clean.
    static func prompt(for rawText: String) -> String? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return "Dictated text:\n\(trimmed)"
    }

    /// The model's reply as plain text: surrounding whitespace and one pair of wrapping quotes
    /// removed (the model sometimes quotes its answer despite rule 5).
    static func plainText(fromReply reply: String) -> String {
        var text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”")]
        for (opening, closing) in quotePairs {
            let isWrapped = text.count >= 2 && text.first == opening && text.last == closing
            if isWrapped {
                text = String(text.dropFirst().dropLast())
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }
}

/// The five fixed phrases: cleanup only, no speaking, so timings repeat.
enum DictationTestPhrases {
    static let deadline = "um so like be there at 5 no wait 6"
    static let mom = "uh tell mom im on my way"
    static let groceries = "buy eggs milk and uh bread oh and coffee"
    static let names = "send the deck to Priya and Tomasz by friday"
    /// 60 words of rambling.
    static let rambling = "so um I was thinking that maybe we could like move the team meeting to thursday because uh on wednesday half the people are out and also I need to finish the budget numbers before we talk about them no wait actually the budget is due friday so thursday morning works and um can someone book the big room please"

    static let all = [deadline, mom, groceries, names, rambling]

    /// Number of times "Run all" runs each phrase.
    static let runAllRepeats = 5
}

/// Milliseconds between two moments; never negative.
enum DictationTiming {
    static func milliseconds(from start: Date, to end: Date) -> Int {
        let seconds = end.timeIntervalSince(start)
        return max(0, Int((seconds * 1000).rounded()))
    }
}

/// One spoken dictation: release → final raw text, cleanup start → cleaned text, total.
struct DictationTimings: Equatable, Sendable {
    let releaseToRawMs: Int
    let cleanupMs: Int
    /// Release to cleaned text, including any gap between the raw text and the cleanup start.
    let totalMs: Int

    init(releasedAt: Date, rawFinalAt: Date, cleanupStartedAt: Date, cleanedAt: Date) {
        releaseToRawMs = DictationTiming.milliseconds(from: releasedAt, to: rawFinalAt)
        cleanupMs = DictationTiming.milliseconds(from: cleanupStartedAt, to: cleanedAt)
        totalMs = DictationTiming.milliseconds(from: releasedAt, to: cleanedAt)
    }
}

/// Average and worst cleanup time for one phrase over several runs.
struct DictationRunSummary: Equatable, Sendable {
    let phrase: String
    let averageMs: Int
    let worstMs: Int
    let runCount: Int

    /// Nil when there were no runs.
    static func make(phrase: String, durationsMs: [Int]) -> DictationRunSummary? {
        guard let worst = durationsMs.max() else {
            return nil
        }
        let sum = durationsMs.reduce(0, +)
        let average = Int((Double(sum) / Double(durationsMs.count)).rounded())
        return DictationRunSummary(phrase: phrase, averageMs: average, worstMs: worst, runCount: durationsMs.count)
    }
}

/// Whether the on-device model can run, and why not.
enum DictationModelStatus: Equatable, Sendable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    /// A reason added by a later iOS; its description.
    case unavailableOther(String)
    /// iOS before 26: no Foundation Models framework.
    case osTooOld

    var isAvailable: Bool {
        self == .available
    }

    var label: String {
        switch self {
        case .available:
            return "Available"
        case .deviceNotEligible:
            return "Not available: device not eligible"
        case .appleIntelligenceNotEnabled:
            return "Not available: Apple Intelligence is off"
        case .modelNotReady:
            return "Not available: model not ready (downloading)"
        case .unavailableOther(let reason):
            return "Not available: \(reason)"
        case .osTooOld:
            return "Not available: needs iOS 26"
        }
    }

    @available(iOS 26, *)
    static func from(_ availability: SystemLanguageModel.Availability) -> DictationModelStatus {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            return from(reason: reason)
        }
    }

    @available(iOS 26, *)
    static func from(reason: SystemLanguageModel.Availability.UnavailableReason) -> DictationModelStatus {
        switch reason {
        case .deviceNotEligible:
            return .deviceNotEligible
        case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
        case .modelNotReady:
            return .modelNotReady
        @unknown default:
            return .unavailableOther(String(describing: reason))
        }
    }

    /// The model's status on this phone right now.
    static func current() -> DictationModelStatus {
        guard #available(iOS 26, *) else {
            return .osTooOld
        }
        return from(SystemLanguageModel.default.availability)
    }
}

/// One cleanup result: the text, how long it took, and whether it was the first call.
struct DictationCleanupResult: Equatable, Sendable {
    let cleanedText: String
    let durationMs: Int
    let isFirstCall: Bool
}

/// Runs cleanup on the on-device model. A new session per call (a session keeps its history and
/// would fill its context over "Run all"); the first call uses the session prewarmed when the
/// screen opened, so first and warm calls can be told apart.
@available(iOS 26, *)
@MainActor
final class DictationCleaner {
    private var prewarmedSession: LanguageModelSession?
    private(set) var callCount = 0

    private static func makeSession() -> LanguageModelSession {
        LanguageModelSession(instructions: DictationCleanup.instructions)
    }

    /// Loads the model and the instruction ahead of the first call.
    func prewarm() {
        let session = Self.makeSession()
        session.prewarm()
        prewarmedSession = session
    }

    /// Nil when the raw text is empty.
    func clean(_ rawText: String) async throws -> DictationCleanupResult? {
        guard let prompt = DictationCleanup.prompt(for: rawText) else {
            return nil
        }
        let session = prewarmedSession ?? Self.makeSession()
        prewarmedSession = nil
        let isFirstCall = callCount == 0
        callCount += 1
        // Greedy: the same phrase gives the same answer, so only the timing varies between runs
        let options = GenerationOptions(sampling: .greedy)
        let startedAt = Date()
        let response = try await session.respond(to: prompt, options: options)
        let durationMs = DictationTiming.milliseconds(from: startedAt, to: Date())
        let cleaned = DictationCleanup.plainText(fromReply: response.content)
        return DictationCleanupResult(cleanedText: cleaned, durationMs: durationMs, isFirstCall: isFirstCall)
    }
}
#endif
