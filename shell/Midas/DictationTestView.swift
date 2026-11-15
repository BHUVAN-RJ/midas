#if MIDAS_TEST_BUILD
// Dictation test screen (TEST BUILD, founder 2026-11-13; branch agent/dictation-test, never
// merged). Compiled only in the Test configuration. Opened by a long press on "Midas" at the top
// of the home grid.
import SwiftUI

/// What the screen shows and does: hold to talk, the five fixed phrases, Run all.
@available(iOS 26, *)
@MainActor
@Observable
final class DictationTestModel {
    private(set) var status: DictationModelStatus = .current()
    private(set) var rawText = ""
    private(set) var cleanedText = ""
    private(set) var isListening = false
    private(set) var isCleaning = false
    private(set) var lastTimings: DictationTimings?
    /// Cleanup time of the phrase tapped last (cleanup only, no speaking).
    private(set) var lastPhraseCleanupMs: Int?
    private(set) var firstCallMs: Int?
    private(set) var lastWarmCallMs: Int?
    private(set) var runAllSummaries: [DictationRunSummary] = []
    private(set) var runAllProgress: String?
    private(set) var errorMessage: String?
    /// The gate's decision for the last run and how long it took.
    private(set) var lastGate: DictationGateOutcome?
    /// The path each phrase took in the last Run All.
    private(set) var runAllPaths: [String: DictationPath] = [:]
    /// The phrases on screen and in Run All: settings:main's, else the built-in ones. Read when the
    /// screen opens and again before each Run All.
    private(set) var phrases: [DictationTestPhrase] = DictationGateSettings.builtInPhrases
    /// Expected against actual path over the last Run All.
    private(set) var pathCheck = DictationPathCheck()
    /// How many times Run All runs each phrase: settings:main's `repeat` (round 3), read with the
    /// phrases.
    private(set) var repeatCount = DictationGateSettings.builtInRepeat
    /// The words the model pointer returned on the last light run (round 4); nil on other paths.
    private(set) var lastPointer: String?
    /// Whether those words ended right before the cue; nil on other paths.
    private(set) var lastPointerValid: Bool?

    private let transcriber = OnDeviceSpeechTranscriber(options: .longDictation)
    private let cleaner = DictationCleaner()
    private var isHolding = false
    private var releasedAt: Date?
    /// The settings the current run's gate used; its model answer is finished with them.
    private var runSettings = DictationGateSettings.builtIn
    /// Each cleanup run, for the Dictation Sidekick's records (DictationTestCenter.save).
    private let onRun: (@MainActor (DictationRun) -> Void)?
    /// The gate's settings, read before every run (DictationTestCenter.currentSettings).
    private let settings: @MainActor () -> DictationGateSettings

    init(onRun: (@MainActor (DictationRun) -> Void)? = nil, settings: @escaping @MainActor () -> DictationGateSettings = DictationTestModel.builtInSettings) {
        self.onRun = onRun
        self.settings = settings
    }

    static func builtInSettings() -> DictationGateSettings {
        .builtIn
    }

    var isBusy: Bool {
        isListening || isCleaning || runAllProgress != nil
    }

    /// Screen opened: read the model status and load the model, so the first call is timed apart.
    func appeared() {
        status = .current()
        let currentSettings = settings()
        phrases = currentSettings.phrases
        repeatCount = currentSettings.repeatCount
        if status.isAvailable {
            cleaner.prewarm(instructions: currentSettings.lightInstruction)
        }
    }

    // MARK: Hold to talk

    func pressBegan() {
        guard !isHolding, !isBusy else {
            return
        }
        isHolding = true
        rawText = ""
        cleanedText = ""
        lastTimings = nil
        errorMessage = nil
        releasedAt = nil
        Task { @MainActor in
            await startListening()
        }
    }

    private func startListening() async {
        do {
            try await transcriber.start(sessionStartedAt: Date(), onUpdate: heard, onEnd: listeningEnded)
            isListening = true
            // Let go before the microphone was ready
            if !isHolding {
                release()
            }
        } catch {
            isHolding = false
            errorMessage = "Can't Listen: \(error)"
        }
    }

    func pressEnded() {
        guard isHolding else {
            return
        }
        isHolding = false
        if isListening {
            release()
        }
    }

    private func release() {
        releasedAt = Date()
        transcriber.stopAndAwaitFinal()
    }

    private func heard(_ transcript: VoiceTranscript) {
        rawText = transcript.text
    }

    private func listeningEnded(_ reason: VoiceTranscriptionEnd) {
        let rawFinalAt = Date()
        isListening = false
        isHolding = false
        if reason == .failed {
            let failure = transcriber.lastFailure?.summary ?? "no details"
            errorMessage = "Recogniser Failed: \(failure)"
        }
        // Ended by the 10 minute backstop: no release
        let released = releasedAt ?? rawFinalAt
        Task { @MainActor in
            await cleanSpoken(releasedAt: released, rawFinalAt: rawFinalAt)
        }
    }

    private func cleanSpoken(releasedAt: Date, rawFinalAt: Date) async {
        isCleaning = true
        defer {
            isCleaning = false
        }
        let gate = runGate(rawText)
        let cleanupStartedAt = Date()
        do {
            guard let result = try await finish(gate) else {
                return
            }
            let cleanedAt = Date()
            cleanedText = result.cleanedText
            let timings = DictationTimings(releasedAt: releasedAt, rawFinalAt: rawFinalAt, cleanupStartedAt: cleanupStartedAt, cleanedAt: cleanedAt)
            lastTimings = timings
            record(result, path: gate.decision.path)
            report(DictationTestRuns.spoken(raw: rawText, result: result, timings: timings, status: status, at: cleanedAt, gate: gate,
                                            thermal: .current()))
        } catch {
            errorMessage = "Cleanup Failed: \(error)"
        }
    }

    // MARK: The gate

    /// The gate on the raw text, timed.
    private func runGate(_ raw: String) -> DictationGateOutcome {
        let currentSettings = settings()
        runSettings = currentSettings
        let clock = ContinuousClock()
        let startedAt = clock.now
        let decision = DictationGate.decideForInsert(raw, settings: currentSettings)
        let gateMs = DictationGateTiming.milliseconds(clock.now - startedAt)
        let outcome = DictationGateOutcome(decision: decision, gateMs: gateMs)
        lastGate = outcome
        lastPointer = nil
        lastPointerValid = nil
        return outcome
    }

    /// The text to insert: as the rules left it for skip and rule (no model), else the model with
    /// the path's instruction, its answer finished by rule (round 3: capitalise list, "I", first
    /// letter, end punctuation on every path). Nil when there is nothing to clean.
    private func finish(_ gate: DictationGateOutcome) async throws -> DictationCleanupResult? {
        let decision = gate.decision
        guard let instruction = decision.instruction else {
            guard !decision.text.isEmpty else {
                return nil
            }
            return DictationCleanupResult(cleanedText: decision.text, durationMs: 0, isFirstCall: false)
        }
        guard status.isAvailable else {
            throw DictationGateError.modelNotAvailable(status.label)
        }
        // Round 4: light is the model pointer; the code edits the text, the model only names words
        if decision.path == .light, let cue = decision.cue {
            return try await point(decision, cue: cue, instruction: instruction)
        }
        guard let answer = try await cleaner.clean(decision.text, instructions: instruction) else {
            return nil
        }
        let finishedText = DictationGate.finished(answer.cleanedText, settings: runSettings)
        return DictationCleanupResult(cleanedText: finishedText, durationMs: answer.durationMs, isFirstCall: answer.isFirstCall,
                                      prewarmed: answer.prewarmed)
    }

    /// The model pointer on the light text: the words it names are checked and replaced by the
    /// code, then the text is finished. Nil when there is nothing to send.
    private func point(_ decision: DictationGateDecision, cue: Range<Int>, instruction: String) async throws -> DictationCleanupResult? {
        guard let marked = DictationGate.markedText(decision.text, cue: cue),
              let answer = try await cleaner.point(marked, instructions: instruction) else {
            return nil
        }
        let outcome = DictationGate.applyPointer(answer.replaced, to: decision.text, cue: cue)
        lastPointer = answer.replaced
        lastPointerValid = outcome.isValid
        let finishedText = DictationGate.finished(outcome.text, settings: runSettings)
        return DictationCleanupResult(cleanedText: finishedText, durationMs: answer.durationMs, isFirstCall: answer.isFirstCall,
                                      prewarmed: answer.prewarmed, pointer: answer.replaced, pointerValid: outcome.isValid)
    }

    // MARK: Fixed phrases

    func runPhrase(_ phrase: DictationTestPhrase) {
        guard !isBusy, status.isAvailable else {
            return
        }
        rawText = phrase.text
        cleanedText = ""
        lastTimings = nil
        lastPhraseCleanupMs = nil
        errorMessage = nil
        Task { @MainActor in
            await cleanPhrase(phrase)
        }
    }

    private func cleanPhrase(_ phrase: DictationTestPhrase) async {
        isCleaning = true
        defer {
            isCleaning = false
        }
        let gate = runGate(phrase.text)
        do {
            guard let result = try await finish(gate) else {
                return
            }
            cleanedText = result.cleanedText
            lastPhraseCleanupMs = result.durationMs
            record(result, path: gate.decision.path)
            report(DictationTestRuns.phrase(phrase.text, result: result, source: .phrase, status: status, at: Date(), gate: gate,
                                            expect: phrase.expect, thermal: .current()))
        } catch {
            errorMessage = "Cleanup Failed: \(error)"
        }
    }

    func runAll() {
        guard !isBusy, status.isAvailable else {
            return
        }
        runAllSummaries = []
        runAllPaths = [:]
        pathCheck = DictationPathCheck()
        // The Sidekick's phrases and repeat count as they are now: a change on the page needs no
        // rebuild
        let currentSettings = settings()
        phrases = currentSettings.phrases
        repeatCount = currentSettings.repeatCount
        errorMessage = nil
        runAllProgress = "Starting"
        Task { @MainActor in
            await runEveryPhrase()
        }
    }

    private func runEveryPhrase() async {
        defer {
            runAllProgress = nil
        }
        let runPhrases = phrases
        let repeats = repeatCount
        for (phraseIndex, phrase) in runPhrases.enumerated() {
            var durations: [Int] = []
            for run in 1...repeats {
                runAllProgress = "Phrase \(phraseIndex + 1) of \(runPhrases.count), run \(run) of \(repeats)"
                let gate = runGate(phrase.text)
                runAllPaths[phrase.text] = gate.decision.path
                pathCheck.add(phrase: phrase.text, expected: phrase.expect, actual: gate.decision.path)
                do {
                    guard let result = try await finish(gate) else {
                        continue
                    }
                    durations.append(result.durationMs)
                    rawText = phrase.text
                    cleanedText = result.cleanedText
                    record(result, path: gate.decision.path)
                    report(DictationTestRuns.phrase(phrase.text, result: result, source: .runAll, status: status, at: Date(), gate: gate,
                                                    expect: phrase.expect, thermal: .current()))
                } catch {
                    errorMessage = "Cleanup Failed: \(error)"
                    return
                }
            }
            if let summary = DictationRunSummary.make(phrase: phrase.text, durationsMs: durations) {
                runAllSummaries.append(summary)
            }
        }
    }

    private func report(_ run: DictationRun) {
        onRun?(run)
    }

    /// Keeps the first call apart from warm ones; skip and rule make no model call.
    private func record(_ result: DictationCleanupResult, path: DictationPath) {
        guard path == .light || path == .rewrite else {
            return
        }
        if result.isFirstCall {
            firstCallMs = result.durationMs
        } else {
            lastWarmCallMs = result.durationMs
        }
    }
}

/// The screen: TEST BUILD label, model status, hold to talk, raw and cleaned side by side,
/// timings, the five phrases and Run all.
@available(iOS 26, *)
struct DictationTestView: View {
    @State private var model: DictationTestModel
    /// Why the last run was not saved to the Dictation Sidekick; nil when it was.
    private let saveError: @MainActor () -> String?

    init(onRun: (@MainActor (DictationRun) -> Void)? = nil, saveError: @escaping @MainActor () -> String? = DictationTestView.noSaveError,
         settings: @escaping @MainActor () -> DictationGateSettings = DictationTestModel.builtInSettings) {
        _model = State(initialValue: DictationTestModel(onRun: onRun, settings: settings))
        self.saveError = saveError
    }

    static func noSaveError() -> String? {
        nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusRow
                holdToTalkButton
                textColumns
                gateSection
                timingsSection
                phrasesSection
                runAllSection
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let saveFailure = saveError() {
                    Text("Not Saved: \(saveFailure)")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .navigationTitle("Dictation Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: model.appeared)
    }

    private var header: some View {
        HStack {
            Text("Dictation Test")
                .font(.title2.weight(.semibold))
            Spacer()
            Text("TEST BUILD")
                .font(.caption.weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.orange, in: Capsule())
                .foregroundStyle(.black)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.status.isAvailable ? Color.green : Color.red)
                .frame(width: 10, height: 10)
            Text("Model: \(model.status.label)")
                .font(.subheadline)
        }
    }

    private var holdToTalkButton: some View {
        let pressGesture = DragGesture(minimumDistance: 0)
            .onChanged(pressChanged)
            .onEnded(pressFinished)
        return Text(holdLabel)
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(model.isListening ? Color.red.opacity(0.85) : Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            .foregroundStyle(.white)
            .gesture(pressGesture)
            .opacity(model.isCleaning || model.runAllProgress != nil ? 0.5 : 1)
    }

    private var holdLabel: String {
        if model.isListening {
            return "Listening…"
        }
        if model.isCleaning {
            return "Cleaning…"
        }
        return "Hold to Talk"
    }

    private func pressChanged(_ value: DragGesture.Value) {
        model.pressBegan()
    }

    private func pressFinished(_ value: DragGesture.Value) {
        model.pressEnded()
    }

    private var textColumns: some View {
        HStack(alignment: .top, spacing: 8) {
            textBox(title: "Raw", text: model.rawText)
            textBox(title: "Cleaned", text: model.cleanedText)
        }
    }

    private func textBox(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text.isEmpty ? " " : text)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var gateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Path")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let gate = model.lastGate {
                HStack {
                    Text(DictationTestView.pathLabel(gate.decision))
                    Spacer()
                    Text(String(format: "Gate %.2f ms", gate.gateMs))
                }
                if !gate.decision.matched.isEmpty {
                    Text(gate.decision.matched.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                if let pointerValid = model.lastPointerValid {
                    Text(DictationTestView.pointerLabel(model.lastPointer ?? "", isValid: pointerValid))
                        .foregroundStyle(pointerValid ? Color.secondary : Color.red)
                }
            } else {
                Text("–")
            }
        }
        .font(.subheadline.monospacedDigit())
    }

    /// "Pointer: and Jonas", "Pointer: None", "Pointer Invalid: Jonas" (round 4).
    static func pointerLabel(_ pointer: String, isValid: Bool) -> String {
        let words = pointer.isEmpty ? "None" : pointer
        return (isValid ? "Pointer: " : "Pointer Invalid: ") + words
    }

    /// "Skip", "Light", "Rewrite: email".
    static func pathLabel(_ decision: DictationGateDecision) -> String {
        let name = decision.path.rawValue.capitalized
        guard let trigger = decision.trigger else {
            return name
        }
        return name + ": " + trigger
    }

    private var timingsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Timings")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let timings = model.lastTimings {
                timingRow("Release → raw text", timings.releaseToRawMs)
                timingRow("Cleanup", timings.cleanupMs)
                timingRow("Total", timings.totalMs)
            }
            if let phraseMs = model.lastPhraseCleanupMs {
                timingRow("Phrase cleanup", phraseMs)
            }
            timingRow("First call", model.firstCallMs)
            timingRow("Last warm call", model.lastWarmCallMs)
        }
        .font(.subheadline.monospacedDigit())
    }

    private func timingRow(_ label: String, _ milliseconds: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(milliseconds.map(Self.formatMilliseconds) ?? "–")
        }
    }

    private static func formatMilliseconds(_ milliseconds: Int) -> String {
        "\(milliseconds) ms"
    }

    private var phrasesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Phrases, Cleanup Only")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Array(model.phrases.enumerated()), id: \.offset, content: phraseButton)
        }
    }

    private func phraseButton(_ item: (offset: Int, element: DictationTestPhrase)) -> some View {
        let phrase = item.element
        return Button(action: phraseAction(phrase)) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(phrase.text)
                    .font(.footnote)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(phrase.expect.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy || !model.status.isAvailable)
    }

    private func phraseAction(_ phrase: DictationTestPhrase) -> () -> Void {
        let runPhrase = model.runPhrase
        return {
            runPhrase(phrase)
        }
    }

    private var runAllSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Run All ×\(model.repeatCount)", action: model.runAll)
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !model.status.isAvailable)
            if let progress = model.runAllProgress {
                Text(progress)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if model.pathCheck.checked > 0 {
                Text(model.pathCheck.label)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(model.pathCheck.wrong > 0 ? Color.red : Color.secondary)
            }
            ForEach(Array(model.runAllSummaries.enumerated()), id: \.offset, content: summaryRow)
        }
    }

    private func summaryRow(_ item: (offset: Int, element: DictationRunSummary)) -> some View {
        let summary = item.element
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(item.offset + 1). \(summary.phrase)")
                .font(.footnote)
                .lineLimit(1)
            Text("\(runAllPathName(summary.phrase))avg \(summary.averageMs) ms · worst \(summary.worstMs) ms · \(summary.runCount) runs")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

@available(iOS 26, *)
extension DictationTestView {
    /// "Light · " before a Run All row; empty when the phrase did not run.
    fileprivate func runAllPathName(_ phrase: String) -> String {
        guard let path = model.runAllPaths[phrase] else {
            return ""
        }
        guard let expected = model.pathCheck.wrongPhrases[phrase] else {
            return path.rawValue.capitalized + " · "
        }
        return path.rawValue.capitalized + " (expected " + expected.rawValue.capitalized + ") · "
    }
}

/// Why a run could not go on.
enum DictationGateError: Error, CustomStringConvertible {
    case modelNotAvailable(String)

    var description: String {
        switch self {
        case .modelNotAvailable(let reason):
            return reason
        }
    }
}

/// Shown on iOS 17 to 25, where Foundation Models does not exist.
struct DictationTestUnavailableView: View {
    var body: some View {
        ContentUnavailableView("Dictation Test", systemImage: "waveform", description: Text("TEST BUILD. Needs iOS 26 with Apple Intelligence."))
    }
}

/// The screen on iOS 26, the unavailable note before it.
struct DictationTestEntry: View {
    var onRun: (@MainActor (DictationRun) -> Void)?
    var saveError: @MainActor () -> String? = DictationTestEntry.noSaveError
    /// The gate's settings, read before every run.
    var settings: @MainActor () -> DictationGateSettings = DictationTestEntry.builtInSettings

    static func noSaveError() -> String? {
        nil
    }

    static func builtInSettings() -> DictationGateSettings {
        .builtIn
    }

    var body: some View {
        if #available(iOS 26, *) {
            DictationTestView(onRun: onRun, saveError: saveError, settings: settings)
        } else {
            DictationTestUnavailableView()
        }
    }
}
/// The quiet way in on the home screen: a long press on the top bar ("Midas"). Simultaneous, so
/// the bar's own buttons keep working.
struct DictationTestLongPress: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        let longPress = LongPressGesture(minimumDuration: 0.8)
            .onEnded(pressed)
        return content.simultaneousGesture(longPress)
    }

    private func pressed(_ finished: Bool) {
        action()
    }
}

extension View {
    func dictationTestLongPress(perform action: @escaping () -> Void) -> some View {
        modifier(DictationTestLongPress(action: action))
    }
}
#endif
