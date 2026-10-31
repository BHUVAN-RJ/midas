import Foundation

/// The server side of Settings (founder, 2026-10-31; docs/briefs/build-22-2026-10-31.md):
/// DELETE /sidekicks/:id, POST /account/sign-out, POST /account/delete-request.
protocol AccountAPI: Sendable {
    func removeSidekick(id sidekickId: String) async throws
    func signOut() async throws
    func requestAccountDeletion() async throws
}

enum AccountAPIError: Error, Equatable {
    case notSignedIn
    /// The server no longer lists this Sidekick for the person (deleted on another phone).
    case noSuchSidekick
    case badResponse
    case server(status: Int)
}

struct RemoteAccountAPI: AccountAPI {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    func removeSidekick(id sidekickId: String) async throws {
        let request = try Self.removeSidekickRequest(platformOrigin: platformOrigin, sidekickId: sidekickId, token: sessionToken())
        try await send(request)
    }

    func signOut() async throws {
        let request = try Self.accountRequest(platformOrigin: platformOrigin, path: "account/sign-out", token: sessionToken())
        try await send(request)
    }

    func requestAccountDeletion() async throws {
        let request = try Self.accountRequest(platformOrigin: platformOrigin, path: "account/delete-request", token: sessionToken())
        try await send(request)
    }

    static func removeSidekickRequest(platformOrigin: URL, sidekickId: String, token: String?) throws -> URLRequest {
        guard let token else {
            throw AccountAPIError.notSignedIn
        }
        let url = platformOrigin.appending(path: "sidekicks").appending(path: sidekickId)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func accountRequest(platformOrigin: URL, path: String, token: String?) throws -> URLRequest {
        guard let token else {
            throw AccountAPIError.notSignedIn
        }
        var request = URLRequest(url: platformOrigin.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// 2xx is done; 404 on a Sidekick means it is already gone; 401 means signed out.
    static func check(status: Int) throws {
        if (200..<300).contains(status) {
            return
        }
        if status == 401 {
            throw AccountAPIError.notSignedIn
        }
        if status == 404 {
            throw AccountAPIError.noSuchSidekick
        }
        throw AccountAPIError.server(status: status)
    }

    private func send(_ request: URLRequest) async throws {
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountAPIError.badResponse
        }
        try Self.check(status: httpResponse.statusCode)
    }
}
