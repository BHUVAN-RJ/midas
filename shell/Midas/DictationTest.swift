#if MIDAS_TEST_BUILD
// Dictation test (TEST BUILD, founder 2026-11-13; branch agent/dictation-test, never merged).
// Measures on-device cleanup of dictated text with Apple's Foundation Models framework, on top of
// the shared on-device transcriber. Compiled only in the Test configuration (MIDAS_TEST_BUILD).
import Foundation
import FoundationModels

/// The cleanup instruction and the prompt built from raw dictated text.
enum DictationCleanup {
    /// The light cleanup instruction built into the app (the gate's light path). The Dictation
    /// Sidekick's settings:main can replace it without a rebuild (DictationGateSettings).
    static let instructions = DictationGateSettings.builtInLightInstruction

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

    // The gate's phrases (docs/briefs/dictation-gate-test.md), with the path each should take
    static let shortNames = "send the deck to Priya by friday"
    static let emailTrigger = "email tell sam the launch moved to monday and thank him for the help"
    static let scratchThat = "the browser is firefox scratch that chrome"
    static let listTrigger = "list eggs milk bread coffee"

    static let gatePhrases = [shortNames, emailTrigger, scratchThat, listTrigger]

    /// Round 1's nine: the first five, then the gate's four. Since round 2 the screen and Run All
    /// use settings:main's phrases (DictationGateSettings.builtInPhrases starts with these nine).
    static let every = all + gatePhrases

    /// The path each phrase is expected to take with the built-in settings.
    static let expectedPaths: [String: DictationPath] = [
        deadline: .light, mom: .light, groceries: .light, names: .skip, rambling: .light,
        shortNames: .skip, emailTrigger: .rewrite, scratchThat: .light, listTrigger: .rewrite,
    ]

    /// Number of times "Run all" runs each phrase.
    static let runAllRepeats = 5
}

/// Run All's tally of the path each phrase should take against the path the gate took.
struct DictationPathCheck: Equatable, Sendable {
    /// Runs counted.
    private(set) var checked = 0
    /// Runs whose path was not the expected one.
    private(set) var wrong = 0
    /// Each phrase that took a wrong path, with the path it should have taken.
    private(set) var wrongPhrases: [String: DictationPath] = [:]

    mutating func add(phrase: String, expected: DictationPath, actual: DictationPath) {
        checked += 1
        guard expected != actual else {
            return
        }
        wrong += 1
        wrongPhrases[phrase] = expected
    }

    /// "Wrong Path 0 of 165".
    var label: String {
        "Wrong Path \(wrong) of \(checked)"
    }
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
/// screen opened, so first and warm calls can be told apart. A session's instruction is fixed when
/// it is made, so the prewarmed one is used only when the call wants the same instruction.
@available(iOS 26, *)
@MainActor
final class DictationCleaner {
    private var prewarmedSession: LanguageModelSession?
    private var prewarmedInstructions: String?
    private(set) var callCount = 0

    private static func makeSession(instructions: String) -> LanguageModelSession {
        LanguageModelSession(instructions: instructions)
    }

    /// Loads the model and the instruction ahead of the first call.
    func prewarm(instructions: String = DictationCleanup.instructions) {
        let session = Self.makeSession(instructions: instructions)
        session.prewarm()
        prewarmedSession = session
        prewarmedInstructions = instructions
    }

    /// Nil when the raw text is empty.
    func clean(_ rawText: String, instructions: String = DictationCleanup.instructions) async throws -> DictationCleanupResult? {
        guard let prompt = DictationCleanup.prompt(for: rawText) else {
            return nil
        }
        let session: LanguageModelSession
        if let prewarmed = prewarmedSession, prewarmedInstructions == instructions {
            session = prewarmed
        } else {
            session = Self.makeSession(instructions: instructions)
        }
        prewarmedSession = nil
        prewarmedInstructions = nil
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
