#if MIDAS_TEST_BUILD
// Dictation cleanup gate (TEST BUILD, founder 2026-11-13; docs/briefs/dictation-gate-test.md;
// branch agent/dictation-test, never merged). Compiled only in the Test configuration.
//
// Rules first (round 3, founder 2026-11-14: "do less, rules first"; the model does at most one
// small job). After the raw text is final, one of four paths:
//
//   rewrite  the text starts with a trigger word, followed by a space, a colon, a comma or
//            nothing else: the trigger is stripped and the rest goes to the model with that
//            trigger's instruction. The built-in trigger list is empty since round 3 (the five
//            instructions in `builtInTriggers` are parked, not in the default list).
//   rule     fillers removed and/or a simple correction applied, by rule. No model call.
//   light    a correction the simple rule cannot apply: the text after the filler rule goes to
//            the model with the light instruction (one line, no examples).
//   skip     nothing to change but casing and punctuation. No model call.
//
// Filler rule: every `fillers` entry (and every counted `positionFillers` entry) is removed as
//   whole words, case-insensitive, with any comma next to it ("we need, uh, cups" → "we need
//   cups"). A word in both the fillers and the corrections counts as a correction.
// Simple correction rule: exactly one correction cue, followed by exactly one token and nothing
//   else; the token is a number (digits or one to twelve), a time (5:30, 5pm, 5 pm), a weekday or
//   a month. The last token of the same kind before the cue is replaced by it; the cue and the
//   words after the replaced token up to the cue stay, the cue goes ("order 3 pizzas make that 4"
//   → "order 4 pizzas"). No same-kind token before the cue, two cues, or anything else after
//   the cue → light.
// Finishing, on every path's output (`finished`): the capitalise list's spelling, "i" → "I"
//   (also i'm, i'll, i've, i'd), a capital first letter and end punctuation.
//
// Matching is whole-word and case-insensitive; a phrase ("no wait") matches consecutive words.
// Position rule for the words in `positionFillers` ("like", "so"): they count as fillers only
//   - at the start of the text or of a sentence (after . ! ?), or
//   - next to a comma (", like," / "so, ..."), or
//   - next to another counted filler ("um so like": "so" is next to "um", "like" next to "so").
// Everywhere else ("I like it", "it is so good") they are words, not fillers.
//
// The lists, instructions, the capitalise list and the test phrases live in the Dictation
// Sidekick's `settings:main` record, so they can be tuned without a rebuild;
// DictationGateSettings.builtIn is the fallback.
import Foundation

/// Which way a dictation goes after the gate.
enum DictationPath: String, Equatable, Sendable, CaseIterable {
    case skip
    /// Round 3: fillers removed and/or a simple correction applied by rule, no model.
    case rule
    case light
    case rewrite
}

/// A word at the start of a dictation that asks for a rewrite ("email ..."), and how.
struct DictationTrigger: Equatable, Sendable {
    let word: String
    let instruction: String
}

/// A test phrase for the Dictation Test screen and the path the gate should take for it (round 2,
/// founder 2026-11-13: the phrases live in settings:main so a new round needs no rebuild).
struct DictationTestPhrase: Equatable, Sendable {
    let text: String
    let expect: DictationPath
    /// What the phrase tests ("backtrack"); nil when none.
    var note: String? = nil
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
    /// The Dictation Test screen's phrases (Run All runs each ×5); optional in the record, the
    /// built-in ones when it has none.
    var phrases: [DictationTestPhrase] = DictationGateSettings.builtInPhrases
    /// Words written with this spelling on the skip path ("friday" → "Friday"); optional in the
    /// record, the built-in ones when it has none.
    var capitalise: [String] = DictationGateSettings.builtInCapitalise
    /// How many times Run All runs each phrase (the record's `repeat`; round 3, was a fixed 5);
    /// optional in the record, the built-in 3 when it has none.
    var repeatCount: Int = DictationGateSettings.builtInRepeat

    static let settingsKey = "settings:main"
    static let builtInRepeat = 3
    static let maxRepeat = 20
    static let maxListItems = 50
    static let maxPhraseCharacters = 40
    static let maxTriggers = 20
    static let maxTriggerCharacters = 30
    static let maxInstructionCharacters = 4000
    static let maxPhrases = 60
    static let maxPhraseTextCharacters = 1000
    static let maxNoteCharacters = 200

    /// The light instruction (round 3, founder 2026-11-14): one line, no examples. The model gets
    /// only the corrections the rules cannot apply; round 2's examples were copied into answers.
    static let builtInLightInstruction = "Remove the correction and the words it replaces. Change nothing else. Reply with the text only."

    /// Days and months. "May" is left out: in dictation it is nearly always the verb.
    static let builtInCapitalise = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        "January", "February", "March", "April", "June", "July", "August", "September", "October", "November", "December",
    ]

    /// Round 3's fifteen (founder 2026-11-14), replacing round 2's 33: the most frequent cases
    /// only. Each `expect` is what the built-in gate decides.
    static let builtInPhrases: [DictationTestPhrase] = [
        DictationTestPhrase(text: "send the deck to Priya by friday", expect: .skip),
        DictationTestPhrase(text: "lunch with Maya on tuesday at 12:30", expect: .skip),
        DictationTestPhrase(text: "I like the new logo a lot", expect: .skip, note: "like as a word"),
        DictationTestPhrase(text: "it was so good to see you yesterday", expect: .skip, note: "so as a word"),
        DictationTestPhrase(text: "call David back before 5 tomorrow", expect: .skip),
        DictationTestPhrase(text: "uh tell mom im on my way", expect: .rule, note: "filler"),
        DictationTestPhrase(text: "um pack the charger the passport and the tickets", expect: .rule, note: "filler"),
        DictationTestPhrase(text: "for the party we need uh cups plates napkins and ice", expect: .rule, note: "filler"),
        DictationTestPhrase(text: "the call is at 2 no wait 3", expect: .rule, note: "correction"),
        DictationTestPhrase(text: "order 3 pizzas make that 4", expect: .rule, note: "correction"),
        DictationTestPhrase(text: "book the table for friday no wait saturday", expect: .rule, note: "correction"),
        DictationTestPhrase(text: "um be there at 5 no wait 6", expect: .rule, note: "correction"),
        DictationTestPhrase(text: "the browser is firefox scratch that chrome", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "send it to Tom I mean Tim", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "meet at the cafe on 5th street scratch that the library", expect: .light, note: "backtrack"),
    ]

    /// Parked since round 3 (founder 2026-11-14): built in, not in the default trigger list. Kept
    /// so a trigger can be added back on the page with its tested instruction.
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
        Turn the dictated text into a bulleted list: one item per line, each line starting with "- ". Split the items where the speaker lists them, even without commas or "and". Remove filler words and apply self-corrections. Write each item in sentence case: a capital first letter, the rest as said; never all capitals. No heading, nothing else. Reply with the list only, as plain text.
        """),
        DictationTrigger(word: "bullets", instruction: """
        Turn the dictated text into short bullet points, one point per line, each line starting with "- ". Remove filler words and apply self-corrections. Keep every fact, name, number and time as said. Write each point in sentence case, keeping the speaker's casing; never all capitals. No heading, nothing else. Reply with the bullets only, as plain text.
        """),
    ]

    static let builtIn = DictationGateSettings(
        fillers: ["um", "uh", "erm", "hmm"],
        positionFillers: [],
        corrections: ["no wait", "wait no", "scratch that", "make that", "I mean", "I meant", "actually", "sorry"],
        triggers: [],
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
        // Phrases and the capitalise list came in round 2: a record without them (saved by the
        // round 1 page) uses the built-in ones; a record with them must have them fit
        var phrases = builtInPhrases
        if let phrasesValue = value["phrases"] {
            guard let storedPhrases = phraseEntries(phrasesValue) else {
                return nil
            }
            phrases = storedPhrases
        }
        var capitalise = builtInCapitalise
        if let capitaliseValue = value["capitalise"] {
            guard let storedCapitalise = phraseList(capitaliseValue) else {
                return nil
            }
            capitalise = storedCapitalise
        }
        // `repeat` came in round 3, optional the same way: a whole number from 1 to 20
        var repeatCount = builtInRepeat
        if let repeatValue = value["repeat"] {
            guard let storedRepeat = repeatNumber(repeatValue) else {
                return nil
            }
            repeatCount = storedRepeat
        }
        return DictationGateSettings(fillers: fillers, positionFillers: positionFillers, corrections: corrections, triggers: triggers,
                                     lightInstruction: lightInstruction, phrases: phrases, capitalise: capitalise, repeatCount: repeatCount)
    }

    private static func repeatNumber(_ value: JSONValue) -> Int? {
        guard let number = value.numberValue, number == number.rounded(), number >= 1, number <= Double(maxRepeat) else {
            return nil
        }
        return Int(number)
    }

    /// One test phrase: text 1 to 1,000 characters, expect a path, note up to 200 characters (an
    /// empty note is no note).
    private static func phraseEntry(_ value: JSONValue) -> DictationTestPhrase? {
        guard value.objectValue != nil,
              let text = value["text"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty, text.count <= maxPhraseTextCharacters,
              let expectText = value["expect"]?.stringValue,
              let expect = DictationPath(rawValue: expectText) else {
            return nil
        }
        guard let noteValue = value["note"], noteValue != .null else {
            return DictationTestPhrase(text: text, expect: expect)
        }
        guard let note = noteValue.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), note.count <= maxNoteCharacters else {
            return nil
        }
        return DictationTestPhrase(text: text, expect: expect, note: note.isEmpty ? nil : note)
    }

    /// 1 to 60 phrases, each fitting.
    private static func phraseEntries(_ value: JSONValue) -> [DictationTestPhrase]? {
        guard let items = value.arrayValue, !items.isEmpty, items.count <= maxPhrases else {
            return nil
        }
        var entries: [DictationTestPhrase] = []
        for item in items {
            guard let entry = phraseEntry(item) else {
                return nil
            }
            entries.append(entry)
        }
        return entries
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
        var phraseValues: [JSONValue] = []
        for phrase in phrases {
            var fields: [String: JSONValue] = ["text": .string(phrase.text), "expect": .string(phrase.expect.rawValue)]
            if let note = phrase.note {
                fields["note"] = .string(note)
            }
            phraseValues.append(.object(fields))
        }
        return .object([
            "fillers": .array(fillers.map(JSONValue.string)),
            "positionFillers": .array(positionFillers.map(JSONValue.string)),
            "corrections": .array(corrections.map(JSONValue.string)),
            "triggers": .array(triggerValues),
            "lightInstruction": .string(lightInstruction),
            "phrases": .array(phraseValues),
            "capitalise": .array(capitalise.map(JSONValue.string)),
            "repeat": .number(Double(repeatCount)),
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
    /// What goes on: the text after the filler rule for light, the text after the trigger for
    /// rewrite, the text to insert as is for skip and rule.
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
        /// Just after the word's last character in the original text.
        let end: String.Index
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
            found.append(Word(text: wordText, start: start, end: index, before: gap, after: ""))
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

    /// One phrase found in the text: which list entry, where, and whether it is a correction cue.
    private struct Hit {
        let phrase: String
        let range: Range<Int>
        var isCorrection = false
    }

    /// The fillers and correction cues in the text, as the settings spell them, in the order they
    /// first occur (each once).
    static func matches(in textWords: [Word], settings: DictationGateSettings) -> [String] {
        let found = hits(in: textWords, settings: settings)
        var seen = Set<String>()
        var ordered: [String] = []
        for hit in found where !seen.contains(hit.phrase.lowercased()) {
            seen.insert(hit.phrase.lowercased())
            ordered.append(hit.phrase)
        }
        return ordered
    }

    /// Every filler, counted position filler and correction cue in the text, earliest first.
    private static func hits(in textWords: [Word], settings: DictationGateSettings) -> [Hit] {
        var hits: [Hit] = []
        var counted = Set<Int>()
        for phrase in settings.fillers {
            for range in occurrences(of: phrase, in: textWords) {
                hits.append(Hit(phrase: phrase, range: range))
                counted.formUnion(range)
            }
        }
        for phrase in settings.corrections {
            for range in occurrences(of: phrase, in: textWords) {
                hits.append(Hit(phrase: phrase, range: range, isCorrection: true))
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
        return hits
    }

    // MARK: The filler rule (round 3)

    /// The word positions the filler rule removes: every filler hit that does not overlap a
    /// correction cue (a phrase in both lists counts as a correction).
    private static func fillerPositions(_ found: [Hit]) -> Set<Int> {
        var cuePositions = Set<Int>()
        for hit in found where hit.isCorrection {
            cuePositions.formUnion(hit.range)
        }
        var positions = Set<Int>()
        for hit in found where !hit.isCorrection && cuePositions.isDisjoint(with: hit.range) {
            positions.formUnion(hit.range)
        }
        return positions
    }

    /// The gap left where words were removed: its punctuation (commas dropped) and one space, or
    /// one space, or nothing when it was empty.
    private static func joinedGap(_ first: String, _ second: String) -> String {
        let combined = first + second
        let punctuation = String(combined.filter(isNotWhitespace))
        if punctuation.isEmpty {
            return combined.isEmpty ? "" : " "
        }
        return punctuation + " "
    }

    private static func isNotWhitespace(_ character: Character) -> Bool {
        !character.isWhitespace
    }

    private static func withoutCommas(_ gap: String) -> String {
        gap.replacingOccurrences(of: ",", with: "")
    }

    /// The text without the words at these positions, and without any comma next to them
    /// ("we need, uh, cups" → "we need cups"). Trimmed.
    static func removingWords(at positions: Set<Int>, from text: String, textWords: [Word]) -> String {
        guard !positions.isEmpty, !textWords.isEmpty else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // gaps[index] is the text before word `index`; the last one is after the last word
        var gaps: [String] = []
        for word in textWords {
            gaps.append(word.before)
        }
        gaps.append(textWords[textWords.count - 1].after)
        for position in positions.sorted() {
            gaps[position] = withoutCommas(gaps[position])
            gaps[position + 1] = withoutCommas(gaps[position + 1])
        }
        var result = ""
        var pendingGap = gaps[0]
        for (index, word) in textWords.enumerated() {
            if positions.contains(index) {
                pendingGap = joinedGap(pendingGap, gaps[index + 1])
                continue
            }
            result += pendingGap + String(text[word.start..<word.end])
            pendingGap = gaps[index + 1]
        }
        result += pendingGap
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: The simple correction rule (round 3)

    /// What a correction can replace by rule.
    enum TokenKind: Equatable, Sendable {
        case number
        case time
        case weekday
        case month
    }

    /// One or more words read as one value ("5:30", "5 pm", "friday"); `kind` nil for any other word.
    struct Token: Equatable {
        let kind: TokenKind?
        let firstWord: Int
        let lastWord: Int
        let start: String.Index
        let end: String.Index
    }

    private static let numberWords: Set<String> = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve"]
    private static let weekdays: Set<String> = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    private static let months: Set<String> = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october",
                                              "november", "december"]
    private static let dayHalves: Set<String> = ["am", "pm"]

    private static func isDigits(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy(\.isASCII) && text.allSatisfy(\.isNumber)
    }

    // "5pm", "11am", "5:30pm" is read as 5, ":" and "30pm" (see `tokens`)
    private static func isClockWithHalf(_ text: String) -> Bool {
        guard text.count > 2 else {
            return false
        }
        let half = String(text.suffix(2))
        let hours = String(text.dropLast(2))
        return dayHalves.contains(half) && isDigits(hours) && hours.count <= 2
    }

    private static func isOnlyWhitespace(_ gap: String) -> Bool {
        !gap.isEmpty && gap.allSatisfy(\.isWhitespace)
    }

    /// The words of a text as tokens: times joined across ":" and before "am"/"pm".
    static func tokens(in textWords: [Word]) -> [Token] {
        var found: [Token] = []
        var index = 0
        while index < textWords.count {
            let word = textWords[index]
            var lastWord = index
            var kind: TokenKind?
            // "5:30" and "5:30pm" (the colon splits the words): hours, ":", minutes
            let hasMinutes = index + 1 < textWords.count && word.after == ":" && isDigits(word.text) && word.text.count <= 2
                && (isDigits(textWords[index + 1].text) || isClockWithHalf(textWords[index + 1].text)) && textWords[index + 1].text.count >= 2
            if hasMinutes {
                kind = .time
                lastWord = index + 1
            } else if isClockWithHalf(word.text) {
                kind = .time
            } else if isDigits(word.text) {
                kind = .number
            } else if numberWords.contains(word.text) {
                kind = .number
            } else if weekdays.contains(word.text) {
                kind = .weekday
            } else if months.contains(word.text) {
                kind = .month
            }
            // "5 pm", "5:30 pm": a number or a time followed by am/pm
            let halfIndex = lastWord + 1
            let isFollowedByHalf = halfIndex < textWords.count && dayHalves.contains(textWords[halfIndex].text)
                && isOnlyWhitespace(textWords[lastWord].after)
            if (kind == .number && isDigits(word.text)) || (kind == .time && lastWord > index), isFollowedByHalf {
                kind = .time
                lastWord = halfIndex
            }
            found.append(Token(kind: kind, firstWord: index, lastWord: lastWord, start: word.start, end: textWords[lastWord].end))
            index = lastWord + 1
        }
        return found
    }

    /// The text with the simple correction applied, or nil when the rule does not fit (then the
    /// model gets it). See the rule at the top of this file.
    static func simpleCorrection(in text: String, settings: DictationGateSettings) -> String? {
        let textWords = words(in: text)
        var cueRanges: [Range<Int>] = []
        for phrase in settings.corrections {
            cueRanges.append(contentsOf: occurrences(of: phrase, in: textWords))
        }
        // Exactly one cue; overlapping matches ("no wait" and "wait no" in "no wait no") count as more
        guard cueRanges.count == 1, let cue = cueRanges.first, cue.lowerBound > 0 else {
            return nil
        }
        let textTokens = tokens(in: textWords)
        var after: [Token] = []
        var before: [Token] = []
        for token in textTokens {
            if token.firstWord >= cue.upperBound {
                after.append(token)
            } else if token.lastWord < cue.lowerBound {
                before.append(token)
            }
        }
        // Exactly one value after the cue and nothing else; only spaces or a comma between them
        guard after.count == 1, let replacement = after.first, let kind = replacement.kind else {
            return nil
        }
        let gapAfterCue = textWords[cue.upperBound - 1].after
        guard gapAfterCue.allSatisfy(isSpaceOrComma) else {
            return nil
        }
        // The last value of the same kind before the cue is the one replaced
        var sameKind: Token?
        for token in before where token.kind == kind {
            sameKind = token
        }
        guard let replaced = sameKind else {
            return nil
        }
        let cueStart = textWords[cue.lowerBound].start
        let head = String(text[text.startIndex..<replaced.start])
        let newValue = String(text[replacement.start..<replacement.end])
        let between = String(text[replaced.end..<cueStart])
        let corrected = head + newValue + between
        return corrected.trimmingCharacters(in: trailingSpaceAndCommas)
    }

    private static let trailingSpaceAndCommas = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))

    private static func isSpaceOrComma(_ character: Character) -> Bool {
        character.isWhitespace || character == ","
    }

    // MARK: Finishing (round 3: every path's output)

    private static let lowercaseI: Set<String> = ["i", "i'm", "i'll", "i've", "i'd"]

    /// "i" written as "I" (also i'm, i'll, i've, i'd).
    static func capitalI(_ text: String) -> String {
        var result = text
        // From the end backwards, so the earlier indices stay valid
        for word in words(in: text).reversed() where lowercaseI.contains(word.text) && text[word.start] == "i" {
            result.replaceSubrange(word.start...word.start, with: "I")
        }
        return result
    }

    /// The text as inserted: the capitalise list's spelling, "I", a capital first letter and end
    /// punctuation.
    static func finished(_ text: String, settings: DictationGateSettings) -> String {
        let withI = capitalI(text)
        let spelled = capitalised(withI, capitalise: settings.capitalise)
        return tidy(spelled)
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

    /// The text with every whole-word match of a capitalise entry written as the entry spells it
    /// ("friday" → "Friday", "new york" → "New York" when listed so). Case-insensitive; a longer
    /// entry wins where two overlap; everything else is left as it was.
    static func capitalised(_ text: String, capitalise: [String]) -> String {
        let textWords = words(in: text)
        // Longest entries first, so "New York City" is placed before "New York" could claim it
        let entries = capitalise.sorted(by: hasMoreWords)
        var taken = Set<Int>()
        var replacements: [(range: Range<String.Index>, spelling: String)] = []
        for entry in entries {
            for wordRange in occurrences(of: entry, in: textWords) where taken.isDisjoint(with: wordRange) {
                taken.formUnion(wordRange)
                let characters = textWords[wordRange.lowerBound].start..<textWords[wordRange.upperBound - 1].end
                replacements.append((characters, entry))
            }
        }
        // From the end backwards, so the earlier ranges stay valid
        replacements.sort(by: startsLater)
        var result = text
        for replacement in replacements {
            result.replaceSubrange(replacement.range, with: replacement.spelling)
        }
        return result
    }

    private static func hasMoreWords(_ first: String, _ second: String) -> Bool {
        words(in: first).count > words(in: second).count
    }

    private static func startsLater(_ first: (range: Range<String.Index>, spelling: String),
                                    _ second: (range: Range<String.Index>, spelling: String)) -> Bool {
        first.range.lowerBound > second.range.lowerBound
    }

    /// The decision the screen acts on: the rules, and on the skip and rule paths the text
    /// finished (`finished`: capitalise list, "I", first letter, end punctuation) and inserted as
    /// is. On light and rewrite the model's answer is finished after the model (`finished`).
    static func decideForInsert(_ rawText: String, settings: DictationGateSettings) -> DictationGateDecision {
        let found = evaluate(rawText, settings: settings)
        guard found.instruction == nil else {
            return DictationGateDecision(path: found.path, trigger: found.trigger, matched: found.matched, text: found.text,
                                         instruction: found.instruction)
        }
        return DictationGateDecision(path: found.path, trigger: nil, matched: found.matched, text: finished(found.text, settings: settings),
                                     instruction: nil)
    }

    /// The path for one dictation (the rules only, the no-model text tidied but not finished; the
    /// screen uses `decideForInsert`).
    static func decide(_ rawText: String, settings: DictationGateSettings) -> DictationGateDecision {
        let found = evaluate(rawText, settings: settings)
        guard found.instruction == nil else {
            return found
        }
        return DictationGateDecision(path: found.path, trigger: nil, matched: found.matched, text: tidy(found.text), instruction: nil)
    }

    /// The rules: the path, and the text as the rules leave it (not tidied).
    private static func evaluate(_ rawText: String, settings: DictationGateSettings) -> DictationGateDecision {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        let textWords = words(in: text)
        if let found = trigger(in: text, textWords: textWords, settings: settings) {
            let restWords = words(in: found.rest)
            let matched = matches(in: restWords, settings: settings)
            return DictationGateDecision(path: .rewrite, trigger: found.trigger.word, matched: matched, text: found.rest,
                                         instruction: found.trigger.instruction)
        }
        let found = hits(in: textWords, settings: settings)
        let matched = matches(in: textWords, settings: settings)
        let removed = fillerPositions(found)
        let withoutFillers = removingWords(at: removed, from: text, textWords: textWords)
        let hasCue = found.contains(where: \.isCorrection)
        guard hasCue else {
            let path: DictationPath = removed.isEmpty ? .skip : .rule
            return DictationGateDecision(path: path, trigger: nil, matched: matched, text: withoutFillers, instruction: nil)
        }
        if let corrected = simpleCorrection(in: withoutFillers, settings: settings) {
            return DictationGateDecision(path: .rule, trigger: nil, matched: matched, text: corrected, instruction: nil)
        }
        return DictationGateDecision(path: .light, trigger: nil, matched: matched, text: withoutFillers, instruction: settings.lightInstruction)
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
