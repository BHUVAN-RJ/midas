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
//            by rule, and the capitalise list's words (days, months) spelled as listed. No model
//            call.
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

    static let settingsKey = "settings:main"
    static let maxListItems = 50
    static let maxPhraseCharacters = 40
    static let maxTriggers = 20
    static let maxTriggerCharacters = 30
    static let maxInstructionCharacters = 4000
    static let maxPhrases = 60
    static let maxPhraseTextCharacters = 1000
    static let maxNoteCharacters = 200

    /// The tightened light instruction (fillers, self-corrections, punctuation, numbered lists).
    /// Round 2 (founder 2026-11-13): a correction replaces the words before it, never keeps both;
    /// numbered lists only for three or more clearly listed items.
    static let builtInLightInstruction = """
    You clean up dictated text. Rules:
    1. Remove filler words: um, uh, erm, hmm, like, so, you know, I mean, sort of, kind of, basically, when they are fillers.
    2. Apply self-corrections: when the speaker corrects themselves (no wait, scratch that, I mean, actually, make that), the words just before the cue are replaced by the words after it. Never keep both, and never turn a correction into a list. "be there at 5 no wait 6" becomes "Be there at 6." "the browser is firefox scratch that chrome" becomes "The browser is Chrome."
    3. Add punctuation and capital letters, including names, days, months and the start of each sentence.
    4. Write a numbered list, one item per line, only when the text is clearly a list of three or more separate items. Never number one or two items. A chat message or an ordinary sentence stays a sentence.
    5. Keep the person's own words otherwise. Never change pronouns, names, numbers or meaning, except what a correction explicitly replaces: "I" stays "I", "you" stays "you". Do not rephrase, summarise or translate.
    6. Add nothing: never add words, greetings, explanations, quotes or notes.
    Reply with the cleaned text only, as plain text.
    """

    /// Days and months. "May" is left out: in dictation it is nearly always the verb.
    static let builtInCapitalise = [
        "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday",
        "January", "February", "March", "April", "June", "July", "August", "September", "October", "November", "December",
    ]

    /// The nine phrases of round 1, then round 2's (founder 2026-11-13): more skips with names,
    /// days and numbers, more backtracks, "like"/"so" as real words, lists said in a sentence, and
    /// each trigger word at least twice. Each `expect` is what the built-in gate decides.
    static let builtInPhrases: [DictationTestPhrase] = [
        DictationTestPhrase(text: "um so like be there at 5 no wait 6", expect: .light),
        DictationTestPhrase(text: "uh tell mom im on my way", expect: .light),
        DictationTestPhrase(text: "buy eggs milk and uh bread oh and coffee", expect: .light),
        DictationTestPhrase(text: "send the deck to Priya and Tomasz by friday", expect: .skip),
        DictationTestPhrase(text: DictationTestPhrases.rambling, expect: .light, note: "60 words"),
        DictationTestPhrase(text: "send the deck to Priya by friday", expect: .skip),
        DictationTestPhrase(text: "email tell sam the launch moved to monday and thank him for the help", expect: .rewrite),
        DictationTestPhrase(text: "the browser is firefox scratch that chrome", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "list eggs milk bread coffee", expect: .rewrite),
        DictationTestPhrase(text: "lunch with Maya on tuesday at 12:30", expect: .skip),
        DictationTestPhrase(text: "the invoice for 450 dollars is due on march 3", expect: .skip),
        DictationTestPhrase(text: "call David back before 5 tomorrow", expect: .skip),
        DictationTestPhrase(text: "Ana and Jonas land at 9 on saturday", expect: .skip),
        DictationTestPhrase(text: "move the review to wednesday the 14th", expect: .skip),
        DictationTestPhrase(text: "meet at the cafe on 5th street scratch that the library", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "send it to Tom I mean Tim", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "order 3 pizzas make that 4", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "the call is at 2 no wait 3", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "book the table for friday no wait saturday", expect: .light, note: "backtrack"),
        DictationTestPhrase(text: "I like the new logo a lot", expect: .skip, note: "like as a word"),
        DictationTestPhrase(text: "it was so good to see you yesterday", expect: .skip, note: "so as a word"),
        DictationTestPhrase(text: "she looks like her mom", expect: .skip, note: "like as a word"),
        DictationTestPhrase(text: "the train was so late we missed the start", expect: .skip, note: "so as a word"),
        DictationTestPhrase(text: "um pack the charger the passport and the tickets", expect: .light, note: "list in a sentence"),
        DictationTestPhrase(text: "for the party we need uh cups plates napkins and ice", expect: .light, note: "list in a sentence"),
        DictationTestPhrase(text: "email tell priya the report is ready and the numbers are final", expect: .rewrite),
        DictationTestPhrase(text: "formal can you send me the contract by friday", expect: .rewrite),
        DictationTestPhrase(text: "formal: thanks for the meeting today we will reply next week", expect: .rewrite),
        DictationTestPhrase(text: "casual hey are we still on for dinner tonight", expect: .rewrite),
        DictationTestPhrase(text: "casual, running 10 minutes late see you soon", expect: .rewrite),
        DictationTestPhrase(text: "list: passport, charger, tickets, snacks", expect: .rewrite),
        DictationTestPhrase(text: "bullets the launch moved to monday the budget is approved and Sam owns the deck", expect: .rewrite),
        DictationTestPhrase(text: "bullets um design review on thursday then ship on friday", expect: .rewrite),
    ]

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
        return DictationGateSettings(fillers: fillers, positionFillers: positionFillers, corrections: corrections, triggers: triggers,
                                     lightInstruction: lightInstruction, phrases: phrases, capitalise: capitalise)
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

    /// The decision the screen acts on: `decide`, then on the skip path the capitalise list applied
    /// to the tidied text (round 2, founder 2026-11-13: skip has no model to fix "friday").
    static func decideForInsert(_ rawText: String, settings: DictationGateSettings) -> DictationGateDecision {
        let decision = decide(rawText, settings: settings)
        guard decision.path == .skip else {
            return decision
        }
        let text = capitalised(decision.text, capitalise: settings.capitalise)
        return DictationGateDecision(path: .skip, trigger: nil, matched: [], text: text, instruction: nil)
    }

    /// The path for one dictation (the rules only; the screen uses `decideForInsert`).
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
