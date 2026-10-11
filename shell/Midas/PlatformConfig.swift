import Foundation

enum PlatformConfig {
    static let liveHost = "midas-api.midas-backend.workers.dev"
    static let stagingHost = "midas-api-staging.midas-backend.workers.dev"
    /// Info.plist key set from the MIDAS_PLATFORM_HOST build setting: staging for Debug,
    /// live for Release (shell/project.yml).
    static let platformHostInfoKey = "MidasPlatformHost"

    /// The one origin Sidekicks may fetch from (CSP connect-src) and where bundles come from.
    static let platformOrigin = origin(forHost: Bundle.main.object(forInfoDictionaryKey: platformHostInfoKey) as? String)

    /// Sidekick pages load as sidekick://<id>/, which gives each bundle its own real origin.
    static let sidekickScheme = "sidekick"

    /// Only the two Midas servers are accepted; anything else (missing, mistyped) means live.
    static func origin(forHost host: String?) -> URL {
        let knownHosts = [liveHost, stagingHost]
        guard let host, knownHosts.contains(host) else {
            return URL(string: "https://\(liveHost)")!
        }
        return URL(string: "https://\(host)")!
    }
}
