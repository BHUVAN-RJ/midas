import SwiftUI
import WebKit

@main
struct MidasApp: App {
    @UIApplicationDelegateAdaptor(ShellAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var auth = AuthModel(
        api: RemoteAuthAPI(platformOrigin: PlatformConfig.platformOrigin, session: .shared),
        store: KeychainSessionStore(),
        passkeys: SystemPasskeyAuthenticator()
    )

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
        }
        .onChange(of: scenePhase, handleScenePhaseChange)
    }

    // Opening Midas is a chance to top up the booked reminders; leaving it is the moment to
    // ask iOS for the next background refresh. Reminders already on the phone keep firing
    // whether or not the user is signed in.
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            Task { @MainActor in
                await ShellServices.shared.notificationEngine.refresh()
            }
            Task { @MainActor in
                await ShellServices.shared.directory.refresh()
            }
            Task { @MainActor in
                await Self.syncIfSignedIn()
            }
        case .background:
            BackgroundRefresh.scheduleNext()
        default:
            break
        }
    }

    @MainActor
    private static func syncIfSignedIn() async {
        guard ShellServices.currentSessionToken() != nil else {
            return
        }
        await ShellServices.shared.recordSync.syncNow()
    }
}

/// Nothing past the welcome screen is reachable without a session.
struct RootView: View {
    let auth: AuthModel

    var body: some View {
        Group {
            switch auth.state {
            case .checking:
                ProgressView()
            case .signedOut:
                WelcomeView(auth: auth)
            case .signedIn:
                RestoreGate(recordSync: ShellServices.shared.recordSync) {
                    SidekickListView(router: ShellServices.shared.router, directory: ShellServices.shared.directory, remindersImport: ShellServices.shared.remindersImport)
                }
            }
        }
        .task {
            await auth.start()
        }
    }
}

/// Words on the restore screen and the home grid (docs/WRITING.md; founder approved the wording
/// mockup 2026-10-10).
enum RestoreCopy {
    static let working = "Restoring…"
    static let failedTitle = "Can’t Connect"
    static let retryButton = "Try Again"
}

enum HomeCopy {
    static let empty = "No Sidekicks"
}

/// On a fresh install (new phone, reinstall) the records come back from the server before any
/// Sidekick shows, so nothing looks lost and nothing is written on top of an empty store.
/// After the first full pull this passes straight through, offline included.
struct RestoreGate<Content: View>: View {
    let recordSync: RecordSync
    @ViewBuilder let content: () -> Content

    private enum Phase {
        case restoring
        case failed
        case ready
    }

    @State private var phase: Phase = .restoring

    var body: some View {
        Group {
            switch phase {
            case .restoring:
                ProgressView(RestoreCopy.working)
            case .failed:
                ContentUnavailableView {
                    Label(RestoreCopy.failedTitle, systemImage: "wifi.exclamationmark")
                } actions: {
                    Button(RestoreCopy.retryButton, action: retry)
                }
            case .ready:
                content()
            }
        }
        .task {
            await restore()
        }
    }

    private func retry() {
        phase = .restoring
        Task { @MainActor in
            await restore()
        }
    }

    private func restore() async {
        let isRestored = await recordSync.completeInitialSync()
        phase = isRestored ? .ready : .failed
    }
}

/// The user's assigned Sidekicks (GET /sidekicks) as a grid of icons, like the iPhone home
/// screen (founder, 2026-10-10). Empty until the founder assigns some.
struct SidekickListView: View {
    @Bindable var router: SidekickRouter
    let directory: SidekickDirectory
    let remindersImport: AppleRemindersImportCenter

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                Text("Midas")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                SidekickHomeGrid(entries: directory.entries)
            }
            .overlay {
                if directory.entries.isEmpty && directory.hasLoadedFromServer {
                    ContentUnavailableView(HomeCopy.empty, systemImage: "square.grid.2x2")
                }
            }
            .task {
                await directory.refresh()
            }
            .refreshable {
                await directory.refresh()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: SidekickEntry.self) { sidekick in
                SidekickScreen(sidekick: sidekick)
            }
        }
        .sheet(item: shownImportRequest, onDismiss: remindersImport.cancelShownRequest) { request in
            AppleRemindersImportSheet(center: remindersImport, askingSidekick: directory.entry(withId: request.sidekickId))
        }
    }

    /// The import sheet is up while a Sidekick's import request waits for the user's answer.
    private var shownImportRequest: Binding<AppleRemindersImportRequest?> {
        Binding(get: readShownImportRequest, set: writeShownImportRequest)
    }

    private func readShownImportRequest() -> AppleRemindersImportRequest? {
        remindersImport.shownRequest
    }

    // Swiping the sheet away counts as "Not Now"
    private func writeShownImportRequest(_ request: AppleRemindersImportRequest?) {
        if request == nil {
            remindersImport.cancelShownRequest()
        }
    }
}

/// A Sidekick fills the screen: no back button, no title (founder, 2026-10-10). A swipe in from
/// the left edge goes back to the grid.
struct SidekickScreen: View {
    let sidekick: SidekickEntry

    var body: some View {
        SidekickWebView(sidekickId: sidekick.id)
            .ignoresSafeArea(edges: .bottom)
            .toolbar(.hidden, for: .navigationBar)
            .background {
                SwipeBackEnabler()
                    .frame(width: 0, height: 0)
            }
    }
}

struct SidekickWebView: UIViewRepresentable {
    let sidekickId: String

    func makeCoordinator() -> SidekickNavigationGuard {
        SidekickNavigationGuard(sidekickId: sidekickId)
    }

    func makeUIView(context: Context) -> WKWebView {
        let bundleLoader = RemoteSidekickBundleLoader(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: bundleLoader, platformOrigin: PlatformConfig.platformOrigin, storeChannel: ShellServices.shared.storeChannel)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
