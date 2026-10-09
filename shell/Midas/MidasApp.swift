import SwiftUI
import WebKit

@main
struct MidasApp: App {
    @UIApplicationDelegateAdaptor(ShellAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            SidekickListView(router: ShellServices.shared.router)
        }
        .onChange(of: scenePhase, handleScenePhaseChange)
    }

    // Opening Midas is a chance to top up the booked reminders; leaving it is the moment to
    // ask iOS for the next background refresh.
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            Task { @MainActor in
                await ShellServices.shared.notificationEngine.refresh()
            }
        case .background:
            BackgroundRefresh.scheduleNext()
        default:
            break
        }
    }
}

struct SidekickListView: View {
    @Bindable var router: SidekickRouter

    var body: some View {
        NavigationStack(path: $router.path) {
            List(SidekickCatalog.all) { sidekick in
                NavigationLink(value: sidekick) {
                    SidekickRow(sidekick: sidekick)
                }
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
        let bundleLoader = RemoteSidekickBundleLoader(platformOrigin: PlatformConfig.platformOrigin, session: .shared)
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: bundleLoader, platformOrigin: PlatformConfig.platformOrigin, storeChannel: ShellServices.shared.storeChannel)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
