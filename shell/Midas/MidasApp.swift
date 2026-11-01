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
    // a widget's tap (SidekickWidgetActionIntent runs in the app's process).
    init() {
        SidekickWidgetIntentBridge.perform = Self.performFromSidekickWidget
        VoiceReminderIntentBridge.open = Self.openVoiceReminder
    }

    /// "Ask jess" from the Action button, a Shortcut or the control: the Listening screen.
    @MainActor
    static func openVoiceReminder() {
        ShellServices.shared.voiceReminders.request()
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
                ShellServices.shared.sidekickWidgets.publish()
            }
            Task { @MainActor in
                // A request iOS stopped while Midas was away: finished now, exactly once
                await ShellServices.shared.jessResults.resume()
            }
            Task { @MainActor in
                await Self.syncIfSignedIn()
                // After the pull: a request jess sent to repair and the backend ran again
                await ShellServices.shared.jessGrowFollowUp.check()
                // A plain repair a Workdesk card waits on
                await ShellServices.shared.jessRepairFollowUp.check()
            }
            Task { @MainActor in
                // Repair reports queued while offline or before a crash.
                await ShellServices.shared.repairUploader.retryQueued()
                // What came of repairs sent from a Sidekick, and keep asking while one is on its way
                await ShellServices.shared.repairCenter.check()
                ShellServices.shared.repairCenter.startPolling()
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
    /// Onboarding (docs/briefs/onboarding-build.md): intro, sign in, teaching cards, once per user
    @State private var onboarding = OnboardingProgress()

    var body: some View {
        Group {
            switch onboarding.stage(for: auth.state) {
            case .checking:
                ProgressView()
            case .intro:
                OnboardingIntroView(onGetStarted: finishIntro)
                    .transition(.opacity)
            case .welcome:
                WelcomeView(auth: auth)
                    .transition(.opacity)
            case .teach:
                OnboardingTeachView(onContinue: finishTeach)
                    .transition(.opacity)
            case .home:
                signedInHome
            }
        }
        .task {
            await auth.start()
        }
        .onAppear(perform: connectAccount)
        .onChange(of: auth.state, initial: true, noteAuthState)
        .sheet(isPresented: .constant(HomeScreenDemoLaunch.frozenTimeMs != nil)) {
            HomeScreenDemoLaunch.sheet()
        }
    }

    @ViewBuilder
    private var signedInHome: some View {
        if case .signedIn(let user) = auth.state {
            // Another account's records leave the phone before this one's restore
            RestoreGate(recordSync: ShellServices.shared.recordSync, beforeRestore: adoptAccount(user)) {
                SidekickListView(router: ShellServices.shared.router, directory: ShellServices.shared.directory, remindersImport: ShellServices.shared.remindersImport, userName: user.name)
            }
            // Microphone and speech recognition, asked when Midas opens (founder, 2026-10-15);
            // then notifications, once, and the push token on every launch (Make, contract
            // section 8), one prompt after the other.
            .task {
                await VoicePermissions.askAtLaunch()
                await ShellServices.shared.pushRegistration.afterSignIn()
            }
            // "Ask jess": the Listening screen and the result banner (founder, 2026-10-15).
            .voiceReminders(ShellServices.shared.voiceReminders)
        }
    }
}

extension RootView {
    /// Settings' Sign Out and Delete Account end the session here (settings-delete, 2026-10-31).
    fileprivate func connectAccount() {
        ShellServices.shared.account.endSession = auth.signOut
    }

    /// Someone already signed in when onboarding arrived is marked as having seen it.
    fileprivate func noteAuthState(_ oldState: AuthState, _ newState: AuthState) {
        onboarding.noteAuthState(newState)
    }

    /// Get Started: cross-fade to the welcome screen (0.35 s, brief section 7).
    fileprivate func finishIntro() {
        withAnimation(.easeInOut(duration: 0.35), onboarding.finishIntro)
    }

    /// Continue on the last card: the Sidekicks, then the permission prompts.
    fileprivate func finishTeach() {
        withAnimation(.easeInOut(duration: 0.35), onboarding.finishTeach)
    }

    fileprivate func adoptAccount(_ user: MidasUser) -> @MainActor () -> Void {
        func adopt() {
            ShellServices.shared.adoptAccount(userId: user.id)
        }
        return adopt
    }
}

/// A DEBUG run with the launch argument `-MidasHomeScreenDemo <ms>` opens the "Add to Home Screen"
/// sheet for Water at once, held still at that moment, for simulator screenshots. Never in a
/// release build.
enum HomeScreenDemoLaunch {
    static let launchArgument = "MidasHomeScreenDemo"

    static var frozenTimeMs: Double? {
        #if DEBUG
        let timeMs = UserDefaults.standard.double(forKey: launchArgument)
        return timeMs > 0 ? timeMs : nil
        #else
        return nil
        #endif
    }

    @MainActor
    static func sheet() -> some View {
        let request = HomeScreenWidgetRequest(sidekickId: "hydration", requestKey: "request:demo", variant: .sidekick)
        let file = SharedSidekickWidgets.read(from: SidekickWidgetShared.fileURL())
        let entries = ShellServices.shared.directory.entries
        let content = HomeScreenDemoContent.make(request: request, file: file, entries: entries, now: Date())
        return HomeScreenWidgetSheetView(content: content, frozenTimeMs: frozenTimeMs, onDone: dismissDemo)
    }

    private static func dismissDemo() {
        // Held open on purpose: the screenshot run ends by quitting the app
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

@MainActor
private func nothingBeforeRestore() {}

/// On a fresh install (new phone, reinstall) the records come back from the server before any
/// Sidekick shows, so nothing looks lost and nothing is written on top of an empty store.
/// After the first full pull this passes straight through, offline included.
struct RestoreGate<Content: View>: View {
    let recordSync: RecordSync
    /// Runs before the restore: the signed-in account adopts the store (settings-delete).
    var beforeRestore: @MainActor () -> Void = nothingBeforeRestore
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
        beforeRestore()
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
    var jessResults: JessResults = ShellServices.shared.jessResults
    var make: MakeCenter = ShellServices.shared.make
    var homeScreenWidgets: HomeScreenWidgetCenter = ShellServices.shared.homeScreenWidgets
    /// E1's initial and Settings' big name (settings-delete, 2026-10-31).
    var userName: String = ""
    var account: AccountCenter = ShellServices.shared.account
    /// Press and hold: the tiles jiggle and can be deleted.
    @State private var arrangement = HomeArrangement()
    /// C3 is up for this Sidekick.
    @State private var sidekickToDelete: SidekickEntry?

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                HomeTopBar(userName: userName, isArranging: arrangement.isArranging, onOpenSettings: openSettings, onDone: arrangement.stopArranging)
                if recordSync.refusedOpCount > 0 {
                    Text(HomeCopy.notBackedUp(count: recordSync.refusedOpCount))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                }
                // Home shows Not Done cards only (founder, 2026-10-31)
                if !jessResults.homeCards.isEmpty {
                    JessResultCardStack(results: jessResults)
                        .padding(.bottom, 16)
                }
                SidekickHomeGrid(entries: directory.entries, onOpenJess: voice.request)
                    // R2: where each tile sits, and the new Sidekick's slot kept empty (Make)
                    .environment(make.builtStage)
                    .environment(arrangement)
            }
            // A tap on the empty grid ends the jiggle, as on iOS
            .contentShape(Rectangle())
            .onTapGesture(perform: stopArrangingOnTap)
            .onAppear(perform: connectArrangement)
            .onChange(of: router.path, stopArrangingWhenLeaving)
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
            .navigationDestination(for: SidekickEntry.self, destination: destination)
        }
        // R2: a Built request's screen, then its tile locking into the grid (Make)
        .overlay {
            MakeBuiltOverlay(stage: make.builtStage)
        }
        // C3: "Delete Water?" with the tile
        .sheet(item: $sidekickToDelete) { sidekick in
            SidekickDeleteSheet(sidekick: sidekick, account: account, onClose: closeDeleteSheet)
        }
        .sheet(item: shownImportRequest, onDismiss: remindersImport.cancelShownRequest) { request in
            AppleRemindersImportSheet(center: remindersImport, askingSidekick: directory.entry(withId: request.sidekickId))
        }
        // "Add to Home Screen", for the Sidekick that asked (founder, 2026-10-26)
        .sheet(item: shownHomeScreenRequest) { request in
            HomeScreenWidgetSheetView(content: homeScreenContent(for: request), onDone: homeScreenWidgets.dismiss)
        }
    }

    /// Make and the Inbox are native screens, Settings too; every other Sidekick is its web page.
    @ViewBuilder
    private func destination(for sidekick: SidekickEntry) -> some View {
        if SettingsPage.isSettings(sidekick) {
            SettingsView(userName: userName, sidekicks: MakeSidekick.listedEntries(directory.entries), account: account)
        } else if MakeSidekick.isMake(sidekick) {
            MakeHomeView(center: make)
        } else if MakeSidekick.isInbox(sidekick) {
            MakeInboxView(center: make)
        } else {
            SidekickScreen(sidekick: sidekick)
        }
    }

    private func openSettings() {
        router.path.append(SettingsPage.entry)
    }

    private func openSidekick(_ sidekick: SidekickEntry) {
        router.path.append(sidekick)
    }

    private func askDelete(_ sidekick: SidekickEntry) {
        sidekickToDelete = sidekick
    }

    private func closeDeleteSheet() {
        sidekickToDelete = nil
    }

    private func connectArrangement() {
        arrangement.openSidekick = openSidekick
        arrangement.askDelete = askDelete
    }

    private func stopArrangingOnTap() {
        arrangement.stopArranging()
    }

    // A notification or widget opened a Sidekick: the grid stops jiggling behind it
    private func stopArrangingWhenLeaving(_ oldPath: [SidekickEntry], _ newPath: [SidekickEntry]) {
        if !newPath.isEmpty {
            arrangement.stopArranging()
        }
    }

    private var shownHomeScreenRequest: Binding<HomeScreenWidgetRequest?> {
        Binding(get: readShownHomeScreenRequest, set: writeShownHomeScreenRequest)
    }

    private func readShownHomeScreenRequest() -> HomeScreenWidgetRequest? {
        homeScreenWidgets.shownRequest
    }

    private func writeShownHomeScreenRequest(_ request: HomeScreenWidgetRequest?) {
        if request == nil {
            homeScreenWidgets.dismiss()
        }
    }

    private func homeScreenContent(for request: HomeScreenWidgetRequest) -> HomeScreenDemoContent {
        let file = SharedSidekickWidgets.read(from: SidekickWidgetShared.fileURL())
        return HomeScreenDemoContent.make(request: request, file: file, entries: directory.entries, now: Date())
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
/// the left edge goes back to the grid. Over it: the repair layer while a repair is open, and the
/// V1 rim and Repair tag (founder, 2026-10-23), the tag only on the Sidekick being repaired.
struct SidekickScreen: View {
    let sidekick: SidekickEntry
    /// Words over the page for a moment: "Already Deleted" from a jess work log card.
    var notice: String? = nil
    var repairCenter: RepairCenter = ShellServices.shared.repairCenter
    /// The repair layer, shown over the frozen Sidekick from the three-finger swipe until Send or Cancel.
    @State private var repairSession: RepairSession?
    @State private var chrome = RepairChrome()
    @State private var page = SidekickPageHandle()

    var body: some View {
        // Also takes the web view to the bottom edge (`ignoresSafeArea`), between the repair
        // layer's two parts
        SidekickWebView(sidekickId: sidekick.id, page: page, onRepairSession: showRepair, onSwipeProgress: chrome.swipeProgressed, onRepairUnavailable: chrome.swipeLetGo)
            .onGeometryChange(for: CGRect.self, of: Self.globalFrame, action: recordPageFrame)
            .repairLayer(repairSession)
            .overlay {
                RepairChromeOverlay(chrome: chrome, center: repairCenter, sidekickId: sidekick.id, session: repairSession, onUpdatePage: updatePage)
            }
            .overlay(alignment: .bottom) {
                if let notice {
                    JessLinkNotice(words: notice)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .background {
                SwipeBackEnabler()
                    .frame(width: 0, height: 0)
            }
            .onAppear(perform: sidekickAppeared)
            .onDisappear(perform: sidekickDisappeared)
    }

    nonisolated private static func globalFrame(_ proxy: GeometryProxy) -> CGRect {
        proxy.frame(in: .global)
    }

    private func recordPageFrame(_ frame: CGRect) {
        chrome.pageFrame = frame
    }

    private func sidekickAppeared() {
        repairCenter.sidekickOpened(sidekick.id)
        ShellServices.shared.sidekickWidgets.noteOpened(sidekickId: sidekick.id)
    }

    private func sidekickDisappeared() {
        repairCenter.sidekickClosed(sidekick.id)
    }

    private func showRepair(_ session: RepairSession) {
        session.onFinish = dismissRepair
        session.onSent = repairSent
        chrome.swipeLocked()
        repairSession = session
    }

    private func dismissRepair() {
        let finish = repairSession?.finish
        chrome.sessionEnded(finish)
        // Send: the pill drops after 200 ms, 320 ms ease-in; Cancel: it goes in 200 ms
        let removal = finish == .sent ? Animation.easeIn(duration: RepairPillSpec.drop).delay(RepairPillSpec.dropDelay) : Animation.easeIn(duration: RepairRimSpec.cancelFade)
        withAnimation(removal) {
            repairSession = nil
        }
    }

    private func repairSent(_ report: RepairReport, drawing: UIImage) {
        repairCenter.didSend(report)
        chrome.playSendAnimation(shot: drawing)
    }

    /// "Repair done. Tap to update": the new version grows out of the tag (U4).
    private func updatePage(from tagCenter: CGPoint) {
        guard let webView = page.webView, let coordinator = page.coordinator else {
            return
        }
        func reload(_ shown: @escaping @MainActor () -> Void) {
            coordinator.reloadPage(finished: shown)
        }
        SidekickPageUpdate.play(webView: webView, tagCenterInWindow: tagCenter, reduceMotion: UIAccessibility.isReduceMotionEnabled, reload: reload)
    }
}

/// The open Sidekick's web view and coordinator, for the update after a repair.
@MainActor
final class SidekickPageHandle {
    weak var webView: WKWebView?
    weak var coordinator: SidekickWebViewCoordinator?
}

struct SidekickWebView: UIViewRepresentable {
    let sidekickId: String
    var page: SidekickPageHandle?
    let onRepairSession: (RepairSession) -> Void
    var onSwipeProgress: ((Double) -> Void)?
    var onRepairUnavailable: (() -> Void)?

    func makeCoordinator() -> SidekickWebViewCoordinator {
        SidekickWebViewCoordinator(sidekickId: sidekickId)
    }

    func makeUIView(context: Context) -> WKWebView {
        let bundleLoader = RemoteSidekickBundleLoader(platformOrigin: PlatformConfig.platformOrigin, session: .shared, sessionToken: ShellServices.currentSessionToken)
        let webView = SidekickWebViewFactory.makeWebView(bundleLoader: bundleLoader, platformOrigin: PlatformConfig.platformOrigin, storeChannel: ShellServices.shared.storeChannel)
        let coordinator = context.coordinator
        webView.navigationDelegate = coordinator.navigationGuard
        coordinator.webView = webView
        wire(coordinator)
        page?.webView = webView
        page?.coordinator = coordinator
        let swipeDown = ThreeFingerSwipeRecognizer(target: coordinator, action: #selector(SidekickWebViewCoordinator.startRepair(_:)))
        swipeDown.onProgress = coordinator.swipeProgressed
        webView.addGestureRecognizer(swipeDown)
        webView.load(URLRequest(url: SidekickWebViewFactory.sidekickURL(sidekickId: sidekickId)))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        wire(context.coordinator)
    }

    private func wire(_ coordinator: SidekickWebViewCoordinator) {
        coordinator.onRepairSession = onRepairSession
        coordinator.onSwipeProgress = onSwipeProgress
        coordinator.onRepairUnavailable = onRepairUnavailable
    }
}
