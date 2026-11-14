#if MIDAS_TEST_BUILD
// Dictation cleanup gate (TEST BUILD, founder 2026-11-13; docs/briefs/dictation-gate-test.md;
// branch agent/dictation-test, never merged). Compiled only in the Test configuration.
//
// Rules only, no model. After the raw text is final, one of three paths:
//
//   rewrite  the text starts with a trigger word ("email", "list", ...), followed by a space, a
//            colon, a comma or nothing else: the trigger is stripped and the rest goes to the
//            model with that trigger's instruction.
//   light    a filler or a correction cue is in the text: the light cleanup instruction.
//   skip     neither: the raw text as heard, with a capital first letter and end punctuation added
//            by rule. No model call.
//
// Matching is whole-word and case-insensitive; a phrase ("no wait") matches consecutive words.
// Position rule for the words in `positionFillers` ("like", "so"): they count as fillers only
//   - at the start of the text or of a sentence (after . ! ?), or
//   - next to a comma (", like," / "so, ..."), or
//   - next to another counted filler ("um so like": "so" is next to "um", "like" next to "so").
// Everywhere else ("I like it", "it is so good") they are words, not fillers.
//
// The lists and instructions live in the Dictation Sidekick's `settings:main` record, so they can
// be tuned without a rebuild; DictationGateSettings.builtIn is the fallback.
import Foundation

/// Which way a dictation goes after the gate.
enum DictationPath: String, Equatable, Sendable, CaseIterable {
    case skip
    case light
    case rewrite
}

/// A word at the start of a dictation that asks for a rewrite ("email ..."), and how.
struct DictationTrigger: Equatable, Sendable {
    let word: String
    let instruction: String
}

/// What the gate matches and the instructions the model gets.
struct DictationGateSettings: Equatable, Sendable {
    /// Always fillers, wherever they are.
    let fillers: [String]
    /// Fillers only by position (see the rule at the top of this file).
    let positionFillers: [String]
    let corrections: [String]
    let triggers: [DictationTrigger]
    let lightInstruction: String

    static let settingsKey = "settings:main"
    static let maxListItems = 50
    static let maxPhraseCharacters = 40
    static let maxTriggers = 20
    static let maxTriggerCharacters = 30
    static let maxInstructionCharacters = 4000

    /// The tightened light instruction (fillers, self-corrections, punctuation, numbered lists).
    static let builtInLightInstruction = """
    You clean up dictated text. Rules:
    1. Remove filler words: um, uh, erm, hmm, like, so, you know, I mean, sort of, kind of, basically, when they are fillers.
    2. Apply self-corrections: when the speaker corrects themselves (no wait, scratch that, I mean, actually, make that), keep only the corrected version. "be there at 5 no wait 6" becomes "Be there at 6."
    3. Add punctuation and capital letters, including names and the start of each sentence.
    4. When the speaker lists several items in a row, write them as a numbered list, one item per line.
    5. Keep the person's own words otherwise. Never change pronouns, names, numbers or meaning, except what a correction explicitly replaces: "I" stays "I", "you" stays "you". Do not rephrase, summarise or translate.
    6. Add nothing: never add words, greetings, explanations, quotes or notes.
    Reply with the cleaned text only, as plain text.
    """

    static let builtInTriggers: [DictationTrigger] = [
        DictationTrigger(word: "email", instruction: """
        Turn the dictated text into a short email to the person it names. Remove filler words and apply self-corrections. "tell Sam X" becomes a message to Sam saying X. Keep every fact, name, number and time as said. Start with "Hi <name>," and end with "Thanks" on its own line. No subject line, no notes. Reply with the email only, as plain text.
        """),
        DictationTrigger(word: "formal", instruction: """
        Rewrite the dictated text in a formal, polite tone. Remove filler words and apply self-corrections. Keep every fact, name, number and time as said. Add no new content. Reply with the rewritten text only, as plain text.
        """),
        DictationTrigger(word: "casual", instruction: """
        Rewrite the dictated text in a casual, friendly tone. Remove filler words and apply self-corrections. Keep every fact, name, number and time as said. Add no new content. Reply with the rewritten text only, as plain text.
        """),
        DictationTrigger(word: "list", instruction: """
        Turn the dictated text into a bulleted list: one item per line, each line starting with "- ". Split the items where the speaker lists them, even without commas or "and". Remove filler words and apply self-corrections. Capitalise each item. No heading, nothing else. Reply with the list only, as plain text.
        """),
        DictationTrigger(word: "bullets", instruction: """
        Turn the dictated text into short bullet points, one point per line, each line starting with "- ". Remove filler words and apply self-corrections. Keep every fact, name, number and time as said. No heading, nothing else. Reply with the bullets only, as plain text.
        """),
    ]

    static let builtIn = DictationGateSettings(
        fillers: ["um", "uh", "erm", "hmm", "you know", "I mean", "sort of", "kind of", "basically"],
        positionFillers: ["like", "so"],
        corrections: ["no wait", "wait no", "scratch that", "I mean", "actually", "sorry", "no no", "make that", "I meant"],
        triggers: builtInTriggers,
        lightInstruction: builtInLightInstruction
    )

    /// The settings a stored `settings:main` holds; nil when it is missing or does not fit (then
    /// the built-in ones are used, see `resolved`).
    static func from(_ value: JSONValue?) -> DictationGateSettings? {
        guard let value, value.objectValue != nil else {
            return nil
        }
        guard let fillers = phraseList(value["fillers"]),
              let positionFillers = phraseList(value["positionFillers"]),
              let corrections = phraseList(value["corrections"]),
              let triggers = triggerList(value["triggers"]),
              let lightInstruction = instruction(value["lightInstruction"]) else {
            return nil
        }
        return DictationGateSettings(fillers: fillers, positionFillers: positionFillers, corrections: corrections, triggers: triggers,
                                     lightInstruction: lightInstruction)
    }

    /// The stored settings, or the built-in ones; `isSaved` says which.
    static func resolved(_ value: JSONValue?) -> (settings: DictationGateSettings, isSaved: Bool) {
        if let stored = from(value) {
            return (stored, true)
        }
        return (builtIn, false)
    }

    /// The record the page writes, from these settings (the same shape `from` reads).
    var recordValue: JSONValue {
        var triggerValues: [JSONValue] = []
        for trigger in triggers {
            triggerValues.append(.object(["word": .string(trigger.word), "instruction": .string(trigger.instruction)]))
        }
        return .object([
            "fillers": .array(fillers.map(JSONValue.string)),
            "positionFillers": .array(positionFillers.map(JSONValue.string)),
            "corrections": .array(corrections.map(JSONValue.string)),
            "triggers": .array(triggerValues),
            "lightInstruction": .string(lightInstruction),
        ])
    }

    // A phrase: 1 to 40 characters with at least one letter or digit
    private static func phrase(_ value: JSONValue, maxCharacters: Int) -> String? {
        guard let text = value.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= maxCharacters,
              text.contains(where: isLetterOrNumber) else {
            return nil
        }
        return text
    }

    private static func isLetterOrNumber(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func phraseList(_ value: JSONValue?) -> [String]? {
        guard let items = value?.arrayValue, items.count <= maxListItems else {
            return nil
        }
        var phrases: [String] = []
        for item in items {
            guard let text = phrase(item, maxCharacters: maxPhraseCharacters) else {
                return nil
            }
            phrases.append(text)
        }
        return phrases
    }

    private static func instruction(_ value: JSONValue?) -> String? {
        guard let text = value?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= maxInstructionCharacters else {
            return nil
        }
        return text
    }

    private static func triggerList(_ value: JSONValue?) -> [DictationTrigger]? {
        guard let items = value?.arrayValue, items.count <= maxTriggers else {
            return nil
        }
        var triggers: [DictationTrigger] = []
        for item in items {
            guard let wordValue = item["word"],
                  let word = phrase(wordValue, maxCharacters: maxTriggerCharacters),
                  let triggerInstruction = instruction(item["instruction"]) else {
                return nil
            }
            triggers.append(DictationTrigger(word: word, instruction: triggerInstruction))
        }
        return triggers
    }
}

/// The gate's answer for one dictation.
struct DictationGateDecision: Equatable, Sendable {
    let path: DictationPath
    /// The trigger word as the settings spell it; rewrite only.
    let trigger: String?
    /// The filler and correction phrases found, as the settings spell them, in the order heard.
    let matched: [String]
    /// What goes on: the raw text for light, the text after the trigger for rewrite, the tidied
    /// text (inserted as is) for skip.
    let text: String
    /// The model instruction; nil for skip.
    let instruction: String?
}

/// The rules: words, phrase matching, the position rule, triggers, the skip tidy-up.
enum DictationGate {
    /// One word of the text and what is around it.
    struct Word: Equatable {
        let text: String
        /// Where the word starts in the original text.
        let start: String.Index
        /// The characters between the previous word (or the start) and this one.
        let before: String
        /// The characters between this word and the next (or the end).
        var after: String
    }

    private static let sentenceEnds: Set<Character> = [".", "!", "?", "…"]

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "'" || character == "’"
    }

    /// The words of a text, lowercased, with the characters around each.
    static func words(in text: String) -> [Word] {
        var found: [Word] = []
        var index = text.startIndex
        var gap = ""
        while index < text.endIndex {
            let character = text[index]
            guard isWordCharacter(character) else {
                gap.append(character)
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, isWordCharacter(text[index]) {
                index = text.index(after: index)
            }
            if !found.isEmpty {
                found[found.count - 1].after = gap
            }
            let wordText = text[start..<index].lowercased().replacingOccurrences(of: "’", with: "'")
            found.append(Word(text: wordText, start: start, before: gap, after: ""))
            gap = ""
        }
        if !found.isEmpty {
            found[found.count - 1].after = gap
        }
        return found
    }

    /// Where a phrase's words occur in the text, as ranges of word positions.
    static func occurrences(of phrase: String, in textWords: [Word]) -> [Range<Int>] {
        let phraseWords = words(in: phrase).map(\.text)
        guard !phraseWords.isEmpty, phraseWords.count <= textWords.count else {
            return []
        }
        var ranges: [Range<Int>] = []
        for startIndex in 0...(textWords.count - phraseWords.count) {
            var isMatch = true
            for (offset, phraseWord) in phraseWords.enumerated() where textWords[startIndex + offset].text != phraseWord {
                isMatch = false
                break
            }
            if isMatch {
                ranges.append(startIndex..<(startIndex + phraseWords.count))
            }
        }
        return ranges
    }

    private static func startsASentence(_ position: Int, in textWords: [Word]) -> Bool {
        if position == 0 {
            return true
        }
        return textWords[position].before.contains(where: sentenceEnds.contains)
    }

    // Set off by a comma: a comma just before the first word or just after the last
    private static func touchesAComma(_ range: Range<Int>, in textWords: [Word]) -> Bool {
        let commaBefore = textWords[range.lowerBound].before.contains(",")
        let commaAfter = textWords[range.upperBound - 1].after.contains(",")
        return commaBefore || commaAfter
    }

    private static func isNextToCounted(_ range: Range<Int>, counted: Set<Int>) -> Bool {
        counted.contains(range.lowerBound - 1) || counted.contains(range.upperBound)
    }

    /// One phrase found in the text: which list entry, where.
    private struct Hit {
        let phrase: String
        let range: Range<Int>
    }

    /// The fillers and correction cues in the text, as the settings spell them, in the order they
    /// first occur (each once).
    static func matches(in textWords: [Word], settings: DictationGateSettings) -> [String] {
        var hits: [Hit] = []
        var counted = Set<Int>()
        for phrase in settings.fillers + settings.corrections {
            for range in occurrences(of: phrase, in: textWords) {
                hits.append(Hit(phrase: phrase, range: range))
                counted.formUnion(range)
            }
        }
        // Position fillers, repeated until nothing new counts (a chain like "um so like")
        var waiting: [Hit] = []
        for phrase in settings.positionFillers {
            for range in occurrences(of: phrase, in: textWords) {
                waiting.append(Hit(phrase: phrase, range: range))
            }
        }
        var addedOne = true
        while addedOne {
            addedOne = false
            var stillWaiting: [Hit] = []
            for hit in waiting {
                let counts = startsASentence(hit.range.lowerBound, in: textWords) || touchesAComma(hit.range, in: textWords)
                    || isNextToCounted(hit.range, counted: counted)
                if counts {
                    hits.append(hit)
                    counted.formUnion(hit.range)
                    addedOne = true
                } else {
                    stillWaiting.append(hit)
                }
            }
            waiting = stillWaiting
        }
        hits.sort(by: isEarlier)
        var seen = Set<String>()
        var ordered: [String] = []
        for hit in hits where !seen.contains(hit.phrase.lowercased()) {
            seen.insert(hit.phrase.lowercased())
            ordered.append(hit.phrase)
        }
        return ordered
    }

    private static func isEarlier(_ first: Hit, _ second: Hit) -> Bool {
        if first.range.lowerBound != second.range.lowerBound {
            return first.range.lowerBound < second.range.lowerBound
        }
        return first.range.count > second.range.count
    }

    /// The trigger the text starts with and the text after it; nil when it starts with none, or
    /// when nothing follows the trigger. Only a space, a colon or a comma may follow the trigger.
    static func trigger(in text: String, textWords: [Word], settings: DictationGateSettings) -> (trigger: DictationTrigger, rest: String)? {
        guard let first = textWords.first, first.before.allSatisfy(\.isWhitespace) else {
            return nil
        }
        for trigger in settings.triggers {
            let triggerWords = words(in: trigger.word).map(\.text)
            guard !triggerWords.isEmpty, triggerWords.count < textWords.count else {
                continue
            }
            var isMatch = true
            for (offset, triggerWord) in triggerWords.enumerated() where textWords[offset].text != triggerWord {
                isMatch = false
                break
            }
            // Inside a multi-word trigger only spaces; after it only a space, ":" or ","
            for offset in 1..<triggerWords.count where !textWords[offset].before.allSatisfy(\.isWhitespace) {
                isMatch = false
            }
            let following = textWords[triggerWords.count]
            let allowedAfter = following.before.allSatisfy(isSpaceColonOrComma)
            guard isMatch, allowedAfter else {
                continue
            }
            let rest = String(text[following.start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (trigger, rest)
        }
        return nil
    }

    private static func isColonOrComma(_ character: Character) -> Bool {
        character == ":" || character == ","
    }

    private static func isSpaceColonOrComma(_ character: Character) -> Bool {
        character.isWhitespace || isColonOrComma(character)
    }

    /// The raw text as inserted on the skip path: a capital first letter, and a full stop when it
    /// ends without . ! ? (a trailing , ; : is replaced).
    static func tidy(_ rawText: String) -> String {
        var text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return text
        }
        if let first = text.first, first.isLetter {
            let capital = String(first).uppercased()
            text.replaceSubrange(text.startIndex...text.startIndex, with: capital)
        }
        while let last = text.last, [",", ";", ":"].contains(last) {
            text.removeLast()
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if let last = text.last, !sentenceEnds.contains(last) {
            text.append(".")
        }
        return text
    }

    /// The path for one dictation.
    static func decide(_ rawText: String, settings: DictationGateSettings) -> DictationGateDecision {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textWords = words(in: text)
        if let found = trigger(in: text, textWords: textWords, settings: settings) {
            let restWords = words(in: found.rest)
            let matched = matches(in: restWords, settings: settings)
            return DictationGateDecision(path: .rewrite, trigger: found.trigger.word, matched: matched, text: found.rest,
                                         instruction: found.trigger.instruction)
        }
        let matched = matches(in: textWords, settings: settings)
        if matched.isEmpty {
            return DictationGateDecision(path: .skip, trigger: nil, matched: [], text: tidy(text), instruction: nil)
        }
        return DictationGateDecision(path: .light, trigger: nil, matched: matched, text: text, instruction: settings.lightInstruction)
    }
}

/// Milliseconds from a ContinuousClock duration, to 0.01 ms (the gate takes well under 1 ms).
enum DictationGateTiming {
    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        let milliseconds = Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
        return (max(0, milliseconds) * 100).rounded() / 100
    }
}
#endif
