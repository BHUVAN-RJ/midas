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

    // Registered before anything else, also when iOS starts Midas in the background only to run
    // a widget's tick (TickReminderIntent runs in the app's process).
    init() {
        RemindersWidgetIntentBridge.tick = Self.tickFromWidget
        SidekickWidgetIntentBridge.perform = Self.performFromSidekickWidget
        VoiceReminderIntentBridge.open = Self.openVoiceReminder
    }

    /// "New Reminder" from the Action button, a Shortcut or the control: the Listening screen.
    @MainActor
    static func openVoiceReminder() {
        ShellServices.shared.voiceReminders.request()
    }

    /// A reminder ticked done on the Reminders widget: written to the record (and its outbox),
    /// then the engine re-plans before the intent returns, so its notifications are cancelled.
    @MainActor
    private static func tickFromWidget(reminderId: String, occurrence: Date) async {
        let services = ShellServices.shared
        services.remindersWidget.tick(reminderId: reminderId, occurrence: occurrence)
        await services.notificationEngine.refresh()
    }

    /// A tap on a Sidekick widget: written to the Sidekick's record (and its outbox); a tick on a
    /// reminder re-plans its notifications before the intent returns.
    @MainActor
    private static func performFromSidekickWidget(action: WidgetTapAction) async {
        let services = ShellServices.shared
        services.sidekickWidgets.perform(action)
        await services.notificationEngine.refresh()
    }

    var body: some Scene {
        WindowGroup {
            RootView(auth: auth)
                .onOpenURL(perform: handleIncomingURL)
        }
        .onChange(of: scenePhase, handleScenePhaseChange)
    }

    /// A midas:// link, from a widget tile. Signed out or before the directory has loaded, the
    /// router finds nothing to open and the link is dropped.
    private func handleIncomingURL(_ url: URL) {
        MidasLinkHandler.handle(url: url, router: ShellServices.shared.router)
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
                // Signing in or out, a Reminders Sidekick added or removed, or a new day.
                ShellServices.shared.remindersWidget.publish()
                ShellServices.shared.sidekickWidgets.publish()
            }
            Task { @MainActor in
                await Self.syncIfSignedIn()
            }
            Task { @MainActor in
                // Repair reports queued while offline or before a crash.
                await ShellServices.shared.repairUploader.retryQueued()
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
                // Microphone and speech recognition, asked when Midas opens (founder, 2026-10-15).
                .task {
                    await VoicePermissions.askAtLaunch()
                }
                // "New Reminder": the Listening screen and the result banner (founder, 2026-10-15).
                .voiceReminders(ShellServices.shared.voiceReminders)
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

    /// Changes the server refused and the phone still holds (docs/WRITING.md: the count, then
    /// stop). Shown under the title only when there are some.
    static func notBackedUp(count: Int) -> String {
        count == 1 ? "1 change not backed up" : "\(count) changes not backed up"
    }
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
    var recordSync: RecordSync = ShellServices.shared.recordSync
    var voice: VoiceReminderFlow = ShellServices.shared.voiceReminders

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                Text("Midas")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                if recordSync.refusedOpCount > 0 {
                    Text(HomeCopy.notBackedUp(count: recordSync.refusedOpCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                }
                if let card = voice.notDoneCard {
                    JessNotDoneCardView(card: card, onRetry: voice.retryNotDone, onDismiss: voice.dismissNotDone)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
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
            .animation(.easeOut(duration: 0.25), value: voice.notDoneCard)
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
    /// The repair layer, shown over the frozen Sidekick from the three-finger swipe until Send or Cancel.
    @State private var repairSession: RepairSession?

    var body: some View {
        // Also takes the web view to the bottom edge (`ignoresSafeArea`), between the repair
        // layer's two parts
        SidekickWebView(sidekickId: sidekick.id, onRepairSession: showRepair)
            .repairLayer(repairSession)
            .toolbar(.hidden, for: .navigationBar)
            .background {
                SwipeBackEnabler()
                    .frame(width: 0, height: 0)
            }
    }

    private func showRepair(_ session: RepairSession) {
        session.onFinish = dismissRepair
        repairSession = session
    }

    private func dismissRepair() {
        repairSession = nil
    }
}

struct SidekickWebView: UIViewRepresentable {
    let sidekickId: String
    let onRepairSession: (RepairSession) -> Void

    func makeCoordinator() -> SidekickWebViewCoordinator {
        SidekickWebViewCoordinator(sidekickId: sidekickId)
    }

    func makeUIView(context: Context) -> WKWebView {
        let bundleLoader = RemoteSidekickBundleLoader(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: bundleLoader, platformOrigin: PlatformConfig.platformOrigin, storeChannel: ShellServices.shared.storeChannel)
        let coordinator = context.coordinator
        webView.navigationDelegate = coordinator.navigationGuard
        coordinator.webView = webView
        coordinator.onRepairSession = onRepairSession
        let swipeDown = ThreeFingerSwipeRecognizer(target: coordinator, action: #selector(SidekickWebViewCoordinator.startRepair(_:)))
        webView.addGestureRecognizer(swipeDown)
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onRepairSession = onRepairSession
    }
}
