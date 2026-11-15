#if MIDAS_TEST_BUILD
// Dictation gate round 4 (TEST BUILD, founder 2026-11-14; docs/briefs/dictation-gate-test.md,
// "Round 4 build (founder approved 2026-11-14): corrections by rule, the model only points").
// Compiled only against a Test build: run with the "Midas Test" scheme's test action.
//
// Cues split into strong (rules may act) and weak (model pointer only); a cue with no words before
// or after it is not a correction; the value rule takes words said again ("room 4 sorry room 5");
// the anchor rule and the one-word swap for strong cues; the model pointer's words checked and
// applied by the code (nothing the model writes is inserted); twenty phrases; settings:main's
// strongCues, weakCues and anchors; light runs log pointer and pointerValid; the summary's
// pointer numbers through the Sidekick's real manifest.
import JavaScriptCore
import XCTest
@testable import Midas

private let roundFourRepoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func roundFourJSON(_ text: String) -> JSONValue {
    return try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@MainActor
final class DictationRound4Tests: XCTestCase {
    private let builtIn = DictationGateSettings.builtIn
    private var storeURL: URL!
    private let device = DictationDeviceInfo(device: "iPhone17,1", ios: "27.0", build: "32")
    private let fixedNow = Date(timeIntervalSince1970: 1_763_160_000)

    override func setUp() {
        super.setUp()
        storeURL = FileManager.default.temporaryDirectory.appending(path: "dictation-round4-\(UUID().uuidString).json")
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

    func testTheBuiltInCuesAnchorsAndPointerInstructionAreTheBriefs() {
        XCTAssertEqual(builtIn.strongCues, ["scratch that", "no wait", "wait no", "I mean", "I meant", "make that", "no no"])
        XCTAssertEqual(builtIn.weakCues, ["actually", "sorry"])
        XCTAssertEqual(builtIn.anchors, ["the", "a", "an", "to", "at", "on", "in", "for", "with", "my", "your", "our", "his", "her", "their"])
        XCTAssertEqual(builtIn.corrections, builtIn.strongCues + builtIn.weakCues)
        XCTAssertEqual(builtIn.lightInstruction,
                       "The words after the bracketed cue may correct words just before it. Give those replaced words exactly as written, or leave it empty when nothing is replaced.")
        XCTAssertFalse(builtIn.lightInstruction.contains("\n"))
        XCTAssertFalse(builtIn.lightInstruction.contains("\""), "no examples in the instruction")
        XCTAssertEqual(builtIn.repeatCount, 3)
        XCTAssertEqual(DictationCleanup.instructions, builtIn.lightInstruction)
    }

    func testTheTwentyPhrasesTakeTheirPaths() {
        let phrases = DictationGateSettings.builtInPhrases
        XCTAssertEqual(phrases.count, 20)
        var counts: [DictationPath: Int] = [:]
        for phrase in phrases {
            counts[phrase.expect, default: 0] += 1
            XCTAssertEqual(DictationGate.decide(phrase.text, settings: builtIn).path, phrase.expect, phrase.text)
            XCTAssertEqual(insert(phrase.text).path, phrase.expect, phrase.text)
        }
        XCTAssertEqual(counts, [.skip: 5, .rule: 13, .light: 2])
        XCTAssertEqual(phrases[15].text, "meet at noon scratch that at 1 pm")
        XCTAssertEqual(phrases[19].text, "send the file to Sam no wait to Priya")
    }

    func testTheNewRulePhrasesAreInsertedAsTheBriefSays() {
        let expected: [(String, String)] = [
            ("the browser is firefox scratch that chrome", "The browser is chrome."),
            ("send it to Tom I mean Tim", "Send it to Tim."),
            ("meet at the cafe on 5th street scratch that the library", "Meet at the library."),
            ("meet at noon scratch that at 1 pm", "Meet at 1 pm."),
            ("the meeting is in room 4 sorry room 5", "The meeting is in room 5."),
            ("send the file to Sam no wait to Priya", "Send the file to Priya."),
            ("the call is at 2 no wait 3", "The call is at 3."),
            ("book the table for friday no wait saturday", "Book the table for Saturday."),
        ]
        for (raw, inserted) in expected {
            let decision = insert(raw)
            XCTAssertEqual(decision.path, .rule, raw)
            XCTAssertEqual(decision.text, inserted, raw)
            XCTAssertNil(decision.instruction, raw)
            XCTAssertNil(decision.cue, raw)
        }
    }

    // MARK: The rules

    func testACueWithNoWordsBeforeOrAfterItIsNotACorrection() {
        XCTAssertEqual(insert("sorry I'm late").path, .skip)
        XCTAssertEqual(insert("sorry I'm late").text, "Sorry I'm late.")
        let fillerFirst = insert("um actually I'm on my way")
        XCTAssertEqual(fillerFirst.path, .rule, "the filler goes; the cue then starts the text")
        XCTAssertEqual(fillerFirst.text, "Actually I'm on my way.")
        XCTAssertEqual(insert("I'm so sorry").path, .skip)
        XCTAssertEqual(insert("no wait").path, .skip)
    }

    func testAWeakCueGetsTheValueRuleButNoAnchorOrSwap() {
        XCTAssertEqual(insert("the call is at 2 sorry 3").text, "The call is at 3.")
        XCTAssertEqual(insert("the call is at 2 sorry 3").path, .rule)
        XCTAssertEqual(insert("the browser is firefox sorry chrome").path, .light)
        XCTAssertEqual(insert("send the file to Sam actually to Priya").path, .light)
    }

    func testWordsSaidAgainMustBeTheOnesBeforeTheOldValue() {
        XCTAssertEqual(insert("the meeting is in room 4 sorry room 5").text, "The meeting is in room 5.")
        XCTAssertEqual(insert("call at 2 I mean call at 3").text, "Call at 3.")
        XCTAssertEqual(insert("the meeting is in room 4 sorry hall 5").path, .light, "hall is not what was said before 4")
        XCTAssertEqual(insert("order 3 pizzas make that 4").text, "Order 4 pizzas.")
    }

    func testTheAnchorRuleNeedsTheAnchorSaidBeforeAndAWordAfterIt() {
        XCTAssertEqual(insert("meet at the cafe on 5th street scratch that the library").text, "Meet at the library.")
        XCTAssertEqual(insert("put it on the desk no wait on the shelf").text, "Put it on the shelf.", "the last 'on' before the cue")
        XCTAssertEqual(insert("meet at noon scratch that at").path, .light, "an anchor alone after the cue")
        XCTAssertEqual(insert("call Sam scratch that the office").path, .light, "'the' was not said before the cue")
        var noAnchors = builtIn
        noAnchors.anchors = []
        XCTAssertEqual(DictationGate.decideForInsert("meet at the cafe scratch that the library", settings: noAnchors).path, .light)
    }

    func testTheSwapTakesExactlyOneWordThatIsNotAnAnchor() {
        XCTAssertEqual(insert("send it to Tom I mean Tim").text, "Send it to Tim.")
        XCTAssertEqual(insert("The browser is Firefox, scratch that, Chrome.").text, "The browser is Chrome.")
        XCTAssertEqual(insert("send it to Tom scratch that to").path, .light)
        XCTAssertEqual(insert("invite Ana and Jonas scratch that just Ana").path, .light, "two words, not an anchor")
    }

    func testTwoCuesGoToThePointerOnTheLastOne() {
        let decision = insert("send it to Tom no wait Tim I mean Jim")
        XCTAssertEqual(decision.path, .light)
        XCTAssertEqual(decision.text, "send it to Tom no wait Tim I mean Jim")
        XCTAssertEqual(decision.cue, 7..<9)
        XCTAssertEqual(decision.instruction, builtIn.lightInstruction)
    }

    // MARK: The model pointer

    func testLightMarksTheCueForThePointer() throws {
        let invite = insert("invite Ana and Jonas scratch that just Ana")
        XCTAssertEqual(invite.path, .light)
        XCTAssertEqual(invite.matched, ["scratch that"])
        let inviteCue = try XCTUnwrap(invite.cue)
        XCTAssertEqual(inviteCue, 4..<6)
        XCTAssertEqual(DictationGate.markedText(invite.text, cue: inviteCue), "invite Ana and Jonas [scratch that] just Ana")

        let plan = insert("um, I actually like the new plan")
        XCTAssertEqual(plan.path, .light)
        XCTAssertEqual(plan.text, "I actually like the new plan", "the model gets the text after the filler rule")
        let planCue = try XCTUnwrap(plan.cue)
        XCTAssertEqual(DictationGate.markedText(plan.text, cue: planCue), "I [actually] like the new plan")
        XCTAssertNil(DictationGate.markedText(plan.text, cue: 0..<1))
    }

    func testThePointersWordsAreCheckedAndAppliedByTheCode() {
        let text = "invite Ana and Jonas scratch that just Ana"
        let cue = 4..<6
        XCTAssertEqual(DictationGate.applyPointer("Ana and Jonas", to: text, cue: cue), DictationPointerOutcome(text: "invite just Ana", isValid: true))
        XCTAssertEqual(DictationGate.applyPointer("and JONAS,", to: text, cue: cue), DictationPointerOutcome(text: "invite Ana just Ana", isValid: true))
        XCTAssertEqual(DictationGate.applyPointer("Jonas", to: text, cue: cue), DictationPointerOutcome(text: "invite Ana and just Ana", isValid: true))
        XCTAssertEqual(DictationGate.applyPointer("  ", to: text, cue: cue), DictationPointerOutcome(text: text, isValid: true), "empty: as said")
        XCTAssertEqual(DictationGate.applyPointer("Ana", to: text, cue: cue), DictationPointerOutcome(text: text, isValid: false), "not right before the cue")
        XCTAssertEqual(DictationGate.applyPointer("Priya", to: text, cue: cue), DictationPointerOutcome(text: text, isValid: false), "never said")
        XCTAssertEqual(DictationGate.applyPointer("please invite Ana and Jonas", to: text, cue: cue), DictationPointerOutcome(text: text, isValid: false))
        XCTAssertEqual(DictationGate.applyPointer("Ana and Jonas", to: text, cue: 7..<8), DictationPointerOutcome(text: text, isValid: false), "no cue there")
        let plan = "I actually like the new plan"
        XCTAssertEqual(DictationGate.applyPointer("", to: plan, cue: 1..<2), DictationPointerOutcome(text: plan, isValid: true))
        XCTAssertEqual(DictationGate.finished("invite just Ana", settings: builtIn), "Invite just Ana.")
    }

    func testThePointerLabelSaysTheWordsOrNone() throws {
        guard #available(iOS 26, *) else {
            throw XCTSkip("the screen needs iOS 26")
        }
        XCTAssertEqual(DictationTestView.pointerLabel("Ana and Jonas", isValid: true), "Pointer: Ana and Jonas")
        XCTAssertEqual(DictationTestView.pointerLabel("", isValid: true), "Pointer: None")
        XCTAssertEqual(DictationTestView.pointerLabel("Tom", isValid: false), "Pointer Invalid: Tom")
    }

    // MARK: Settings

    private let roundThreeRecord = #"{ "fillers": ["um"], "positionFillers": [], "corrections": ["no wait", "Sorry", "hold on"], "triggers": [], "lightInstruction": "x""#

    func testARoundThreeRecordSplitsItsCorrections() throws {
        let settings = try XCTUnwrap(DictationGateSettings.from(roundFourJSON(roundThreeRecord + "}")))
        XCTAssertEqual(settings.strongCues, ["no wait", "hold on"])
        XCTAssertEqual(settings.weakCues, ["Sorry"])
        XCTAssertEqual(settings.anchors, DictationGateSettings.builtInAnchors)
        XCTAssertEqual(DictationGate.decideForInsert("call Tom hold on Tim", settings: settings).text, "Call Tim.")
        XCTAssertEqual(DictationGate.decideForInsert("call Tom sorry Tim", settings: settings).path, .light)
    }

    func testTheCueListsCountWhenTogetherTheyAreTheCorrections() throws {
        let matching = roundThreeRecord.replacingOccurrences(of: #""corrections": ["no wait", "Sorry", "hold on"]"#,
                                                             with: #""corrections": ["NO WAIT", "sorry", "hold on"]"#)
            + #", "strongCues": ["no wait"], "weakCues": ["sorry", "hold on"], "anchors": ["near"] }"#
        let settings = try XCTUnwrap(DictationGateSettings.from(roundFourJSON(matching)))
        XCTAssertEqual(settings.strongCues, ["no wait"])
        XCTAssertEqual(settings.weakCues, ["sorry", "hold on"])
        XCTAssertEqual(settings.anchors, ["near"])
        XCTAssertEqual(DictationGate.decideForInsert("call Tom hold on Tim", settings: settings).path, .light, "hold on is weak here")

        let stale = roundThreeRecord + #", "strongCues": ["scratch that"], "weakCues": ["actually"] }"#
        let staleSettings = try XCTUnwrap(DictationGateSettings.from(roundFourJSON(stale)))
        XCTAssertEqual(staleSettings.strongCues, ["no wait", "hold on"], "corrections changed by an older writer win")
        XCTAssertEqual(staleSettings.weakCues, ["Sorry"])
    }

    func testCueListsAndAnchorsThatDoNotFitFallBackToTheBuiltInSettings() {
        let tooMany = Array(repeating: #""a""#, count: 30).joined(separator: ", ")
        let tooManyWeak = Array(repeating: #""b""#, count: 21).joined(separator: ", ")
        let bad = [
            #", "strongCues": [""] }"#,
            #", "weakCues": "sorry" }"#,
            #", "anchors": ["\#(String(repeating: "x", count: 41))"] }"#,
            ", \"strongCues\": [\(tooMany)], \"weakCues\": [\(tooManyWeak)] }",
        ]
        for ending in bad {
            let value = roundFourJSON(roundThreeRecord + ending)
            XCTAssertNil(DictationGateSettings.from(value), ending)
            XCTAssertEqual(DictationGateSettings.resolved(value).settings, builtIn, ending)
        }
    }

    func testTheRecordCarriesTheCueListsAndReadsBack() throws {
        let record = builtIn.recordValue
        XCTAssertEqual(record["strongCues"], .array(builtIn.strongCues.map(JSONValue.string)))
        XCTAssertEqual(record["weakCues"], .array(["actually", "sorry"].map(JSONValue.string)))
        XCTAssertEqual(record["anchors"]?.arrayValue?.count, 15)
        XCTAssertEqual(record["corrections"], .array((builtIn.strongCues + builtIn.weakCues).map(JSONValue.string)))
        XCTAssertEqual(DictationGateSettings.from(record), builtIn)

        let custom = try XCTUnwrap(DictationGateSettings.from(roundFourJSON(roundThreeRecord
            .replacingOccurrences(of: #""corrections": ["no wait", "Sorry", "hold on"]"#, with: #""corrections": ["no wait", "hold on"]"#)
            + #", "strongCues": ["no wait"], "weakCues": ["hold on"], "anchors": ["near"] }"#)))
        XCTAssertEqual(DictationGateSettings.from(custom.recordValue), custom)
        XCTAssertEqual(custom.recordValue["corrections"], .array(["no wait", "hold on"].map(JSONValue.string)))
    }

    func testThePagesDefaultsAreTheShellsBuiltInSettings() throws {
        let toolsSource = try String(contentsOf: roundFourRepoRoot.appending(path: "sidekicks/dictation/tools.js"), encoding: .utf8)
        let beginRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: begin */"))
        let endRange = try XCTUnwrap(toolsSource.range(of: "/* copied from index.html: end */", range: beginRange.upperBound..<toolsSource.endIndex))
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(String(toolsSource[beginRange.upperBound..<endRange.lowerBound]))
        XCTAssertNil(context.exception)

        let defaults = roundFourJSON(try XCTUnwrap(context.evaluateScript("JSON.stringify(DictationLogic.defaultSettings())")?.toString()))
        XCTAssertEqual(defaults, builtIn.recordValue)
    }

    // MARK: Runs and the summary through the manifest

    private func gatedStore() throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: storeURL)
        let manifestURL = roundFourRepoRoot.appending(path: "sidekicks/dictation/manifest.json")
        let manifest = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: manifestURL))
        let types = try XCTUnwrap(manifest["types"])
        func typesFor(_ sidekickId: String) -> JSONValue? {
            sidekickId == DictationRunRecord.sidekickId ? types : nil
        }
        store.writeGate = RecordTypeGate.make(engine: try RecordSchemaEngine(), typesProvider: typesFor)
        return store
    }

    func testALightRunSavesThePointerAndTheSummaryCountsIt() throws {
        let store = try gatedStore()
        let center = DictationTestCenter(store: store, device: device, now: clock)
        center.openFromHome()
        let raw = "invite Ana and Jonas scratch that just Ana"
        let gate = DictationGateOutcome(decision: insert(raw), gateMs: 0.04)
        let valid = DictationCleanupResult(cleanedText: "Invite just Ana.", durationMs: 820, isFirstCall: false, prewarmed: true, pointer: "Ana and Jonas",
                                           pointerValid: true)
        let empty = DictationCleanupResult(cleanedText: "Invite Ana and Jonas scratch that just Ana.", durationMs: 800, isFirstCall: false, prewarmed: true,
                                           pointer: "", pointerValid: true)
        let invalid = DictationCleanupResult(cleanedText: "Invite Ana and Jonas scratch that just Ana.", durationMs: 900, isFirstCall: false, prewarmed: true,
                                             pointer: "Tom", pointerValid: false)

        for result in [valid, empty, invalid] {
            center.save(DictationTestRuns.phrase(raw, result: result, source: .runAll, status: .available, at: fixedNow, gate: gate, expect: .light,
                                                 thermal: .nominal))
        }

        XCTAssertNil(center.lastSaveError)
        let runs = store.query(sidekickId: "dictation", keyPrefix: "run:")
        var logged: [String] = []
        for run in runs {
            let pointer = run.value["pointer"]?.stringValue ?? "missing"
            let pointerValid = run.value["pointerValid"] == .bool(true) ? "valid" : "invalid"
            logged.append(pointer + "|" + pointerValid)
        }
        XCTAssertEqual(logged.sorted(), ["Ana and Jonas|valid", "Tom|invalid", "|valid"])
        let summary = try XCTUnwrap(store.get(sidekickId: "dictation", key: "summary:main"))
        XCTAssertEqual(summary["pointer"], roundFourJSON(#"{ "runs": 3, "valid": 2, "empty": 1, "sharePercent": 67 }"#))
    }

    func testARunWithoutAPointerHasNoPointerFieldsAndNoPointerSummary() throws {
        let result = DictationCleanupResult(cleanedText: "Be there at 6.", durationMs: 0, isFirstCall: false)
        let run = DictationTestRuns.phrase("um be there at 5 no wait 6", result: result, source: .phrase, status: .available, at: fixedNow)
        let value = DictationRunRecord.value(run, device: device)
        XCTAssertNil(value["pointer"])
        XCTAssertNil(value["pointerValid"])
        let record = LocalRecord(sidekickId: "dictation", key: "run:1", value: value)
        XCTAssertNil(DictationRunRecord.summary(of: [record], updatedAt: fixedNow)["pointer"])
    }

    func testALongPointerIsShortenedToTheManifestsLimit() throws {
        let long = String(repeating: "word ", count: 100)
        let result = DictationCleanupResult(cleanedText: "x", durationMs: 700, isFirstCall: false, prewarmed: true, pointer: long, pointerValid: false)
        let run = DictationTestRuns.phrase("x", result: result, source: .phrase, status: .available, at: fixedNow)
        let value = DictationRunRecord.value(run, device: device)
        XCTAssertEqual(value["pointer"]?.stringValue?.count, 400)
        XCTAssertNoThrow(try gatedStore().set(sidekickId: "dictation", key: "run:long", value: value))
    }

    /// The same runs as backend/test/dictation-round4.test.ts pointerFixture().
    func testTheSummaryCountsThePointerAsThePageDoes() throws {
        let values = [
            #"{ "at": "2026-11-14T21:00:00.000Z", "path": "light", "cleanupMs": 850, "pointer": "Ana and Jonas", "pointerValid": true }"#,
            #"{ "at": "2026-11-14T21:01:00.000Z", "path": "light", "cleanupMs": 850, "pointer": "", "pointerValid": true }"#,
            #"{ "at": "2026-11-14T21:02:00.000Z", "path": "light", "cleanupMs": 900, "pointer": "Tom", "pointerValid": false }"#,
            #"{ "at": "2026-11-14T21:03:00.000Z", "path": "rule", "cleanupMs": 0 }"#,
        ]
        var records: [LocalRecord] = []
        for (index, value) in values.enumerated() {
            records.append(LocalRecord(sidekickId: "dictation", key: "run:\(index + 1)", value: roundFourJSON(value)))
        }
        let summary = DictationRunRecord.summary(of: records, updatedAt: fixedNow)
        XCTAssertEqual(summary["pointer"], roundFourJSON(#"{ "runs": 3, "valid": 2, "empty": 1, "sharePercent": 67 }"#))
        XCTAssertNoThrow(try gatedStore().set(sidekickId: "dictation", key: "summary:main", value: summary))
    }
}
#endif
