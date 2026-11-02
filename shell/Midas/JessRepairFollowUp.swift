import Foundation

// A plain repair jess sent (not a grow) waits on its Workdesk card (founder default, 2026-10-22):
// the card stays grey until the repair's done notice arrives (GET /repairs/notices, matched by
// reportId), then turns green and moves to the top. There is no re-run for a plain repair.

/// One unseen repair result from GET /repairs/notices. `kind`, `summary` and `clientReportId`
/// come from servers since 2026-10-23 (migration 0010); an older server sends none of them, and
/// its every notice is a fixed one.
struct JessRepairNotice: Decodable, Equatable, Sendable {
    let id: String
    let reportId: String
    let text: String
    var kind: RepairResultKind?
    var summary: String?
    var clientReportId: String?

    /// What the repair came to; an older server only ever sent fixed ones.
    var resultKind: RepairResultKind {
        kind ?? .fixed
    }
}

/// GET /repairs/notices and POST /repairs/notices/:id/seen.
protocol JessRepairNoticesAPI: Sendable {
    /// Nil when the server could not be asked (signed out, offline).
    func notices() async -> [JessRepairNotice]?
    func markSeen(id: String) async
}

private struct JessRepairNoticeList: Decodable {
    let notices: [JessRepairNotice]
}

private struct JessRepairEmptyBody: Encodable {}

/// The repair notices with the user's session.
struct RemoteJessRepairNotices: JessRepairNoticesAPI {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func notices() async -> [JessRepairNotice]? {
        guard let token = sessionToken() else {
            return nil
        }
        var request = URLRequest(url: platformOrigin.appending(path: "repairs/notices"))
        request.timeoutInterval = RemoteJessRouter.requestTimeout
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request) else {
            return nil
        }
        return Self.notices(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }

    /// Best effort: a lost mark only finds the same notice, already settled, next time.
    func markSeen(id: String) async {
        guard let token = sessionToken(), let urlRequest = try? RemoteJessRouter.urlRequest(platformOrigin: platformOrigin, path: "repairs/notices/\(id)/seen", body: JessRepairEmptyBody(), token: token) else {
            return
        }
        _ = try? await session.data(for: urlRequest)
    }

    static func notices(statusCode: Int, data: Data) -> [JessRepairNotice]? {
        guard statusCode == 200, let list = try? JSONDecoder().decode(JessRepairNoticeList.self, from: data) else {
            return nil
        }
        return list.notices
    }
}

/// After each sync: every notice for a repair a Workdesk card waits on settles that card and is
/// marked seen. Notices for other repairs are left alone.
@MainActor
final class JessRepairFollowUp {
    private let api: JessRepairNoticesAPI
    private let results: JessResults
    private var isChecking = false

    init(api: JessRepairNoticesAPI, results: JessResults) {
        self.api = api
        self.results = results
    }

    func check() async {
        // Nothing waits: the server is not asked
        let editReportIds = results.editReportIds
        guard !isChecking, !editReportIds.isEmpty else {
            return
        }
        isChecking = true
        defer {
            isChecking = false
        }
        guard let notices = await api.notices() else {
            return
        }
        // A repair jess sent that could not be made leaves its card waiting, saying Taking a Deeper
        // Look while the founder makes it by hand (founder, 2026-11-01); his fix arrives later as
        // a fixed notice and settles it. The could-not notice is left unseen, as before. A grow card
        // (jess grew the Sidekick) says the same; its fixed notice settles nothing here: the backend
        // re-runs the request on the fix and JessGrowFollowUp settles the card (founder, 2026-11-02).
        for notice in notices where editReportIds.contains(notice.reportId) && notice.resultKind == .couldntFix {
            _ = results.markDeeperLook(reportId: notice.reportId)
        }
        for notice in notices where results.waitingReportIds.contains(notice.reportId) && notice.resultKind != .couldntFix {
            if results.settleRepair(reportId: notice.reportId, text: notice.text) {
                await api.markSeen(id: notice.id)
            }
        }
    }
}
