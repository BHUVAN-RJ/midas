import Foundation

/// Turns a midas:// link (from a widget tile, see shell/Shared/WidgetShared.swift) into a change
/// of what the shell shows. Any other URL is ignored.
@MainActor
enum MidasLinkHandler {
    static func handle(url: URL, router: SidekickRouter) {
        guard let link = MidasLink(url: url) else {
            return
        }
        switch link {
        case .home:
            router.goHome()
        case .openSidekick(let sidekickId):
            // The router ignores an id that is not in the directory (unknown, or not loaded yet).
            router.open(sidekickId: sidekickId)
        }
    }
}
