import Foundation

/// One Sidekick the router can offer: listed with an agent block (it has tools) and a version.
struct JessSidekickSource: Equatable, Sendable {
    let id: String
    let name: String
    let version: String
    let agent: JSONValue
}

/// What jess did with one sentence (jess router, founder 2026-10-21). `done` carries the
/// Sidekick handler's own line ("Added Bananas", "Marked done: Call Mom") and the time it set;
/// `sentToRepair` was queued for the repair agent; `notDone` changed nothing and keeps what was
/// said for the home page card.
enum JessResult: Equatable, Sendable {
    case done(text: String, at: String?, allDay: Bool?, timeZone: String?)
    case sentToRepair(sidekickName: String)
    case notDone(transcript: String)
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
        let notDone = JessResult.notDone(transcript: transcript)
        let now = dependencies.now()
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
            timeZone: dependencies.timeZone().identifier,
            locale: Locale.current.identifier(.bcp47),
            sidekicks: payloads,
            app: dependencies.app(),
            listenMs: listenMs
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
                guard let current = try? await dependencies.engine(sidekickId, version) else {
                    await report(logId: logId, outcome: .failed(reason: "version-changed"))
                    return notDone
                }
                engine = current
            }
            return await run(verb: verb, input: input, sidekickId: sidekickId, engine: engine, logId: logId, transcript: transcript)
        case .repair(let sidekickId, _):
            let name = offered[sidekickId]?.source.name ?? sidekickId
            return .sentToRepair(sidekickName: name)
        case .notDone, .unreachable:
            return notDone
        }
    }

    /// "reminders.add" -> "add", only for the Sidekick named.
    static func verb(of tool: String, sidekickId: String) -> String? {
        let prefix = sidekickId + "."
        guard tool.hasPrefix(prefix), tool.count > prefix.count else {
            return nil
        }
        return String(tool.dropFirst(prefix.count))
    }

    private func run(verb: String, input: JSONValue, sidekickId: String, engine: SidekickToolsEngine, logId: String?, transcript: String) async -> JessResult {
        // Read the records again: they may have changed while the server answered
        let records = dependencies.records(sidekickId)
        let result: SidekickToolResult
        do {
            result = try engine.run(verb: verb, input: input, records: records, now: dependencies.now())
        } catch {
            await report(logId: logId, outcome: .failed(reason: Self.reason(for: error)))
            return .notDone(transcript: transcript)
        }
        switch result.outcome {
        case .refused(let reason):
            await report(logId: logId, outcome: .refused(reason: reason))
            return .notDone(transcript: transcript)
        case .changes(let ops):
            do {
                try dependencies.apply(sidekickId, ops)
            } catch {
                await report(logId: logId, outcome: .failed(reason: Self.reason(for: error)))
                return .notDone(transcript: transcript)
            }
            await report(logId: logId, outcome: .applied)
            return .done(text: result.text, at: result.at, allDay: result.allDay, timeZone: dependencies.timeZone().identifier)
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
