#if MIDAS_TEST_BUILD
// Dictation cleanup gate (TEST BUILD, founder 2026-11-13; docs/briefs/dictation-gate-test.md).
// Compiled only against a Test build: run with the "Midas Test" scheme's test action.
//
// The gate's three paths (skip, light, rewrite) for the test phrases and for the edge cases of its
// rules (whole words, the position rule for "like" and "so", trigger stripping, the skip tidy-up);
// settings:main read, checked and falling back to the built-in settings, which match the page's;
// runs saved with their path through the Sidekick's real manifest; and the per-path summary with
// the same numbers as the page (backend/test/dictation-gate.test.ts uses the same fixture).
import JavaScriptCore
import XCTest
@testable import Midas

private let gateRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func gateJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@MainActor
final class DictationGateTests: XCTestCase {
    private let builtIn = DictationGateSettings.builtIn
    private var storeURL: URL!
    private let device = DictationDeviceInfo(device: "iPhone17,1", ios: "26.1", build: "29")
    private let fixedNow = Date(timeIntervalSince1970: 1_763_070_000)

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory.appending(path: "dictation-gate-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func decide(_ text: String) -> DictationGateDecision {
        DictationGate.decide(text, settings: builtIn)
    }

    // MARK: The test phrases

    func testEveryTestPhraseTakesItsExpectedPath() {
        XCTAssertEqual(DictationTestPhrases.every.count, 9)
        XCTAssertEqual(Array(DictationTestPhrases.every.prefix(5)), DictationTestPhrases.all, "the first five stay first")
        XCTAssertEqual(DictationTestPhrases.expectedPaths.count, 9)
        for phrase in DictationTestPhrases.every {
            XCTAssertEqual(decide(phrase).path, DictationTestPhrases.expectedPaths[phrase], phrase)
        }
    }

    func testTheBriefsFourNewPhrases() {
        XCTAssertEqual(DictationTestPhrases.gatePhrases, [
            "send the deck to Priya by friday",
            "email tell sam the launch moved to monday and thank him for the help",
            "the browser is firefox scratch that chrome",
            "list eggs milk bread coffee",
        ])
        XCTAssertEqual(decide(DictationTestPhrases.shortNames).path, .skip)
        let email = decide(DictationTestPhrases.emailTrigger)
        XCTAssertEqual(email.path, .rewrite)
        XCTAssertEqual(email.trigger, "email")
        XCTAssertEqual(decide(DictationTestPhrases.scratchThat).matched, ["scratch that"])
        let list = decide(DictationTestPhrases.listTrigger)
        XCTAssertEqual(list.path, .rewrite)
        XCTAssertEqual(list.trigger, "list")
        XCTAssertEqual(list.text, "eggs milk bread coffee")
    }

    // MARK: Paths

    func testSkipInsertsTheRawTextTidiedWithNoInstruction() {
        let decision = decide("send the deck to Priya by friday")

        XCTAssertEqual(decision.path, .skip)
        XCTAssertEqual(decision.text, "Send the deck to Priya by friday.")
        XCTAssertNil(decision.instruction)
        XCTAssertNil(decision.trigger)
        XCTAssertEqual(decision.matched, [])
    }

    func testLightCarriesTheRawTextTheMatchesAndTheLightInstruction() {
        let decision = decide("um so like be there at 5 no wait 6")

        XCTAssertEqual(decision.path, .light)
        XCTAssertEqual(decision.matched, ["um", "so", "like", "no wait"])
        XCTAssertEqual(decision.text, "um so like be there at 5 no wait 6")
        XCTAssertEqual(decision.instruction, DictationGateSettings.builtInLightInstruction)
    }

    func testRewriteStripsTheTriggerAndUsesItsInstruction() {
        let decision = decide("email tell sam the launch moved to monday and thank him for the help")

        XCTAssertEqual(decision.text, "tell sam the launch moved to monday and thank him for the help")
        XCTAssertEqual(decision.instruction, DictationGateSettings.builtInTriggers[0].instruction)
        XCTAssertTrue(decision.instruction?.contains("short email") == true)
    }

    func testTheLightInstructionIsTightened() {
        let instruction = DictationGateSettings.builtInLightInstruction

        XCTAssertTrue(instruction.contains("Never change pronouns, names, numbers or meaning, except what a correction explicitly replaces"))
        XCTAssertTrue(instruction.contains("never add words"))
        XCTAssertTrue(instruction.contains("numbered list"))
        XCTAssertEqual(DictationCleanup.instructions, instruction, "the screen's default instruction is the light one")
    }

    // MARK: Triggers

    func testTriggerMatchesInAnyCaseWithASpaceColonOrComma() {
        let cases: [(String, String, String)] = [
            ("Email: tell Sam hi", "email", "tell Sam hi"),
            ("EMAIL, tell Sam hi", "email", "tell Sam hi"),
            ("List  eggs, milk", "list", "eggs, milk"),
            ("list:eggs", "list", "eggs"),
            ("  formal thanks for coming", "formal", "thanks for coming"),
            ("Bullets: um the plan", "bullets", "um the plan"),
        ]
        for (text, trigger, rest) in cases {
            let decision = decide(text)
            XCTAssertEqual(decision.path, .rewrite, text)
            XCTAssertEqual(decision.trigger, trigger, text)
            XCTAssertEqual(decision.text, rest, text)
        }
        XCTAssertEqual(decide("Bullets: um the plan").matched, ["um"], "matches are counted after the trigger too")
    }

    func testTriggerNeedsAWholeWordAtTheStartAndTextAfterIt() {
        XCTAssertEqual(decide("emails to sam").path, .skip, "not the whole word")
        XCTAssertEqual(decide("listen to this").path, .skip)
        XCTAssertEqual(decide("send an email to sam").path, .skip, "not at the start")
        XCTAssertEqual(decide("email").path, .skip, "nothing after it")
        XCTAssertEqual(decide("email").text, "Email.")
        XCTAssertEqual(decide("Email. Tell Sam hi").path, .skip, "a full stop is not a colon or comma")
        XCTAssertEqual(decide("\"email\" tell sam").path, .skip, "something before the trigger")
    }

    func testAMultiWordTriggerFromSettings() {
        let settings = DictationGateSettings(fillers: [], positionFillers: [], corrections: [],
                                             triggers: [DictationTrigger(word: "make it formal", instruction: "Formal.")], lightInstruction: "Light.")

        let decision = DictationGate.decide("Make it formal: tell sam hi", settings: settings)
        XCTAssertEqual(decision.path, .rewrite)
        XCTAssertEqual(decision.trigger, "make it formal")
        XCTAssertEqual(decision.text, "tell sam hi")
        XCTAssertEqual(decision.instruction, "Formal.")
        XCTAssertEqual(DictationGate.decide("make it, formal tell sam", settings: settings).path, .skip)
        XCTAssertEqual(DictationGate.decide("make it casual tell sam", settings: settings).path, .skip)
    }

    // MARK: Whole words

    func testMatchingIsWholeWordAndCaseInsensitive() {
        XCTAssertEqual(decide("the umbrella is in the summary").path, .skip, "um inside a word")
        XCTAssertEqual(decide("sort the files of the hmmm folder").path, .skip, "sort of needs both words in a row; hmmm is not hmm")
        XCTAssertEqual(decide("Um, call me").matched, ["um"])
        XCTAssertEqual(decide("UH call me").matched, ["uh"])
        XCTAssertEqual(decide("I'm sorry I'm late").matched, ["sorry"])
        XCTAssertEqual(decide("it's sort of fine").matched, ["sort of"])
        XCTAssertEqual(decide("call me actually text me").matched, ["actually"])
    }

    func testEachPhraseIsListedOnceInTheOrderHeard() {
        XCTAssertEqual(decide("uh call uh me no wait text me").matched, ["uh", "no wait"])
        XCTAssertEqual(decide("I mean we could go").matched, ["I mean"], "in the fillers and the corrections, listed once")
    }

    // MARK: The position rule for like and so

    func testLikeAndSoAreWordsInTheMiddleOfASentence() {
        XCTAssertEqual(decide("I like it").path, .skip)
        XCTAssertEqual(decide("it is so good").path, .skip)
        XCTAssertEqual(decide("call me like when you land").path, .skip)
    }

    func testLikeAndSoAreFillersAtASentenceStart() {
        XCTAssertEqual(decide("So we leave at 6").matched, ["so"])
        XCTAssertEqual(decide("like I said we go").matched, ["like"])
        XCTAssertEqual(decide("We leave at 6. So bring snacks").matched, ["so"])
        XCTAssertEqual(decide("Done? Like now").matched, ["like"])
    }

    func testLikeAndSoAreFillersByACommaOrNextToAnotherFiller() {
        XCTAssertEqual(decide("it was, like, huge").matched, ["like"])
        XCTAssertEqual(decide("it was like, huge").matched, ["like"])
        XCTAssertEqual(decide("we um so go").matched, ["um", "so"])
        XCTAssertEqual(decide("we go um so like now").matched, ["um", "so", "like"], "a chain from one filler")
    }

    // MARK: The skip tidy-up

    func testTidyAddsACapitalAndAFullStopOnly() {
        XCTAssertEqual(DictationGate.tidy("send it"), "Send it.")
        XCTAssertEqual(DictationGate.tidy("Send it!"), "Send it!")
        XCTAssertEqual(DictationGate.tidy("are you there?"), "Are you there?")
        XCTAssertEqual(DictationGate.tidy("send it,"), "Send it.")
        XCTAssertEqual(DictationGate.tidy("  ok  "), "Ok.")
        XCTAssertEqual(DictationGate.tidy("5 pm works"), "5 pm works.")
        XCTAssertEqual(DictationGate.tidy("iPhone is here."), "IPhone is here.")
        XCTAssertEqual(DictationGate.tidy(""), "")
        XCTAssertEqual(decide("   ").path, .skip)
        XCTAssertEqual(decide("   ").text, "")
    }

    // MARK: Gate timing

    func testGateTimeIsInMillisecondsToTwoPlaces() {
        XCTAssertEqual(DictationGateTiming.milliseconds(.microseconds(42)), 0.04)
        XCTAssertEqual(DictationGateTiming.milliseconds(.microseconds(1_234)), 1.23)
        XCTAssertEqual(DictationGateTiming.milliseconds(.seconds(2)), 2_000)
        XCTAssertEqual(DictationGateTiming.milliseconds(.microseconds(-5)), 0)
    }

    // MARK: Settings

    func testBuiltInSettingsRoundTripThroughTheRecord() {
        XCTAssertEqual(DictationGateSettings.from(builtIn.recordValue), builtIn)
    }

    func testTheBuiltInSettingsMatchThePages() throws {
        let toolsSource = try String(contentsOf: gateRepoRoot.appending(path: "sidekicks/dictation/tools.js"), encoding: .utf8)
        let beginRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: begin */"))
        let endRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: end */", range: beginRange.upperBound..<toolsSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(toolsSource[beginRange.upperBound..<endRange.lowerBound]))
        XCTAssertNil(context.exception)
        let text = try XCTUnwrap(context.evaluateScript("JSON.stringify(DictationLogic.defaultSettings())")?.toString())

        let pageDefaults = gateJSON(text)

        XCTAssertEqual(pageDefaults, builtIn.recordValue, "the page's built-in settings, character for character")
    }

    func testStoredSettingsAreTrimmedAndUsed() {
        let value = gateJSON(#"""
        { "fillers": [" er "], "positionFillers": [], "corrections": ["oops"], "lightInstruction": " Clean it. ",
          "triggers": [{ "word": " memo ", "instruction": "Write a memo." }] }
        """#)

        let resolved = DictationGateSettings.resolved(value)

        XCTAssertTrue(resolved.isSaved)
        XCTAssertEqual(resolved.settings.fillers, ["er"])
        XCTAssertEqual(resolved.settings.positionFillers, [])
        XCTAssertEqual(resolved.settings.lightInstruction, "Clean it.")
        XCTAssertEqual(resolved.settings.triggers, [DictationTrigger(word: "memo", instruction: "Write a memo.")])
        let decision = DictationGate.decide("er memo time", settings: resolved.settings)
        XCTAssertEqual(decision.path, .light)
        XCTAssertEqual(decision.instruction, "Clean it.")
        XCTAssertEqual(DictationGate.decide("memo: lunch at noon", settings: resolved.settings).instruction, "Write a memo.")
        XCTAssertEqual(DictationGate.decide("um so email sam", settings: resolved.settings).path, .skip, "only the stored lists count")
    }

    func testEmptyListsAreAllowed() {
        let value = gateJSON(#"{ "fillers": [], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "x" }"#)

        XCTAssertNotNil(DictationGateSettings.from(value))
    }

    func testSettingsThatDoNotFitFallBackToTheBuiltInOnes() {
        let good = #"{ "fillers": ["um"], "positionFillers": ["so"], "corrections": ["no wait"], "triggers": [], "lightInstruction": "x" }"#
        XCTAssertNotNil(DictationGateSettings.from(gateJSON(good)), "the base case fits")
        let longPhrase = String(repeating: "a", count: 41)
        let longInstruction = String(repeating: "a", count: 4001)
        var manyWords: [String] = []
        for index in 0..<51 {
            manyWords.append("\"w\(index)\"")
        }
        let badValues: [String] = [
            #"[]"#,
            #"{ "positionFillers": ["so"], "corrections": [], "triggers": [], "lightInstruction": "x" }"#,
            #"{ "fillers": "um", "positionFillers": ["so"], "corrections": [], "triggers": [], "lightInstruction": "x" }"#,
            #"{ "fillers": [""], "positionFillers": ["so"], "corrections": [], "triggers": [], "lightInstruction": "x" }"#,
            #"{ "fillers": ["..."], "positionFillers": ["so"], "corrections": [], "triggers": [], "lightInstruction": "x" }"#,
            #"{ "fillers": [3], "positionFillers": ["so"], "corrections": [], "triggers": [], "lightInstruction": "x" }"#,
            #"{ "fillers": ["\#(longPhrase)"], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "x" }"#,
            #"{ "fillers": [\#(manyWords.joined(separator: ","))], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "x" }"#,
            #"{ "fillers": [], "positionFillers": [], "corrections": [], "triggers": [{ "word": "email" }], "lightInstruction": "x" }"#,
            #"{ "fillers": [], "positionFillers": [], "corrections": [], "triggers": [{ "word": "", "instruction": "x" }], "lightInstruction": "x" }"#,
            #"{ "fillers": [], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "  " }"#,
            #"{ "fillers": [], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "\#(longInstruction)" }"#,
        ]
        for badValue in badValues {
            XCTAssertNil(DictationGateSettings.from(gateJSON(badValue)), String(badValue.prefix(80)))
            let resolved = DictationGateSettings.resolved(gateJSON(badValue))
            XCTAssertFalse(resolved.isSaved)
            XCTAssertEqual(resolved.settings, builtIn)
        }
        XCTAssertEqual(DictationGateSettings.resolved(nil).settings, builtIn, "missing")
    }

    // MARK: Settings from the Sidekick

    private func manifestTypes() throws -> JSONValue {
        let manifestURL = gateRepoRoot.appending(path: "sidekicks/dictation/manifest.json")
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        return try XCTUnwrap(manifest["types"])
    }

    /// A store whose write gate checks the Dictation Sidekick's real manifest types.
    private func gatedStore() throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: storeURL)
        let types = try manifestTypes()
        func typesFor(_ sidekickId: String) -> JSONValue? {
            sidekickId == DictationRunRecord.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: try RecordSchemaEngine(), typesProvider: typesFor)
        return store
    }

    private func clock() -> Date {
        fixedNow
    }

    func testTheCenterReadsTheSidekicksSettingsBeforeEachRun() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        XCTAssertEqual(center.currentSettings(), builtIn, "none saved")
        XCTAssertFalse(center.settingsAreSaved)

        let custom = DictationGateSettings(fillers: ["er"], positionFillers: [], corrections: [], triggers: [], lightInstruction: "Clean it.")
        try store.set(sidekickId: "dictation", key: "settings:main", value: custom.recordValue)

        XCTAssertEqual(store.get(sidekickId: "dictation", key: "settings:main")?["$type"]?.stringValue, "dictation.settings", "the manifest's type")
        XCTAssertEqual(center.currentSettings(), custom)
        XCTAssertTrue(center.settingsAreSaved)
    }

    func testTheManifestRefusesSettingsThatDoNotFit() throws {
        let store = try gatedStore()
        let bad = gateJSON(#"{ "fillers": [""], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "x" }"#)

        XCTAssertThrowsError(try store.set(sidekickId: "dictation", key: "settings:main", value: bad))
    }

    func testTheCenterFallsBackWhenTheStoredSettingsDoNotFit() throws {
        // Written past the gate (an older page, a hand edit): the shell still checks on read
        let store = LocalRecordStore(fileURL: storeURL)
        let bad = gateJSON(#"{ "fillers": ["um"], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "" }"#)
        try store.set(sidekickId: "dictation", key: "settings:main", value: bad)
        let center = DictationTestCenter(store: store, device: device, now: clock)

        XCTAssertEqual(center.currentSettings(), builtIn)
        XCTAssertFalse(center.settingsAreSaved)
    }

    // MARK: Runs with their path

    func testAGatedRunIsSavedWithItsPathThroughTheManifest() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let decision = decide("email tell sam um hi")
        let gate = DictationGateOutcome(decision: decision, gateMs: 0.04)
        let result = DictationCleanupResult(cleanedText: "Hi Sam,\nHi.\nThanks", durationMs: 1_400, isFirstCall: false)

        center.save(DictationTestRuns.phrase("email tell sam um hi", result: result, source: .phrase, status: .available, at: fixedNow, gate: gate))

        XCTAssertNil(center.lastSaveError)
        let value = try XCTUnwrap(store.query(sidekickId: "dictation", keyPrefix: "run:").first?.value)
        XCTAssertEqual(value["path"]?.stringValue, "rewrite")
        XCTAssertEqual(value["trigger"]?.stringValue, "email")
        XCTAssertEqual(value["matched"], .array([.string("um")]))
        XCTAssertEqual(value["gateMs"]?.numberValue, 0.04)
        XCTAssertEqual(value["cleanupMs"]?.numberValue, 1_400)
        let summary = try XCTUnwrap(store.get(sidekickId: "dictation", key: "summary:main"))
        XCTAssertEqual(summary["paths"]?["rewrite"]?["runs"]?.numberValue, 1)
        XCTAssertEqual(summary["paths"]?["rewrite"]?["sharePercent"]?.numberValue, 100)
        XCTAssertEqual(summary["paths"]?["rewrite"]?["averageTotalMs"]?.numberValue, 1_400, "1,400 + 0.04 rounds to 1,400")
    }

    func testASkippedSpokenRunKeepsItsTimings() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let decision = decide("send it")
        let gate = DictationGateOutcome(decision: decision, gateMs: 0.02)
        let timings = DictationTimings(releasedAt: fixedNow, rawFinalAt: fixedNow.addingTimeInterval(0.250), cleanupStartedAt: fixedNow.addingTimeInterval(0.250),
                                       cleanedAt: fixedNow.addingTimeInterval(0.251))
        let result = DictationCleanupResult(cleanedText: decision.text, durationMs: 0, isFirstCall: false)

        center.save(DictationTestRuns.spoken(raw: "send it", result: result, timings: timings, status: .available, at: fixedNow, gate: gate))

        XCTAssertNil(center.lastSaveError)
        let value = try XCTUnwrap(store.query(sidekickId: "dictation", keyPrefix: "run:").first?.value)
        XCTAssertEqual(value["path"]?.stringValue, "skip")
        XCTAssertEqual(value["cleaned"]?.stringValue, "Send it.")
        XCTAssertEqual(value["matched"], .array([]))
        XCTAssertNil(value["trigger"])
        XCTAssertEqual(value["totalMs"]?.numberValue, 251)
    }

    func testARunWithoutTheGateHasNoGateFields() {
        let result = DictationCleanupResult(cleanedText: "x", durationMs: 5, isFirstCall: false)
        let value = DictationRunRecord.value(DictationTestRuns.phrase("x", result: result, source: .phrase, status: .available, at: fixedNow), device: device)

        XCTAssertNil(value["path"])
        XCTAssertNil(value["matched"])
        XCTAssertNil(value["trigger"])
        XCTAssertNil(value["gateMs"])
    }

    // MARK: Per-path summary

    /// The same runs as backend/test/dictation-gate.test.ts pathFixture().
    private func pathFixture() -> [LocalRecord] {
        let values = [
            #"{ "at": "2026-11-13T21:00:00.000Z", "path": "skip", "cleanupMs": 0, "totalMs": 310, "gateMs": 0.02 }"#,
            #"{ "at": "2026-11-13T21:01:00.000Z", "path": "skip", "cleanupMs": 0, "gateMs": 0.03 }"#,
            #"{ "at": "2026-11-13T21:02:00.000Z", "path": "light", "cleanupMs": 1500, "totalMs": 1800, "gateMs": 0.04 }"#,
            #"{ "at": "2026-11-13T21:03:00.000Z", "path": "light", "cleanupMs": 1300, "gateMs": 0.04 }"#,
            #"{ "at": "2026-11-13T21:04:00.000Z", "path": "rewrite", "cleanupMs": 1401, "gateMs": 0.5 }"#,
            #"{ "at": "2026-11-13T21:05:00.000Z", "path": "rewrite", "cleanupMs": 1600, "gateMs": 0.5 }"#,
            #"{ "at": "2026-11-13T20:00:00.000Z", "cleanupMs": 999 }"#,
        ]
        var records: [LocalRecord] = []
        for (index, value) in values.enumerated() {
            records.append(LocalRecord(sidekickId: "dictation", key: "run:\(index + 1)", value: gateJSON(value)))
        }
        return records
    }

    func testThePerPathSummaryMatchesThePage() {
        let summary = DictationRunRecord.summary(of: pathFixture(), updatedAt: fixedNow)

        XCTAssertEqual(summary["runs"]?.numberValue, 7, "every run still counts in the totals")
        XCTAssertEqual(summary["paths"], gateJSON(#"""
        { "skip": { "runs": 2, "sharePercent": 33, "averageTotalMs": 155 },
          "light": { "runs": 2, "sharePercent": 33, "averageTotalMs": 1550 },
          "rewrite": { "runs": 2, "sharePercent": 33, "averageTotalMs": 1501 } }
        """#))
    }

    func testAPathWithNoRunsHasNoAverageAndOldRunsHaveNoPaths() {
        let firstFour = Array(pathFixture().prefix(4))
        let summary = DictationRunRecord.summary(of: firstFour, updatedAt: fixedNow)
        XCTAssertEqual(summary["paths"]?["rewrite"], gateJSON(#"{ "runs": 0, "sharePercent": 0 }"#))
        XCTAssertEqual(summary["paths"]?["skip"]?["sharePercent"]?.numberValue, 50)

        let oldOnly = [pathFixture()[6]]
        XCTAssertNil(DictationRunRecord.summary(of: oldOnly, updatedAt: fixedNow)["paths"])
    }

    func testTheSummaryWithPathsFitsTheManifest() throws {
        let store = try gatedStore()
        let summary = DictationRunRecord.summary(of: pathFixture(), updatedAt: fixedNow)

        XCTAssertNoThrow(try store.set(sidekickId: "dictation", key: "summary:main", value: summary))
    }
}
#endif
