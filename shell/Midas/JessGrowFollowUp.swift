import Foundation

/// jess grows the Sidekick (founder, 2026-10-21): a request the Sidekick had no option for went to
/// the repair agent ("Sent to Repair"). Once that repair is live on the user's copy, the backend
/// runs the request again itself and appends its changes to the user's records; the phone gets
/// them through its normal pull. After each sync this shows what came of it, once: the handler's
/// line as the banner, or what was said as the Not Done card.
@MainActor
final class JessGrowFollowUp {
    private let api: JessPendingAPI
    private let present: @MainActor (JessResult) -> Void
    private var isChecking = false

    init(api: JessPendingAPI, present: @escaping @MainActor (JessResult) -> Void) {
        self.api = api
        self.present = present
    }

    func check() async {
        // Two foregrounds in a row would show the same result twice
        guard !isChecking else {
            return
        }
        isChecking = true
        defer {
            isChecking = false
        }
        guard let items = await api.pending() else {
            return
        }
        for item in items {
            present(Self.result(for: item))
            await api.markShown(id: item.id)
        }
    }

    static func result(for item: JessPendingItem) -> JessResult {
        if item.state == "done", let text = item.text, !text.isEmpty {
            return .done(text: text, at: nil, allDay: nil, timeZone: nil)
        }
        return .notDone(transcript: item.transcript)
    }
}
