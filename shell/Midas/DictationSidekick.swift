#if MIDAS_TEST_BUILD
// Dictation Sidekick wiring (TEST BUILD, founder 2026-11-13; branch agent/dictation-test, never
// merged; docs/briefs/dictation-sidekick-test.md). Compiled only in the Test configuration.
//
//   Sidekick page writes  request:<id>  { kind: "test.dictation", status: "pending" }
//   shell shows           the Dictation Test screen; request:<id> { status: "open" }
//   each cleanup run      run:<time>-<n>  (dictation.run) and summary:main (dictation.summary)
//   screen closed         request:<id>  { status: "done", runs: <saved while open> }
//
// The long press on "Midas" opens the same screen with no request; its runs land in the
// `dictation` Sidekick too. Records go through the store's write gate (the manifest's types) and
// sync to the server like every other record.
import Foundation
import Observation
import UIKit

extension ShellRequests {
    static let dictationTestKind = "test.dictation"
}

/// One cleanup run, as the test screen measured it.
struct DictationRun: Equatable, Sendable {
    enum Source: String, Sendable {
        case phrase
        case spoken
        case runAll = "run-all"
    }

    let at: Date
    let source: Source
    let raw: String
    let cleaned: String
    let cleanupMs: Int
    /// Spoken runs only.
    let releaseToRawMs: Int?
    /// Spoken runs only.
    let totalMs: Int?
    let firstCall: Bool
    let modelStatus: String
}

/// A run from what the test screen measured.
enum DictationTestRuns {
    /// Hold to talk: the timings the screen shows (release → raw, cleanup, total).
    static func spoken(raw: String, result: DictationCleanupResult, timings: DictationTimings, status: DictationModelStatus, at: Date) -> DictationRun {
        DictationRun(at: at, source: .spoken, raw: raw, cleaned: result.cleanedText, cleanupMs: timings.cleanupMs, releaseToRawMs: timings.releaseToRawMs,
                     totalMs: timings.totalMs, firstCall: result.isFirstCall, modelStatus: status.label)
    }

    /// A fixed phrase, tapped alone or in Run All: cleanup only.
    static func phrase(_ phrase: String, result: DictationCleanupResult, source: DictationRun.Source, status: DictationModelStatus, at: Date) -> DictationRun {
        DictationRun(at: at, source: source, raw: phrase, cleaned: result.cleanedText, cleanupMs: result.durationMs, releaseToRawMs: nil,
                     totalMs: nil, firstCall: result.isFirstCall, modelStatus: status.label)
    }
}

/// The phone and build a run was measured on.
struct DictationDeviceInfo: Equatable, Sendable {
    let device: String
    let ios: String
    let build: String

    /// "iPhone17,1" on a phone; the simulated model's identifier on a simulator.
    static func current() -> DictationDeviceInfo {
        let environment = ProcessInfo.processInfo.environment
        let simulatedModel = environment["SIMULATOR_MODEL_IDENTIFIER"]
        let device = simulatedModel.map(simulatorName) ?? machineIdentifier()
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return DictationDeviceInfo(device: device, ios: UIDevice.current.systemVersion, build: build)
    }

    private static func simulatorName(_ model: String) -> String {
        "Simulator " + model
    }

    private static func machineIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        var identifier = ""
        for child in machineMirror.children {
            guard let byte = child.value as? Int8, byte != 0 else {
                break
            }
            identifier.append(Character(UnicodeScalar(UInt8(byte))))
        }
        return identifier
    }
}

/// The Dictation Sidekick's records (its manifest.json `types`): one `run:` per cleanup and the
/// `summary:main` its widget reads.
enum DictationRunRecord {
    static let sidekickId = "dictation"
    static let keyPrefix = "run:"
    static let summaryKey = "summary:main"
    /// The manifest's maxLength for raw and cleaned text (a 10 minute dictation can be longer).
    static let maxTextCharacters = 4000

    /// "run:20261113T213045123Z-0007": sorts by time; the counter keeps two runs in one
    /// millisecond apart.
    static func key(at date: Date, counter: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd'T'HHmmssSSS'Z'"
        let counterText = String(format: "%04d", counter % 10_000)
        return keyPrefix + formatter.string(from: date) + "-" + counterText
    }

    /// "2026-11-13T21:30:45.123Z"
    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func shortened(_ text: String) -> String {
        String(text.prefix(maxTextCharacters))
    }

    static func value(_ run: DictationRun, device: DictationDeviceInfo) -> JSONValue {
        var fields: [String: JSONValue] = [
            "at": .string(timestamp(run.at)),
            "source": .string(run.source.rawValue),
            "raw": .string(shortened(run.raw)),
            "cleaned": .string(shortened(run.cleaned)),
            "cleanupMs": .number(Double(run.cleanupMs)),
            "firstCall": .bool(run.firstCall),
            "modelStatus": .string(String(run.modelStatus.prefix(120))),
            "device": .string(String(device.device.prefix(60))),
            "ios": .string(String(device.ios.prefix(20))),
            "build": .string(String(device.build.prefix(20))),
        ]
        if let releaseToRawMs = run.releaseToRawMs {
            fields["releaseToRawMs"] = .number(Double(releaseToRawMs))
        }
        if let totalMs = run.totalMs {
            fields["totalMs"] = .number(Double(totalMs))
        }
        return .object(fields)
    }

    /// One stored run's time and cleanup ms; nil for a record that is not a run.
    private struct StoredRun {
        let key: String
        let at: Date
        let atText: String
        let cleanupMs: Int
    }

    private static func storedRun(_ record: LocalRecord) -> StoredRun? {
        guard record.key.hasPrefix(keyPrefix),
              let atText = record.value["at"]?.stringValue,
              let cleanupNumber = record.value["cleanupMs"]?.numberValue,
              cleanupNumber >= 0, cleanupNumber == cleanupNumber.rounded() else {
            return nil
        }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainParser = ISO8601DateFormatter()
        guard let at = parser.date(from: atText) ?? plainParser.date(from: atText) else {
            return nil
        }
        return StoredRun(key: record.key, at: at, atText: atText, cleanupMs: Int(cleanupNumber))
    }

    // Newest first: by time, then by key (as the page's DictationLogic.runsOf orders them)
    private static func isNewer(_ first: StoredRun, than second: StoredRun) -> Bool {
        if first.at != second.at {
            return first.at > second.at
        }
        return first.key > second.key
    }

    /// The summary over every run, with the same numbers as the page's DictationLogic.summaryOf:
    /// the count, the newest run's cleanup ms, the average rounded half up, the worst.
    static func summary(of records: [LocalRecord], updatedAt: Date) -> JSONValue {
        var runs: [StoredRun] = []
        for record in records {
            if let run = storedRun(record) {
                runs.append(run)
            }
        }
        runs.sort(by: isNewer)
        var fields: [String: JSONValue] = [
            "runs": .number(Double(runs.count)),
            "updatedAt": .string(timestamp(updatedAt)),
        ]
        guard let newest = runs.first else {
            return .object(fields)
        }
        var total = 0
        var worst = 0
        for run in runs {
            total += run.cleanupMs
            worst = max(worst, run.cleanupMs)
        }
        // Half up, as JavaScript's Math.round does for these positive numbers
        let average = Int((Double(total) / Double(runs.count) + 0.5).rounded(.down))
        fields["lastCleanupMs"] = .number(Double(newest.cleanupMs))
        fields["averageCleanupMs"] = .number(Double(average))
        fields["worstCleanupMs"] = .number(Double(worst))
        fields["lastAt"] = .string(newest.atText)
        return .object(fields)
    }
}

/// The test screen on screen: for a Sidekick's request, or from the long press (no request).
struct DictationTestSession: Identifiable, Equatable, Sendable {
    let sidekickId: String
    let requestKey: String?

    var id: String {
        sidekickId + "|" + (requestKey ?? "home")
    }
}

/// Opens the Dictation Test screen for a Sidekick's request and saves each run as its records.
@MainActor
@Observable
final class DictationTestCenter {
    /// The screen on screen; nil when none.
    var shownSession: DictationTestSession?
    /// Why the last run could not be saved; nil when it was.
    private(set) var lastSaveError: String?

    @ObservationIgnored private let store: LocalRecordStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let device: DictationDeviceInfo
    @ObservationIgnored private var savedRunCount = 0
    @ObservationIgnored private var keyCounter = 0

    init(store: LocalRecordStore, device: DictationDeviceInfo = .current(), now: @escaping @MainActor () -> Date = Date.init) {
        self.store = store
        self.device = device
        self.now = now
    }

    /// Called by the request dispatch after a Sidekick writes a `test.dictation` request.
    func handleRequestWritten(sidekickId: String, key: String, value: JSONValue) {
        guard value["status"]?.stringValue == "pending", value["kind"]?.stringValue == ShellRequests.dictationTestKind else {
            return
        }
        // One screen at a time: a second request while it is up is answered at once
        guard shownSession == nil else {
            finish(sidekickId: sidekickId, requestKey: key, status: "cancelled", extraFields: [:])
            return
        }
        savedRunCount = 0
        lastSaveError = nil
        shownSession = DictationTestSession(sidekickId: sidekickId, requestKey: key)
        finish(sidekickId: sidekickId, requestKey: key, status: "open", extraFields: [:])
    }

    /// The long press on "Midas": the same screen, runs saved to the Dictation Sidekick.
    func openFromHome() {
        guard shownSession == nil else {
            return
        }
        savedRunCount = 0
        lastSaveError = nil
        shownSession = DictationTestSession(sidekickId: DictationRunRecord.sidekickId, requestKey: nil)
    }

    /// One cleanup run: its record, then the summary the widget reads.
    func save(_ run: DictationRun) {
        let sidekickId = shownSession?.sidekickId ?? DictationRunRecord.sidekickId
        keyCounter += 1
        let key = DictationRunRecord.key(at: run.at, counter: keyCounter)
        do {
            try store.set(sidekickId: sidekickId, key: key, value: DictationRunRecord.value(run, device: device))
            let runs = store.query(sidekickId: sidekickId, keyPrefix: DictationRunRecord.keyPrefix)
            let summary = DictationRunRecord.summary(of: runs, updatedAt: now())
            try store.set(sidekickId: sidekickId, key: DictationRunRecord.summaryKey, value: summary)
            savedRunCount += 1
            lastSaveError = nil
        } catch {
            lastSaveError = String(describing: error)
        }
    }

    /// The screen closed (Done, or swiped away): the request is done, with the runs it saved.
    func dismiss() {
        guard let session = shownSession else {
            return
        }
        shownSession = nil
        if let requestKey = session.requestKey {
            finish(sidekickId: session.sidekickId, requestKey: requestKey, status: "done", extraFields: ["runs": .number(Double(savedRunCount))])
        }
    }

    /// Writes the outcome into the request record (a patch: what the Sidekick put in it stays).
    private func finish(sidekickId: String, requestKey: String, status: String, extraFields: [String: JSONValue]) {
        var patch: [String: JSONValue] = [
            "status": .string(status),
            "finishedAt": .string(ISO8601DateFormatter.deviceZone.string(from: now())),
        ]
        for (fieldName, fieldValue) in extraFields {
            patch[fieldName] = fieldValue
        }
        try? RecordWriter(store: store).update(sidekickId: sidekickId, key: requestKey, patch: .object(patch))
    }
}
#endif
