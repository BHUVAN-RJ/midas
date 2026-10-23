import Foundation

// A plain repair jess sent (not a grow) waits on its Workdesk card (founder default, 2026-10-22):
// the card stays grey until the repair's done notice arrives (GET /repairs/notices, matched by
// reportId), then turns green and moves to the top. There is no re-run for a plain repair.

/// One unseen "done" notice from GET /repairs/notices.
struct JessRepairNotice: Decodable, Equatable, Sendable {
    let id: String
    let reportId: String
    let text: String
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
        guard !isChecking, !results.waitingReportIds.isEmpty else {
            return
        }
        isChecking = true
        defer {
            isChecking = false
        }
        guard let notices = await api.notices() else {
            return
        }
        for notice in notices where results.waitingReportIds.contains(notice.reportId) {
            if results.settleRepair(reportId: notice.reportId, text: notice.text) {
                await api.markSeen(id: notice.id)
            }
        }
    }
}
