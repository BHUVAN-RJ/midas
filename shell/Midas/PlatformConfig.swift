import Foundation

enum PlatformConfig {
    /// The one origin Sidekicks may fetch from (CSP connect-src) and where bundles come from.
    static let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!

    /// Sidekick pages load as sidekick://<id>/, which gives each bundle its own real origin.
    static let sidekickScheme = "sidekick"
}
