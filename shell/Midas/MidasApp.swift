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
        case .background:
            BackgroundRefresh.scheduleNext()
        default:
            break
        }
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
                SidekickListView(router: ShellServices.shared.router, directory: ShellServices.shared.directory)
            }
        }
        .task {
            await auth.start()
        }
    }
}

/// The user's assigned Sidekicks (GET /sidekicks). Empty until the founder assigns some.
struct SidekickListView: View {
    @Bindable var router: SidekickRouter
    let directory: SidekickDirectory

    var body: some View {
        NavigationStack(path: $router.path) {
            List(directory.entries) { sidekick in
                NavigationLink(value: sidekick) {
                    SidekickRow(sidekick: sidekick)
                }
            }
            .overlay {
                if directory.entries.isEmpty && directory.hasLoadedFromServer {
                    ContentUnavailableView("No Sidekicks yet", systemImage: "square.grid.2x2")
                }
            }
            .task {
                await directory.refresh()
            }
            .refreshable {
                await directory.refresh()
            }
            .navigationTitle("Midas")
            .navigationDestination(for: SidekickEntry.self) { sidekick in
                SidekickScreen(sidekick: sidekick)
            }
        }
    }
}

struct SidekickRow: View {
    let sidekick: SidekickEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sidekick.symbolName)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(sidekick.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
            Text(sidekick.name)
        }
    }
}

struct SidekickScreen: View {
    let sidekick: SidekickEntry

    var body: some View {
        SidekickWebView(sidekickId: sidekick.id)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(sidekick.name)
            .navigationBarTitleDisplayMode(.inline)
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
