import SwiftUI

/// Pull while open (contract section 8): while Make or the Inbox is on screen and the app is
/// active, the records are pulled every 3 seconds, so the founder's replies and the person's words
/// show without a push. The screens redraw from `MakeCenter.revision`, which the store's change
/// observer bumps when a pull brings a Make record.
enum MakeLivePull {
    static let interval: Duration = .seconds(3)

    /// Pulls once per `interval` until the task is cancelled (the screen went away or the app left
    /// the foreground). The first pull is at once.
    @MainActor
    static func run(isActive: @MainActor () -> Bool, pull: @MainActor () async -> Void, interval: Duration = MakeLivePull.interval, sleep: @MainActor (Duration) async throws -> Void = MakeLivePull.sleep) async {
        while !Task.isCancelled {
            if isActive() {
                await pull()
            }
            do {
                try await sleep(interval)
            } catch {
                return
            }
        }
    }

    static func sleep(_ duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

private struct MakeLivePullModifier: ViewModifier {
    let center: MakeCenter
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        // A new phase restarts the task: it runs only while active
        content.task(id: scenePhase, pullWhileActive)
    }

    private func pullWhileActive() async {
        guard scenePhase == .active else {
            return
        }
        await MakeLivePull.run(isActive: isActive, pull: pull)
    }

    private func isActive() -> Bool {
        scenePhase == .active
    }

    private func pull() async {
        await center.sync()
    }
}

extension View {
    /// Pulls Make's records every 3 s while this screen is up and Midas is in front.
    func makeLivePull(_ center: MakeCenter) -> some View {
        modifier(MakeLivePullModifier(center: center))
    }
}
