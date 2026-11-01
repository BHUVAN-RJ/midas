import Foundation

/// One Sidekick the router can offer: listed with an agent block (it has tools) and a version.
struct JessSidekickSource: Equatable, Sendable {
    let id: String
    let name: String
    let version: String
    let agent: JSONValue
}

/// The repair a request waits for (founder, 2026-10-22): its feature request or repair report, and
/// for a grow the pending request the backend runs again once the repair is live.
struct JessRepairLink: Codable, Equatable, Sendable {
    let reportId: String?
    let pendingId: String?
}

/// What jess did with one sentence (jess router, founder 2026-10-21). `done` carries the
/// Sidekick handler's own line ("Added Bananas", "Marked done: Call Mom") and the time it set;
/// `sentToRepair` was queued for the repair agent (with the link the Workdesk card waits on);
/// `notDone` changed nothing and keeps what was said for the home page card; `cutOff` got no
/// answer (no network, timeout, server busy or the model unreachable) and stays queued to be sent
/// again (founder, 2026-10-22).
enum JessResult: Equatable, Sendable {
    case done(text: String, at: String?, allDay: Bool?, timeZone: String?)
    case sentToRepair(sidekickName: String, link: JessRepairLink? = nil)
    case notDone(transcript: String)
    case cutOff(transcript: String)
}

/// One request's route in the queue (JessResults): the id the server keeps its answer under, in,
/// and the name of the Sidekick jess chose, out. Carried as a task local so the route call's shape
/// stays the same for every caller.
@MainActor
final class JessRouteContext {
    @TaskLocal static var current: JessRouteContext?

    let requestId: String
    var sidekickName: String?
    /// The records the done tool changed, set just before `onApplied` (JessChangeLink).
    var changeLink: JessChangeLink?

    init(requestId: String) {
        self.requestId = requestId
    }
}

/// What the router needs from the rest of the shell; tests pass stand-ins.
struct JessRouterDependencies {
    var sidekicks: @MainActor () -> [JessSidekickSource]
    var engine: @MainActor (_ sidekickId: String, _ version: String) async throws -> SidekickToolsEngine
    var records: @MainActor (_ sidekickId: String) -> [LocalRecord]
    /// Writes a tool's ops through `RecordWriter.apply`; throws `RecordRefusal`.
    var apply: @MainActor (_ sidekickId: String, _ ops: [SidekickToolOp]) throws -> Void
    var api: JessRouting
    var now: @MainActor () -> Date
    var timeZone: @MainActor () -> TimeZone
    var app: @MainActor () -> VoiceParseApp
    /// The directory again, and the version it now lists for a Sidekick: RecordWriter stamps each
    /// op with that version and the server checks the op against its schemas, so a newer version's
    /// tools run only once the directory lists it. Nil: not checked (tests that do not need it).
    var refreshDirectory: (@MainActor () async -> Void)? = nil
    var directoryVersion: (@MainActor (_ sidekickId: String) -> String?)? = nil
}

/// The tool call the server chose, ready to run on the phone.
private struct JessToolCall {
    let verb: String
    let input: JSONValue
    let sidekickId: String
    let logId: String?
    let transcript: String
}

/// One sentence to one Sidekick tool: the phone offers every Sidekick with tools (its id and a
/// summary of its records; the server reads the tools from the manifest), the server picks and
/// checks one call, the phone runs that
/// Sidekick's handler in JavaScriptCore with the records it holds and writes the result through
/// `RecordWriter`. Anything that cannot act changes nothing.
@MainActor
final class JessRouter {
    private let dependencies: JessRouterDependencies

    init(dependencies: JessRouterDependencies) {
        self.dependencies = dependencies
    }

    func route(transcript: String, listenMs: Int) async -> JessResult {
        await route(transcript: transcript, listenMs: listenMs, saidAt: nil, timeZone: nil, onApplied: nil)
    }

    /// `saidAt` and `timeZone`: when and where it was said, for a request finished later than it
    /// was spoken (jess in the background, founder 2026-10-22); nil means now and here.
    /// `onApplied` runs right after the ops are written, before anything else is awaited, so the
    /// caller can record that this request is applied and never run it again.
    func route(transcript: String, listenMs: Int, saidAt: Date?, timeZone: TimeZone?, onApplied: (@MainActor (JessResult) -> Void)?) async -> JessResult {
        let notDone = JessResult.notDone(transcript: transcript)
        let now = saidAt ?? dependencies.now()
        let zone = timeZone ?? dependencies.timeZone()
        var offered: [String: (source: JessSidekickSource, engine: SidekickToolsEngine)] = [:]
        var payloads: [JessSidekickPayload] = []
        for source in dependencies.sidekicks() {
            // A Sidekick whose tools cannot be loaded is left out; the others still work
            guard let engine = try? await dependencies.engine(source.id, source.version),
                  let context = try? engine.context(records: dependencies.records(source.id), now: now) else {
                continue
            }
            offered[source.id] = (source, engine)
            payloads.append(JessSidekickPayload(id: source.id, context: context))
        }
        if payloads.isEmpty {
            return notDone
        }
        let request = JessRouteRequest(
            transcript: transcript,
            now: ReminderRecord.formatDate(now),
            timeZone: zone.identifier,
            locale: Locale.current.identifier(.bcp47),
            sidekicks: payloads,
            app: dependencies.app(),
            listenMs: listenMs,
            requestId: JessRouteContext.current?.requestId
        )
        switch await dependencies.api.route(request) {
        case .done(let sidekickId, let version, let tool, let input, let logId):
            guard let chosen = offered[sidekickId], let verb = Self.verb(of: tool, sidekickId: sidekickId) else {
                await report(logId: logId, outcome: .failed(reason: "unknown-tool"))
                return notDone
            }
            // The server checked the call against the manifest of the version the user gets now;
            // run that version's tools.js, which the phone may not have loaded yet
            var engine = chosen.engine
            if let version, version != chosen.source.version {
                if let refreshDirectory = dependencies.refreshDirectory {
                    await refreshDirectory()
                }
                if let directoryVersion = dependencies.directoryVersion, directoryVersion(sidekickId) != version {
                    await report(logId: logId, outcome: .failed(reason: "version-changed"))
                    return notDone
                }
                guard let current = try? await dependencies.engine(sidekickId, version) else {
                    await report(logId: logId, outcome: .failed(reason: "version-changed"))
                    return notDone
                }
                engine = current
            }
            JessRouteContext.current?.sidekickName = chosen.source.name
            let call = JessToolCall(verb: verb, input: input, sidekickId: sidekickId, logId: logId, transcript: transcript)
            return await run(call, engine: engine, now: now, timeZone: zone, onApplied: onApplied)
        case .repair(let sidekickId, _, let reportId):
            let name = offered[sidekickId]?.source.name ?? sidekickId
            JessRouteContext.current?.sidekickName = name
            return .sentToRepair(sidekickName: name, link: Self.link(reportId: reportId, pendingId: nil))
        case .grow(let sidekickId, _, let reportId, let pendingId):
            let name = offered[sidekickId]?.source.name ?? sidekickId
            JessRouteContext.current?.sidekickName = name
            return .sentToRepair(sidekickName: name, link: Self.link(reportId: reportId, pendingId: pendingId))
        case .notDone(let reason):
            // The server leaves a request whose model could not be reached open to run again
            if reason == Self.modelUnreachableReason {
                return .cutOff(transcript: transcript)
            }
            return notDone
        case .unreachable:
            return .cutOff(transcript: transcript)
        }
    }

    /// The server's not-done reason when the model could not be reached (jess-route.ts).
    static let modelUnreachableReason = "model-error"

    /// Nil when the server named neither (an older server).
    static func link(reportId: String?, pendingId: String?) -> JessRepairLink? {
        if reportId == nil && pendingId == nil {
            return nil
        }
        return JessRepairLink(reportId: reportId, pendingId: pendingId)
    }

    /// "reminders.add" -> "add", only for the Sidekick named.
    static func verb(of tool: String, sidekickId: String) -> String? {
        let prefix = sidekickId + "."
        guard tool.hasPrefix(prefix), tool.count > prefix.count else {
            return nil
        }
        return String(tool.dropFirst(prefix.count))
    }

    private func run(_ call: JessToolCall, engine: SidekickToolsEngine, now: Date, timeZone: TimeZone, onApplied: (@MainActor (JessResult) -> Void)?) async -> JessResult {
        let sidekickId = call.sidekickId
        let logId = call.logId
        let transcript = call.transcript
        // Read the records again: they may have changed while the server answered
        let records = dependencies.records(sidekickId)
        let result: SidekickToolResult
        do {
            result = try engine.run(verb: call.verb, input: call.input, records: records, now: now)
        } catch {
            await report(logId: logId, outcome: .failed(reason: Self.reason(for: error)))
            return .notDone(transcript: transcript)
        }
        switch result.outcome {
        case .refused(let reason):
            await report(logId: logId, outcome: .refused(reason: reason))
            return .notDone(transcript: transcript)
        case .changes(let ops):
            // Which records were new, edited or deleted, from the records the tool ran on
            let changeLink = JessChangeLink.make(sidekickId: sidekickId, ops: ops, recordsBefore: records)
            do {
                try dependencies.apply(sidekickId, ops)
            } catch {
                await report(logId: logId, outcome: .failed(reason: Self.reason(for: error)))
                return .notDone(transcript: transcript)
            }
            let done = JessResult.done(text: result.text, at: result.at, allDay: result.allDay, timeZone: timeZone.identifier)
            JessRouteContext.current?.changeLink = changeLink
            onApplied?(done)
            await report(logId: logId, outcome: .applied)
            return done
        }
    }

    private func report(logId: String?, outcome: JessPhoneOutcome) async {
        guard let logId else {
            return
        }
        await dependencies.api.reportOutcome(logId: logId, outcome: outcome)
    }

    private static func reason(for error: Error) -> String {
        if let refusal = error as? RecordRefusal {
            return "write-refused: " + refusal.reason
        }
        if let toolsError = error as? SidekickToolsError {
            return "tools: \(toolsError)"
        }
        return "error"
    }
}
