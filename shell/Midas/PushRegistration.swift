import Foundation
import UIKit
import UserNotifications

// Push for Make (contract section 4 and 8): after sign-in Midas asks once for notifications,
// registers with APNs on every launch and hands the token to the server (`POST /push/register`).
// The server sends a push for a question card and for Built (to the person), and for each of a
// person's messages and answers (to the founder). Tapping one opens its thread.

/// Which APNs host the token belongs to: `aps-environment` in the app's embedded provisioning
/// profile (`development` is the sandbox; anything else, or no profile as on the App Store and
/// TestFlight, is production). Read from the profile, not from `#if DEBUG`, because a Release
/// build signed for development still gets sandbox tokens.
enum PushEnvironment {
    static let sandbox = "sandbox"
    static let production = "production"

    static func current(bundle: Bundle = .main) -> String {
        let profileURL = bundle.url(forResource: "embedded", withExtension: "mobileprovision")
        let profile = profileURL.flatMap(readProfile)
        return fromProvisioningProfile(profile)
    }

    private static func readProfile(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    /// The profile is a signed envelope around a property list; the list is found between its
    /// `<?xml` (or `<plist`) start and `</plist>` end and read for `Entitlements.aps-environment`.
    static func fromProvisioningProfile(_ profile: Data?) -> String {
        guard let profile, let plist = plistData(in: profile) else {
            return production
        }
        let parsed = try? PropertyListSerialization.propertyList(from: plist, format: nil)
        let entitlements = (parsed as? [String: Any])?["Entitlements"] as? [String: Any]
        let apsEnvironment = entitlements?["aps-environment"] as? String
        return apsEnvironment == "development" ? sandbox : production
    }

    private static func plistData(in profile: Data) -> Data? {
        let startMarkers = [Data("<?xml".utf8), Data("<plist".utf8)]
        let endMarker = Data("</plist>".utf8)
        var start: Range<Data.Index>?
        for marker in startMarkers {
            if let found = profile.range(of: marker) {
                start = found
                break
            }
        }
        guard let start, let end = profile.range(of: endMarker, in: start.lowerBound..<profile.endIndex) else {
            return nil
        }
        return profile.subdata(in: start.lowerBound..<end.upperBound)
    }

    /// The device token as the server takes it: lowercase hex.
    static func hex(_ token: Data) -> String {
        var text = ""
        for byte in token {
            text += String(format: "%02x", byte)
        }
        return text
    }
}

/// `POST /push/register` with the user's session.
struct PushRegisterAPI: Sendable {
    let platformOrigin: URL
    let session: URLSession
    let sessionToken: @Sendable () -> String?

    struct Body: Codable, Equatable {
        let token: String
        let env: String
        let bundleId: String
    }

    static func request(platformOrigin: URL, token: String?, body: Body) throws -> URLRequest {
        var request = URLRequest(url: platformOrigin.appending(path: "push/register"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Any answer, a 404 before the server has the route included, is let go: the next launch
    /// sends the token again.
    func register(_ body: Body) async {
        guard let sessionToken = sessionToken(), let request = try? Self.request(platformOrigin: platformOrigin, token: sessionToken, body: body) else {
            return
        }
        _ = try? await session.data(for: request)
    }
}

/// The notification permission and remote registration, behind a protocol so tests drive them.
@MainActor
protocol PushSystem: AnyObject {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async -> Bool
    func registerForRemoteNotifications()
}

@MainActor
final class LivePushSystem: PushSystem {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        let granted = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
}

/// Asks once, registers every launch, sends every token it gets.
@MainActor
final class PushRegistration {
    static let askedKey = "midas.push.asked"

    private let system: PushSystem
    private let defaults: UserDefaults
    private let send: @MainActor (PushRegisterAPI.Body) async -> Void
    private let environment: @MainActor () -> String
    private let bundleId: String
    /// Bodies sent, newest last (tests read it).
    private(set) var sent: [PushRegisterAPI.Body] = []

    init(system: PushSystem, defaults: UserDefaults = .standard, bundleId: String = Bundle.main.bundleIdentifier ?? "com.bhuvanrj.midas", environment: @escaping @MainActor () -> String = PushRegistration.liveEnvironment, send: @escaping @MainActor (PushRegisterAPI.Body) async -> Void) {
        self.system = system
        self.defaults = defaults
        self.bundleId = bundleId
        self.environment = environment
        self.send = send
    }

    static func liveEnvironment() -> String {
        PushEnvironment.current()
    }

    /// After sign-in, on every launch: the permission is asked the first time only (Not Now is
    /// never asked again), then Midas registers whenever it may show notifications.
    func afterSignIn() async {
        var status = await system.authorizationStatus()
        if status == .notDetermined && !defaults.bool(forKey: Self.askedKey) {
            defaults.set(true, forKey: Self.askedKey)
            _ = await system.requestAuthorization()
            status = await system.authorizationStatus()
        }
        switch status {
        case .authorized, .provisional, .ephemeral:
            system.registerForRemoteNotifications()
        default:
            return
        }
    }

    /// iOS gave the token: it goes to the server with its APNs host and the app's bundle id.
    func didRegister(deviceToken: Data) async {
        let body = PushRegisterAPI.Body(token: PushEnvironment.hex(deviceToken), env: environment(), bundleId: bundleId)
        sent.append(body)
        await send(body)
    }
}

// MARK: - A Make push, read

/// `userInfo["make"]` of a Make push: `{kind, requestId, userId, cardId?}` (contract section 4).
struct MakePushPayload: Equatable, Sendable {
    enum Kind: String, Sendable {
        case card
        case built
        case message
        case answer
    }

    let kind: Kind
    let requestId: String
    let userId: String
    let cardId: String?

    init?(userInfo: [AnyHashable: Any]) {
        guard let make = userInfo["make"] as? [String: Any], let kindText = make["kind"] as? String, let kind = Kind(rawValue: kindText), let requestId = make["requestId"] as? String, let userId = make["userId"] as? String else {
            return nil
        }
        self.kind = kind
        self.requestId = requestId
        self.userId = userId
        self.cardId = make["cardId"] as? String
    }

    /// A card or Built goes to the person; a message or an answer goes to the founder.
    var isForFounder: Bool {
        kind == .message || kind == .answer
    }

    /// The thread this push is about: the person's request, or the person's request in the
    /// founder's inbox.
    var thread: MakeThreadRef {
        isForFounder ? MakeThreadRef(userId: userId, reqId: requestId) : MakeThreadRef(userId: nil, reqId: requestId)
    }

    /// While Midas is open: no banner when that thread is already on screen.
    func showsBanner(openThread: MakeThreadRef?) -> Bool {
        openThread != thread
    }
}
