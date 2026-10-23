import Foundation
import Network

/// Calls `onBack` each time the network comes back after being away (founder, 2026-10-22: a
/// cut-off jess request is sent again then).
@MainActor
final class JessNetworkWatch {
    private let monitor = NWPathMonitor()
    private let onBack: @MainActor () -> Void
    private var wasConnected = true

    init(onBack: @escaping @MainActor () -> Void) {
        self.onBack = onBack
    }

    func start() {
        monitor.pathUpdateHandler = Self.pathHandler(for: self)
        monitor.start(queue: DispatchQueue(label: "jess network watch"))
    }

    /// The monitor calls this on its own queue; the change is handled on the main actor.
    private nonisolated static func pathHandler(for watch: JessNetworkWatch) -> @Sendable (NWPath) -> Void {
        @Sendable func pathChanged(_ path: NWPath) {
            let isConnected = path.status == .satisfied
            Task { @MainActor in
                watch.connectionChanged(isConnected: isConnected)
            }
        }
        return pathChanged
    }

    /// Only the change from away to back counts.
    func connectionChanged(isConnected: Bool) {
        let cameBack = isConnected && !wasConnected
        wasConnected = isConnected
        if cameBack {
            onBack()
        }
    }
}
