#if MIDAS_TEST_BUILD
// Dictation gate round 3 (TEST BUILD, founder 2026-11-14; docs/briefs/dictation-gate-test.md,
// "Round 3 build (founder approved 2026-11-14): do less, rules first"). Compiled only against a
// Test build: run with the "Midas Test" scheme's test action.
//
// The rule path (fillers removed with their commas; a simple correction of a number, time, weekday
// or month applied by rule; no model), light only for the corrections the rule cannot apply, the
// finishing on every path's output, the cut-down built-in settings (fifteen phrases, Run All ×3
// from settings:main's `repeat`), runs logging `prewarmed` and `thermal`, and the summary's heat
// shares through the Sidekick's real manifest.
import JavaScriptCore
import XCTest
@testable import Midas

private let roundThreeRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func roundThreeJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@MainActor
final class DictationRound3Tests: XCTestCase {
    private let builtIn = DictationGateSettings.builtIn
    private var storeURL: URL!
    private let device = DictationDeviceInfo(device: "iPhone17,1", ios: "27.0", build: "31")
    private let fixedNow = Date(timeIntervalSince1970: 1_763_150_000)
    private var modelSettings = DictationGateSettings.builtIn

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory.appending(path: "dictation-round3-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: storeURL)
        super.tearDown()
    }

    private func clock() -> Date {
        fixedNow
    }

    private func insert(_ text: String) -> DictationGateDecision {
        DictationGate.decideForInsert(text, settings: builtIn)
    }

    // MARK: The built-in settings

    func testTheBuiltInSettingsAreTheBriefsCutDownSet() {
        XCTAssertEqual(builtIn.fillers, ["um", "uh", "erm", "hmm"])
        XCTAssertEqual(builtIn.positionFillers, [])
        XCTAssertEqual(builtIn.corrections, ["no wait", "wait no", "scratch that", "make that", "I mean", "I meant", "actually", "sorry"])
        XCTAssertEqual(builtIn.triggers, [], "the trigger words are parked")
        XCTAssertEqual(builtIn.repeatCount, 3)
        XCTAssertEqual(builtIn.lightInstruction, "Remove the correction and the words it replaces. Change nothing else. Reply with the text only.")
        XCTAssertFalse(builtIn.lightInstruction.contains("\n"))
        XCTAssertFalse(builtIn.lightInstruction.contains("\""), "no examples in the instruction")
        XCTAssertEqual(DictationCleanup.instructions, builtIn.lightInstruction)
        var parkedWords: [String] = []
        for trigger in DictationGateSettings.builtInTriggers {
            parkedWords.append(trigger.word)
        }
        XCTAssertEqual(parkedWords, ["email", "formal", "casual", "list", "bullets"], "parked, still built in")
    }

    func testTheFifteenPhrasesTakeTheirPaths() {
        let phrases = DictationGateSettings.builtInPhrases
        XCTAssertEqual(phrases.count, 15)
        var counts: [DictationPath: Int] = [:]
        for phrase in phrases {
            counts[phrase.expect, default: 0] += 1
            XCTAssertEqual(DictationGate.decide(phrase.text, settings: builtIn).path, phrase.expect, phrase.text)
            XCTAssertEqual(insert(phrase.text).path, phrase.expect, phrase.text)
        }
        XCTAssertEqual(counts, [.skip: 5, .rule: 7, .light: 3])
    }

    func testTheSkipAndRulePhrasesAreInsertedAsTheRulesFinishThem() {
        let expected: [(String, String)] = [
            ("send the deck to Priya by friday", "Send the deck to Priya by Friday."),
            ("lunch with Maya on tuesday at 12:30", "Lunch with Maya on Tuesday at 12:30."),
            ("I like the new logo a lot", "I like the new logo a lot."),
            ("it was so good to see you yesterday", "It was so good to see you yesterday."),
            ("call David back before 5 tomorrow", "Call David back before 5 tomorrow."),
            ("uh tell mom im on my way", "Tell mom im on my way."),
            ("um pack the charger the passport and the tickets", "Pack the charger the passport and the tickets."),
            ("for the party we need uh cups plates napkins and ice", "For the party we need cups plates napkins and ice."),
            ("the call is at 2 no wait 3", "The call is at 3."),
            ("order 3 pizzas make that 4", "Order 4 pizzas."),
            ("book the table for friday no wait saturday", "Book the table for Saturday."),
            ("um be there at 5 no wait 6", "Be there at 6."),
        ]
        for (raw, inserted) in expected {
            let decision = insert(raw)
            XCTAssertEqual(decision.text, inserted, raw)
            XCTAssertNil(decision.instruction, raw)
        }
        XCTAssertEqual(insert("um be there at 5 no wait 6").matched, ["um", "no wait"])
        XCTAssertEqual(insert("order 3 pizzas make that 4").matched, ["make that"])
    }

    func testLightGetsTheTextAfterTheFillerRuleAndTheOneLineInstruction() {
        let decision = insert("um the browser is firefox scratch that chrome")

        XCTAssertEqual(decision.path, .light)
        XCTAssertEqual(decision.text, "the browser is firefox scratch that chrome")
        XCTAssertEqual(decision.matched, ["um", "scratch that"])
        XCTAssertEqual(decision.instruction, builtIn.lightInstruction)
        XCTAssertEqual(insert("send it to Tom I mean Tim").text, "send it to Tom I mean Tim")
    }

    // MARK: The filler rule

    func testFillersGoWithTheCommasNextToThem() {
        XCTAssertEqual(insert("we need, uh, cups").text, "We need cups.")
        XCTAssertEqual(insert("Um, call me").text, "Call me.")
        XCTAssertEqual(insert("call me, hmm").text, "Call me.")
        XCTAssertEqual(insert("fine. um, ok").text, "Fine. ok.")
        XCTAssertEqual(insert("UH ERM call me").text, "Call me.")
        XCTAssertEqual(insert("uh, so i guess friday works").text, "So I guess Friday works.")
        XCTAssertEqual(insert("um").path, .rule)
        XCTAssertEqual(insert("um").text, "")
    }

    func testFillersAreWholeWords() {
        XCTAssertEqual(insert("the umbrella is in the summary").path, .skip)
        XCTAssertEqual(insert("hmmm ok").path, .skip, "hmmm is not hmm")
        XCTAssertEqual(insert("hmmm ok").text, "Hmmm ok.")
    }

    func testPositionFillersFromTheSettingsAreRemovedToo() {
        let settings = DictationGateSettings(fillers: ["um"], positionFillers: ["like", "so"], corrections: [], triggers: [], lightInstruction: "x")

        let decision = DictationGate.decideForInsert("so um like I said we go", settings: settings)
        XCTAssertEqual(decision.path, .rule)
        XCTAssertEqual(decision.text, "I said we go.")
        XCTAssertEqual(DictationGate.decideForInsert("I like it", settings: settings).path, .skip)
    }

    func testAPhraseInBothListsCountsAsACorrection() {
        let settings = DictationGateSettings(fillers: ["um", "I mean"], positionFillers: [], corrections: ["I mean"], triggers: [], lightInstruction: "x")

        let decision = DictationGate.decideForInsert("um send it to Tom I mean Tim", settings: settings)
        XCTAssertEqual(decision.path, .light)
        XCTAssertEqual(decision.text, "send it to Tom I mean Tim")
    }

    // MARK: The simple correction rule

    func testNumbersTimesDaysAndMonthsAreCorrectedByRule() {
        let cases: [(String, String)] = [
            ("order three pizzas make that four", "Order four pizzas."),
            ("meet at 5:30 no wait 6:15", "Meet at 6:15."),
            ("meet at 5 pm no wait 6 pm", "Meet at 6 pm."),
            ("lunch at 12:30pm no wait 1pm", "Lunch at 1pm."),
            ("move it to march no wait april", "Move it to April."),
            ("the call is at 2, no wait, 3", "The call is at 3."),
            ("book 2 seats for friday make that saturday", "Book 2 seats for Saturday."),
            ("call at 4 sorry 5.", "Call at 5."),
        ]
        for (raw, inserted) in cases {
            let decision = insert(raw)
            XCTAssertEqual(decision.path, .rule, raw)
            XCTAssertEqual(decision.text, inserted, raw)
        }
    }

    func testCorrectionsTheRuleCannotApplyGoToTheModel() {
        let light = [
            "be there at 5 no wait 6 please",
            "the call is at 2 no wait 3 no wait 4",
            "be there at 5 no wait friday",
            "the browser is firefox scratch that chrome",
            "no wait 6",
            "meet at the park no wait 6",
            "i think i'm late no wait i'll be on time",
        ]
        for raw in light {
            XCTAssertEqual(insert(raw).path, .light, raw)
        }
    }

    func testTokensJoinTimesAcrossTheColonAndBeforeAmOrPm() {
        let words = DictationGate.words(in: "at 5:30 pm or 6pm or 7 am on friday in june, 3 or four")
        var kinds: [DictationGate.TokenKind?] = []
        for token in DictationGate.tokens(in: words) {
            kinds.append(token.kind)
        }
        XCTAssertEqual(kinds, [nil, .time, nil, .time, nil, .time, nil, .weekday, nil, .month, .number, nil, .number])
    }

    // MARK: Finishing

    func testFinishingSpellsTheListAndICapitalAndEnds() {
        XCTAssertEqual(DictationGate.finished("hi i'm sam and i like friday", settings: builtIn), "Hi I'm sam and I like Friday.")
        XCTAssertEqual(DictationGate.finished("i'll call, i've got it, i'd go", settings: builtIn), "I'll call, I've got it, I'd go.")
        XCTAssertEqual(DictationGate.finished("Done!", settings: builtIn), "Done!")
        XCTAssertEqual(DictationGate.finished("iphone and ipad", settings: builtIn), "Iphone and ipad.", "only the word i")
        XCTAssertEqual(DictationGate.capitalI("i am here"), "I am here")
    }

    func testARewriteStillWorksFromATriggerInTheSettings() {
        let trigger = DictationGateSettings.builtInTriggers[0]
        let settings = DictationGateSettings(fillers: ["um"], positionFillers: [], corrections: [], triggers: [trigger], lightInstruction: "x")

        let decision = DictationGate.decideForInsert("email um tell sam hi", settings: settings)
        XCTAssertEqual(decision.path, .rewrite)
        XCTAssertEqual(decision.trigger, "email")
        XCTAssertEqual(decision.text, "um tell sam hi")
        XCTAssertEqual(decision.instruction, trigger.instruction)
        XCTAssertEqual(insert("email tell sam hi").path, .skip, "no trigger words by default")
    }

    // MARK: Settings: repeat

    func testRepeatIsOptionalAndFromOneToTwenty() {
        let base = #"{ "fillers": ["um"], "positionFillers": [], "corrections": [], "triggers": [], "lightInstruction": "x""#
        XCTAssertEqual(DictationGateSettings.from(roundThreeJSON(base + "}"))?.repeatCount, 3, "missing: the built-in 3")
        XCTAssertEqual(DictationGateSettings.from(roundThreeJSON(base + #", "repeat": 7 }"#))?.repeatCount, 7)
        XCTAssertEqual(DictationGateSettings.from(roundThreeJSON(base + #", "repeat": 20 }"#))?.repeatCount, 20)
        for bad in ["0", "21", "2.5", "\"3\"", "null", "-1"] {
            let value = roundThreeJSON(base + #", "repeat": "# + bad + "}")
            XCTAssertNil(DictationGateSettings.from(value), bad)
            XCTAssertEqual(DictationGateSettings.resolved(value).settings, builtIn, bad)
        }
        var custom = builtIn
        custom.repeatCount = 9
        XCTAssertEqual(DictationGateSettings.from(custom.recordValue), custom)
        XCTAssertEqual(builtIn.recordValue["repeat"]?.numberValue, 3)
    }

    func testThePagesDefaultsCarryRepeatAndTheRulePath() throws {
        let toolsSource = try String(contentsOf: roundThreeRepoRoot.appending(path: "sidekicks/dictation/tools.js"), encoding: .utf8)
        let beginRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: begin */"))
        let endRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: end */", range: beginRange.upperBound..<toolsSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(toolsSource[beginRange.upperBound..<endRange.lowerBound]))
        XCTAssertNil(context.exception)

        let defaults = roundThreeJSON(try XCTUnwrap(context.evaluateScript("JSON.stringify(DictationLogic.defaultSettings())")?.toString()))
        let paths = roundThreeJSON(try XCTUnwrap(context.evaluateScript("JSON.stringify(DictationLogic.PATHS)")?.toString()))

        XCTAssertEqual(defaults, builtIn.recordValue)
        var pathNames: [JSONValue] = []
        for path in DictationPath.allCases {
            pathNames.append(.string(path.rawValue))
        }
        XCTAssertEqual(paths, .array(pathNames))
    }

    // MARK: Runs and the summary through the manifest

    private func gatedStore() throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: storeURL)
        let manifestURL = roundThreeRepoRoot.appending(path: "sidekicks/dictation/manifest.json")
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        let types = try XCTUnwrap(manifest["types"])
        func typesFor(_ sidekickId: String) -> JSONValue? {
            sidekickId == DictationRunRecord.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: try RecordSchemaEngine(), typesProvider: typesFor)
        return store
    }

    func testARuleRunIsSavedWithItsHeatAndNoPrewarmedField() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let decision = insert("um be there at 5 no wait 6")
        let gate = DictationGateOutcome(decision: decision, gateMs: 0.05)
        let result = DictationCleanupResult(cleanedText: decision.text, durationMs: 0, isFirstCall: false)

        center.save(DictationTestRuns.phrase("um be there at 5 no wait 6", result: result, source: .runAll, status: .available, at: fixedNow,
                                             gate: gate, expect: .rule, thermal: .fair))

        XCTAssertNil(center.lastSaveError)
        let value = try XCTUnwrap(store.query(sidekickId: "dictation", keyPrefix: "run:").first?.value)
        XCTAssertEqual(value["path"]?.stringValue, "rule")
        XCTAssertEqual(value["expect"]?.stringValue, "rule")
        XCTAssertEqual(value["cleaned"]?.stringValue, "Be there at 6.")
        XCTAssertEqual(value["thermal"]?.stringValue, "fair")
        XCTAssertNil(value["prewarmed"], "no model call")
        let summary = try XCTUnwrap(store.get(sidekickId: "dictation", key: "summary:main"))
        XCTAssertEqual(summary["paths"]?["rule"]?["runs"]?.numberValue, 1)
        XCTAssertEqual(summary["thermal"]?["fair"], roundThreeJSON(#"{ "runs": 1, "sharePercent": 100 }"#))
    }

    func testALightRunSavesWhetherItsSessionWasPrewarmed() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let decision = insert("send it to Tom I mean Tim")
        let gate = DictationGateOutcome(decision: decision, gateMs: 0.04)
        let result = DictationCleanupResult(cleanedText: "Send it to Tim.", durationMs: 980, isFirstCall: false, prewarmed: true)
        let timings = DictationTimings(releasedAt: fixedNow, rawFinalAt: fixedNow.addingTimeInterval(0.2), cleanupStartedAt: fixedNow.addingTimeInterval(0.2),
                                       cleanedAt: fixedNow.addingTimeInterval(1.18))

        center.save(DictationTestRuns.spoken(raw: "send it to Tom I mean Tim", result: result, timings: timings, status: .available, at: fixedNow,
                                             gate: gate, thermal: .serious))

        XCTAssertNil(center.lastSaveError)
        let value = try XCTUnwrap(store.query(sidekickId: "dictation", keyPrefix: "run:").first?.value)
        XCTAssertEqual(value["prewarmed"], .bool(true))
        XCTAssertEqual(value["thermal"]?.stringValue, "serious")
        XCTAssertEqual(value["path"]?.stringValue, "light")
    }

    func testARunWithoutHeatOrModelHasNeitherField() {
        let result = DictationCleanupResult(cleanedText: "x", durationMs: 0, isFirstCall: false)
        XCTAssertNil(result.prewarmed)
        let value = DictationRunRecord.value(DictationTestRuns.phrase("x", result: result, source: .phrase, status: .available, at: fixedNow), device: device)

        XCTAssertNil(value["prewarmed"])
        XCTAssertNil(value["thermal"])
    }

    /// The same runs as backend/test/dictation-round3.test.ts heatFixture().
    private func heatFixture() -> [LocalRecord] {
        let values = [
            #"{ "at": "2026-11-14T19:00:00.000Z", "path": "rule", "cleanupMs": 0, "gateMs": 0.03, "thermal": "nominal" }"#,
            #"{ "at": "2026-11-14T19:01:00.000Z", "path": "skip", "cleanupMs": 0, "gateMs": 0.03, "thermal": "nominal" }"#,
            #"{ "at": "2026-11-14T19:02:00.000Z", "path": "rule", "cleanupMs": 0, "gateMs": 0.03, "thermal": "nominal" }"#,
            #"{ "at": "2026-11-14T19:03:00.000Z", "path": "light", "cleanupMs": 900, "gateMs": 0.03, "prewarmed": true, "thermal": "fair" }"#,
            #"{ "at": "2026-11-14T19:04:00.000Z", "path": "light", "cleanupMs": 1500, "gateMs": 0.03, "prewarmed": false, "thermal": "serious" }"#,
            #"{ "at": "2026-11-14T18:00:00.000Z", "path": "light", "cleanupMs": 2000, "gateMs": 0.03 }"#,
        ]
        var records: [LocalRecord] = []
        for (index, value) in values.enumerated() {
            records.append(LocalRecord(sidekickId: "dictation", key: "run:\(index + 1)", value: roundThreeJSON(value)))
        }
        return records
    }

    func testTheSummaryHasTheRulePathAndTheHeatSharesAsThePageCountsThem() throws {
        let summary = DictationRunRecord.summary(of: heatFixture(), updatedAt: fixedNow)

        XCTAssertEqual(summary["paths"]?["rule"], roundThreeJSON(#"{ "runs": 2, "sharePercent": 33, "averageTotalMs": 0 }"#))
        XCTAssertEqual(summary["paths"]?["light"], roundThreeJSON(#"{ "runs": 3, "sharePercent": 50, "averageTotalMs": 1467 }"#))
        XCTAssertEqual(summary["thermal"], roundThreeJSON(#"""
        { "nominal": { "runs": 3, "sharePercent": 60 }, "fair": { "runs": 1, "sharePercent": 20 },
          "serious": { "runs": 1, "sharePercent": 20 }, "critical": { "runs": 0, "sharePercent": 0 } }
        """#))
        XCTAssertNil(DictationRunRecord.summary(of: [heatFixture()[5]], updatedAt: fixedNow)["thermal"])
        XCTAssertNoThrow(try gatedStore().set(sidekickId: "dictation", key: "summary:main", value: summary))
    }

    func testTheHeatStatesMapFromTheSystem() {
        XCTAssertEqual(DictationThermal.from(.nominal), .nominal)
        XCTAssertEqual(DictationThermal.from(.fair), .fair)
        XCTAssertEqual(DictationThermal.from(.serious), .serious)
        XCTAssertEqual(DictationThermal.from(.critical), .critical)
        XCTAssertEqual(DictationThermal.allCases.map(\.rawValue), ["nominal", "fair", "serious", "critical"])
    }

    // MARK: The screen reads repeat from the settings

    private func currentModelSettings() -> DictationGateSettings {
        modelSettings
    }

    func testTheScreenReadsRunAllsRepeatFromTheSettings() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("the screen needs iOS 26")
        }
        let model = DictationTestModel(settings: currentModelSettings)
        XCTAssertEqual(model.repeatCount, 3, "built-in before the screen opens")
        var custom = DictationGateSettings.builtIn
        custom.repeatCount = 6
        modelSettings = custom

        model.appeared()

        XCTAssertEqual(model.repeatCount, 6)
        XCTAssertEqual(model.phrases, DictationGateSettings.builtInPhrases)
    }
}
#endif
