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

    private let transcriber = OnDeviceSpeechTranscriber(options: .longDictation)
    private let cleaner = DictationCleaner()
    private var isHolding = false
    private var releasedAt: Date?

    var isBusy: Bool {
        isListening || isCleaning || runAllProgress != nil
    }

    /// Screen opened: read the model status and load the model, so the first call is timed apart.
    func appeared() {
        status = .current()
        if status.isAvailable {
            cleaner.prewarm()
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
        guard status.isAvailable else {
            return
        }
        isCleaning = true
        defer {
            isCleaning = false
        }
        let cleanupStartedAt = Date()
        do {
            guard let result = try await cleaner.clean(rawText) else {
                return
            }
            let cleanedAt = Date()
            cleanedText = result.cleanedText
            lastTimings = DictationTimings(releasedAt: releasedAt, rawFinalAt: rawFinalAt, cleanupStartedAt: cleanupStartedAt, cleanedAt: cleanedAt)
            record(result)
        } catch {
            errorMessage = "Cleanup Failed: \(error)"
        }
    }

    // MARK: Fixed phrases

    func runPhrase(_ phrase: String) {
        guard !isBusy, status.isAvailable else {
            return
        }
        rawText = phrase
        cleanedText = ""
        lastTimings = nil
        lastPhraseCleanupMs = nil
        errorMessage = nil
        Task { @MainActor in
            await cleanPhrase(phrase)
        }
    }

    private func cleanPhrase(_ phrase: String) async {
        isCleaning = true
        defer {
            isCleaning = false
        }
        do {
            guard let result = try await cleaner.clean(phrase) else {
                return
            }
            cleanedText = result.cleanedText
            lastPhraseCleanupMs = result.durationMs
            record(result)
        } catch {
            errorMessage = "Cleanup Failed: \(error)"
        }
    }

    func runAll() {
        guard !isBusy, status.isAvailable else {
            return
        }
        runAllSummaries = []
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
        let phrases = DictationTestPhrases.all
        let repeats = DictationTestPhrases.runAllRepeats
        for (phraseIndex, phrase) in phrases.enumerated() {
            var durations: [Int] = []
            for run in 1...repeats {
                runAllProgress = "Phrase \(phraseIndex + 1) of \(phrases.count), run \(run) of \(repeats)"
                do {
                    guard let result = try await cleaner.clean(phrase) else {
                        continue
                    }
                    durations.append(result.durationMs)
                    rawText = phrase
                    cleanedText = result.cleanedText
                    record(result)
                } catch {
                    errorMessage = "Cleanup Failed: \(error)"
                    return
                }
            }
            if let summary = DictationRunSummary.make(phrase: phrase, durationsMs: durations) {
                runAllSummaries.append(summary)
            }
        }
    }

    /// Keeps the first call apart from warm ones.
    private func record(_ result: DictationCleanupResult) {
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
    @State private var model = DictationTestModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                statusRow
                holdToTalkButton
                textColumns
                timingsSection
                phrasesSection
                runAllSection
                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
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
            ForEach(DictationTestPhrases.all, id: \.self, content: phraseButton)
        }
    }

    private func phraseButton(_ phrase: String) -> some View {
        Button(action: phraseAction(phrase)) {
            Text(phrase)
                .font(.footnote)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .disabled(model.isBusy || !model.status.isAvailable)
    }

    private func phraseAction(_ phrase: String) -> () -> Void {
        let runPhrase = model.runPhrase
        return {
            runPhrase(phrase)
        }
    }

    private var runAllSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Run All ×\(DictationTestPhrases.runAllRepeats)", action: model.runAll)
                .buttonStyle(.borderedProminent)
                .disabled(model.isBusy || !model.status.isAvailable)
            if let progress = model.runAllProgress {
                Text(progress)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
            Text("avg \(summary.averageMs) ms · worst \(summary.worstMs) ms · \(summary.runCount) runs")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
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
    var body: some View {
        if #available(iOS 26, *) {
            DictationTestView()
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
