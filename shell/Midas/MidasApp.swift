import SwiftUI
import WebKit

@main
struct MidasApp: App {
    var body: some Scene {
        WindowGroup {
            SidekickListView()
        }
    }
}

struct SidekickListView: View {
    var body: some View {
        NavigationStack {
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
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: bundleLoader, platformOrigin: PlatformConfig.platformOrigin)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
