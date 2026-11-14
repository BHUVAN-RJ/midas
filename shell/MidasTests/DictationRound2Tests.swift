#if MIDAS_TEST_BUILD
// Dictation gate round 2 (TEST BUILD, founder 2026-11-13; docs/briefs/dictation-gate-test.md,
// "Round 2 build"). Compiled only against a Test build: run with the "Midas Test" scheme's test
// action.
//
// The test phrases and the capitalise list live in settings:main (optional fields: a record
// without them uses the built-in ones; a record with them must have them fit); the built-in
// phrases (29 or more) each take the path they expect; the capitalise list fixes days and months
// on the skip path only; Run All's expected-against-actual tally; runs saved with `expect`
// through the Sidekick's real manifest; and the round 2 instruction fixes.
import XCTest
@testable import Midas

private let roundTwoRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func roundTwoJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// The round 1 record shape, with the two round 2 fields given as raw JSON text after it.
private func settingsJSON(extra: String) -> JSONValue {
    roundTwoJSON(#"{ "fillers": ["um"], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "x""# + extra + "}")
}

@MainActor
final class DictationRound2Tests: XCTestCase {
    private let builtIn = DictationGateSettings.builtIn
    private var storeURL: URL!
    private let device = DictationDeviceInfo(device: "iPhone17,1", ios: "26.1", build: "30")
    private let fixedNow = Date(timeIntervalSince1970: 1_763_070_000)
    private var modelSettings = DictationGateSettings.builtIn

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory.appending(path: "dictation-round2-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func clock() -> Date {
        fixedNow
    }

    // MARK: The built-in phrases

    func testThereAreAtLeast29PhrasesStartingWithRoundOnesNine() {
        let phrases = DictationGateSettings.builtInPhrases
        XCTAssertGreaterThanOrEqual(phrases.count, 29)
        XCTAssertLessThanOrEqual(phrases.count, DictationGateSettings.maxPhrases)
        var firstNine: [String] = []
        for phrase in phrases.prefix(9) {
            firstNine.append(phrase.text)
            XCTAssertEqual(phrase.expect, DictationTestPhrases.expectedPaths[phrase.text], phrase.text)
        }
        XCTAssertEqual(firstNine, DictationTestPhrases.every)
        var seen = Set<String>()
        for phrase in phrases {
            XCTAssertFalse(seen.contains(phrase.text), "listed twice: \(phrase.text)")
            seen.insert(phrase.text)
        }
    }

    func testEveryBuiltInPhraseTakesThePathItExpects() {
        for phrase in DictationGateSettings.builtInPhrases {
            XCTAssertEqual(DictationGate.decide(phrase.text, settings: builtIn).path, phrase.expect, phrase.text)
        }
    }

    func testEachTriggerWordIsSaidAtLeastTwice() {
        var counts: [String: Int] = [:]
        for phrase in DictationGateSettings.builtInPhrases {
            if let trigger = DictationGate.decide(phrase.text, settings: builtIn).trigger {
                counts[trigger, default: 0] += 1
            }
        }
        for trigger in DictationGateSettings.builtInTriggers {
            XCTAssertGreaterThanOrEqual(counts[trigger.word] ?? 0, 2, trigger.word)
        }
    }

    func testTheNewPhrasesCoverBacktracksFillerWordsUsedAsWordsAndSkips() {
        var cuesHeard = Set<String>()
        var skips = 0
        var likeOrSoAsWords = 0
        for phrase in DictationGateSettings.builtInPhrases.dropFirst(9) {
            let decision = DictationGate.decide(phrase.text, settings: builtIn)
            cuesHeard.formUnion(decision.matched)
            guard decision.path == .skip else {
                continue
            }
            skips += 1
            let words = DictationGate.words(in: phrase.text).map(\.text)
            if words.contains("like") || words.contains("so") {
                likeOrSoAsWords += 1
            }
        }
        for cue in ["scratch that", "I mean", "make that", "no wait"] {
            XCTAssertTrue(cuesHeard.contains(cue), cue)
        }
        XCTAssertGreaterThanOrEqual(skips, 5)
        XCTAssertGreaterThanOrEqual(likeOrSoAsWords, 3)
    }

    // MARK: Capitalise on the skip path

    func testSkipSpellsDaysAndMonthsAsListed() {
        let deck = DictationGate.decideForInsert("send the deck to Priya by friday", settings: builtIn)
        XCTAssertEqual(deck.path, .skip)
        XCTAssertEqual(deck.text, "Send the deck to Priya by Friday.")
        XCTAssertNil(deck.instruction)
        let invoice = DictationGate.decideForInsert("the invoice for 450 dollars is due on march 3", settings: builtIn)
        XCTAssertEqual(invoice.text, "The invoice for 450 dollars is due on March 3.")
        XCTAssertEqual(DictationGate.decideForInsert("MONDAY works", settings: builtIn).text, "Monday works.")
    }

    func testMayIsLeftOutOfTheBuiltInList() {
        XCTAssertFalse(DictationGateSettings.builtInCapitalise.contains("May"))
        XCTAssertEqual(DictationGate.decideForInsert("I may see you in may", settings: builtIn).text, "I may see you in may.")
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday", "January", "December"] {
            XCTAssertTrue(DictationGateSettings.builtInCapitalise.contains(day), day)
        }
    }

    func testCapitaliseMatchesWholeWordsAndTheLongestEntryFirst() {
        XCTAssertEqual(DictationGate.capitalised("fridays and friday's", capitalise: ["Friday"]), "fridays and friday's")
        XCTAssertEqual(DictationGate.capitalised("meet in new york city on monday", capitalise: ["New York", "New York City", "Monday"]),
                       "meet in New York City on Monday")
        XCTAssertEqual(DictationGate.capitalised("see you, friday!", capitalise: ["Friday"]), "see you, Friday!")
        XCTAssertEqual(DictationGate.capitalised("friday or friday", capitalise: ["Friday"]), "Friday or Friday")
        XCTAssertEqual(DictationGate.capitalised("nothing here", capitalise: []), "nothing here")
    }

    func testOnlyTheSkipPathIsCapitalised() {
        let light = DictationGate.decideForInsert("um see you friday", settings: builtIn)
        XCTAssertEqual(light.path, .light)
        XCTAssertEqual(light.text, "um see you friday", "the model gets the raw text")
        let rewrite = DictationGate.decideForInsert("email tell sam friday works", settings: builtIn)
        XCTAssertEqual(rewrite.path, .rewrite)
        XCTAssertEqual(rewrite.text, "tell sam friday works")
    }

    func testTheCapitaliseListComesFromTheSettings() {
        let none = DictationGateSettings(fillers: [], positionFillers: [], corrections: [], triggers: [], lightInstruction: "x", capitalise: [])
        XCTAssertEqual(DictationGate.decideForInsert("send it friday", settings: none).text, "Send it friday.")
        let custom = DictationGateSettings(fillers: [], positionFillers: [], corrections: [], triggers: [], lightInstruction: "x", capitalise: ["Priya"])
        XCTAssertEqual(DictationGate.decideForInsert("call priya friday", settings: custom).text, "Call Priya friday.")
    }

    // MARK: Settings: phrases and capitalise

    func testARecordWithoutTheRoundTwoFieldsUsesTheBuiltInOnes() {
        let resolved = DictationGateSettings.resolved(settingsJSON(extra: ""))

        XCTAssertTrue(resolved.isSaved)
        XCTAssertEqual(resolved.settings.fillers, ["um"])
        XCTAssertEqual(resolved.settings.phrases, DictationGateSettings.builtInPhrases)
        XCTAssertEqual(resolved.settings.capitalise, DictationGateSettings.builtInCapitalise)
    }

    func testStoredPhrasesAndCapitaliseAreTrimmedAndUsed() {
        let value = settingsJSON(extra: #", "capitalise": [" Sunday "], "phrases": [{ "text": " hi there ", "expect": "skip", "note": "  " }, { "text": "um ok", "expect": "light", "note": " filler ", "extra": 1 }, { "text": "list a b c", "expect": "rewrite", "note": null }]"#)

        let resolved = DictationGateSettings.resolved(value)

        XCTAssertTrue(resolved.isSaved)
        XCTAssertEqual(resolved.settings.capitalise, ["Sunday"])
        XCTAssertEqual(resolved.settings.phrases, [
            DictationTestPhrase(text: "hi there", expect: .skip),
            DictationTestPhrase(text: "um ok", expect: .light, note: "filler"),
            DictationTestPhrase(text: "list a b c", expect: .rewrite),
        ])
    }

    func testPhrasesOrACapitaliseListThatDoNotFitFallBackToTheBuiltInSettings() {
        let longText = String(repeating: "a", count: 1001)
        let longNote = String(repeating: "a", count: 201)
        var manyPhrases: [String] = []
        for index in 0..<61 {
            manyPhrases.append(#"{ "text": "p\#(index)", "expect": "skip" }"#)
        }
        let badExtras: [String] = [
            #", "phrases": []"#,
            #", "phrases": "send it""#,
            #", "phrases": null"#,
            #", "phrases": ["send it"]"#,
            #", "phrases": [{ "text": "send it", "expect": "fast" }]"#,
            #", "phrases": [{ "text": "send it" }]"#,
            #", "phrases": [{ "text": "   ", "expect": "skip" }]"#,
            #", "phrases": [{ "text": "\#(longText)", "expect": "skip" }]"#,
            #", "phrases": [{ "text": "send it", "expect": "skip", "note": "\#(longNote)" }]"#,
            #", "phrases": [{ "text": "send it", "expect": "skip", "note": 3 }]"#,
            #", "phrases": [\#(manyPhrases.joined(separator: ","))]"#,
            #", "capitalise": [""]"#,
            #", "capitalise": "Friday""#,
            #", "capitalise": ["..."]"#,
        ]
        for extra in badExtras {
            let value = settingsJSON(extra: extra)
            XCTAssertNil(DictationGateSettings.from(value), String(extra.prefix(80)))
            let resolved = DictationGateSettings.resolved(value)
            XCTAssertFalse(resolved.isSaved, String(extra.prefix(80)))
            XCTAssertEqual(resolved.settings, builtIn)
        }
        let sixty = Array(manyPhrases.prefix(60)).joined(separator: ",")
        XCTAssertNotNil(DictationGateSettings.from(settingsJSON(extra: #", "phrases": [\#(sixty)], "capitalise": []"#)), "60 phrases and no capitalise fit")
    }

    func testCustomPhrasesRoundTripThroughTheRecord() {
        let custom = DictationGateSettings(fillers: ["er"], positionFillers: [], corrections: [], triggers: [], lightInstruction: "Clean it.",
                                           phrases: [DictationTestPhrase(text: "meet sam friday", expect: .skip, note: "day"),
                                                     DictationTestPhrase(text: "er hi", expect: .light)],
                                           capitalise: ["Friday", "Sam"])

        XCTAssertEqual(DictationGateSettings.from(custom.recordValue), custom)
        XCTAssertNil(custom.recordValue["phrases"]?.arrayValue?[1]["note"], "no note, no field")
    }

    // MARK: Through the Sidekick's manifest

    private func gatedStore() throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: storeURL)
        let manifestURL = roundTwoRepoRoot.appending(path: "sidekicks/dictation/manifest.json")
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        let types = try XCTUnwrap(manifest["types"])
        func typesFor(_ sidekickId: String) -> JSONValue? {
            sidekickId == DictationRunRecord.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: try RecordSchemaEngine(), typesProvider: typesFor)
        return store
    }

    func testTheBuiltInSettingsWithPhrasesFitTheManifestAndTheCenterReadsThem() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        let custom = DictationGateSettings(fillers: [], positionFillers: [], corrections: [], triggers: [], lightInstruction: "x",
                                           phrases: [DictationTestPhrase(text: "send it friday", expect: .skip)], capitalise: ["Friday"])

        try store.set(sidekickId: "dictation", key: "settings:main", value: builtIn.recordValue)
        XCTAssertEqual(center.currentSettings(), builtIn)
        try store.set(sidekickId: "dictation", key: "settings:main", value: custom.recordValue)

        XCTAssertEqual(center.currentSettings().phrases, custom.phrases)
        XCTAssertEqual(center.currentSettings().capitalise, ["Friday"])
        XCTAssertTrue(center.settingsAreSaved)
    }

    func testTheManifestRefusesPhrasesThatDoNotFit() throws {
        let store = try gatedStore()
        let badExtras = [
            #", "phrases": []"#,
            #", "phrases": [{ "text": "send it", "expect": "fast" }]"#,
            #", "phrases": [{ "expect": "skip" }]"#,
            #", "capitalise": [""]"#,
        ]
        for extra in badExtras {
            XCTAssertThrowsError(try store.set(sidekickId: "dictation", key: "settings:main", value: settingsJSON(extra: extra)), extra)
        }
        XCTAssertNoThrow(try store.set(sidekickId: "dictation", key: "settings:main", value: settingsJSON(extra: "")), "round 1 shape still fits")
    }

    func testARunAllRunIsSavedWithTheExpectedPath() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let decision = DictationGate.decideForInsert("send it friday", settings: builtIn)
        let gate = DictationGateOutcome(decision: decision, gateMs: 0.02)
        let result = DictationCleanupResult(cleanedText: decision.text, durationMs: 0, isFirstCall: false)

        center.save(DictationTestRuns.phrase("send it friday", result: result, source: .runAll, status: .available, at: fixedNow, gate: gate,
                                             expect: .light))

        XCTAssertNil(center.lastSaveError)
        let value = try XCTUnwrap(store.query(sidekickId: "dictation", keyPrefix: "run:").first?.value)
        XCTAssertEqual(value["expect"]?.stringValue, "light")
        XCTAssertEqual(value["path"]?.stringValue, "skip")
        XCTAssertEqual(value["cleaned"]?.stringValue, "Send it Friday.")
    }

    func testASpokenRunHasNoExpectedPath() {
        let result = DictationCleanupResult(cleanedText: "x", durationMs: 5, isFirstCall: false)
        let timings = DictationTimings(releasedAt: fixedNow, rawFinalAt: fixedNow, cleanupStartedAt: fixedNow, cleanedAt: fixedNow)
        let spoken = DictationTestRuns.spoken(raw: "x", result: result, timings: timings, status: .available, at: fixedNow)

        XCTAssertNil(DictationRunRecord.value(spoken, device: device)["expect"])
        let tapped = DictationTestRuns.phrase("x", result: result, source: .phrase, status: .available, at: fixedNow, expect: .skip)
        XCTAssertEqual(DictationRunRecord.value(tapped, device: device)["expect"]?.stringValue, "skip")
    }

    // MARK: Run All's tally

    func testThePathCheckCountsWrongPaths() {
        var check = DictationPathCheck()
        XCTAssertEqual(check.label, "Wrong Path 0 of 0")
        check.add(phrase: "a", expected: .skip, actual: .skip)
        check.add(phrase: "b", expected: .light, actual: .skip)
        check.add(phrase: "b", expected: .light, actual: .skip)
        check.add(phrase: "c", expected: .rewrite, actual: .rewrite)

        XCTAssertEqual(check.checked, 4)
        XCTAssertEqual(check.wrong, 2)
        XCTAssertEqual(check.wrongPhrases, ["b": .light])
        XCTAssertEqual(check.label, "Wrong Path 2 of 4")
    }

    // MARK: The screen reads the phrases from the settings

    private func currentModelSettings() -> DictationGateSettings {
        modelSettings
    }

    func testTheScreenShowsTheSettingsPhrases() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("the screen needs iOS 26")
        }
        let model = DictationTestModel(settings: currentModelSettings)
        XCTAssertEqual(model.phrases, DictationGateSettings.builtInPhrases, "built-in before the screen opens")
        modelSettings = DictationGateSettings(fillers: [], positionFillers: [], corrections: [], triggers: [], lightInstruction: "x",
                                              phrases: [DictationTestPhrase(text: "send it", expect: .skip)])

        model.appeared()

        XCTAssertEqual(model.phrases, [DictationTestPhrase(text: "send it", expect: .skip)])
    }

    // MARK: Instruction fixes (round 1 results)

    func testTheLightInstructionReplacesBacktracksAndListsOnlyThreeOrMore() {
        let instruction = DictationGateSettings.builtInLightInstruction

        XCTAssertTrue(instruction.contains("the words just before the cue are replaced by the words after it"))
        XCTAssertTrue(instruction.contains("Never keep both"))
        XCTAssertTrue(instruction.contains("\"the browser is firefox scratch that chrome\" becomes \"The browser is Chrome.\""))
        XCTAssertTrue(instruction.contains("only when the text is clearly a list of three or more separate items"))
        XCTAssertTrue(instruction.contains("Never number one or two items"))
        XCTAssertTrue(instruction.contains("stays a sentence"))
        XCTAssertFalse(instruction.contains("When the speaker lists several items in a row"), "the old list rule is gone")
    }

    func testListAndBulletsKeepSentenceCaseNeverAllCapitals() throws {
        var byWord: [String: String] = [:]
        for trigger in DictationGateSettings.builtInTriggers {
            byWord[trigger.word] = trigger.instruction
        }
        let list = try XCTUnwrap(byWord["list"])
        let bullets = try XCTUnwrap(byWord["bullets"])

        XCTAssertTrue(list.contains("sentence case"))
        XCTAssertTrue(list.contains("never all capitals"))
        XCTAssertFalse(list.contains("Capitalise each item"))
        XCTAssertTrue(bullets.contains("sentence case"))
        XCTAssertTrue(bullets.contains("never all capitals"))
    }
}
#endif
