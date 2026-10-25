import SwiftUI
import UIKit
import XCTest
@testable import Midas

// How Make sits in the shell (docs/briefs/make-contract.md section 8, founder 2026-10-24): the
// pill's words (voice starts, tapping to type stops listening, Send takes the words), the pull
// every 3 s while open, a push opening Make or the Inbox on its thread, Make on the home grid
// before the server lists it (DEBUG), its tile, the swipe catcher finding its own screen, and the
// shared B3 pill keeping repair's 60 pt.

/// Starts at once and lets the test say words.
@MainActor
private final class SayingTranscriber: RepairTranscribing {
    private var onUpdate: (@MainActor (RepairTranscript) -> Void)?
    private(set) var starts = 0
    private(set) var stops = 0

    func start(sessionStartedAt: Date, onUpdate: @escaping @MainActor (RepairTranscript) -> Void) async throws {
        starts += 1
        self.onUpdate = onUpdate
    }

    func stop() {
        stops += 1
    }

    func say(_ text: String) {
        onUpdate?(RepairTranscript(text: text, words: []))
    }
}

/// A directory fetcher with nothing to fetch: the tests use the cached list.
private struct NoFetch: SidekickDirectoryFetching {
    func fetchSidekicks() async throws -> [SidekickEntry] {
        throw SidekickDirectoryError.badResponse
    }
}

/// B3 on its own, as Make shows it.
private struct PillBarHost: View {
    let onPillLayout: (CGRect) -> Void
    @State private var typed = ""
    @State private var isTyping = false

    var body: some View {
        VStack {
            Spacer()
            PillBar(settled: "", pending: "", typed: $typed, isTyping: $isTyping, placeholder: MakeCopy.newRequestPlaceholder, orbState: .idle, canSend: false, onSend: PillBarHost.noSend, onPillLayout: onPillLayout)
                .padding(.horizontal, RepairPillSpec.sideMargin)
        }
    }

    static func noSend() {}
}

@MainActor
private final class FrameBox {
    var frame: CGRect = .zero

    func record(_ newFrame: CGRect) {
        frame = newFrame
    }
}

@MainActor
final class MakeShellWiringTests: XCTestCase {
    private var cacheURL: URL!
    private var storeURL: URL!
    private var defaultsSuite = ""

    override func setUp() {
        super.setUp()
        cacheURL = FileManager.default.temporaryDirectory.appending(path: "make-wiring-dir-\(UUID().uuidString).json")
        storeURL = FileManager.default.temporaryDirectory.appending(path: "make-wiring-store-\(UUID().uuidString).json")
        defaultsSuite = "make-wiring-\(UUID().uuidString)"
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheURL)
        try? FileManager.default.removeItem(at: storeURL)
        UserDefaults().removePersistentDomain(forName: defaultsSuite)
        super.tearDown()
    }

    // MARK: The pill's words

    func testVoiceWordsThenTypedWordsGoAsOneMessageAndTypingStopsListening() async {
        let transcriber = SayingTranscriber()
        func makeTranscriber() -> RepairTranscribing {
            transcriber
        }
        let composer = PillVoiceComposer(makeTranscriber: makeTranscriber)
        XCTAssertFalse(composer.canSend)
        await composer.startListening()
        XCTAssertTrue(composer.isListening)
        XCTAssertEqual(composer.orbState, .listening)
        transcriber.say("my plants keep dying")
        XCTAssertEqual(composer.words, "my plants keep dying")
        XCTAssertEqual(composer.pillText.pending, "dying", "the newest word is grey while listening")

        // Tap to type stops listening (contract section 8)
        composer.isTyping = true
        XCTAssertFalse(composer.isListening)
        XCTAssertEqual(transcriber.stops, 1)
        XCTAssertEqual(composer.orbState, .idle)
        composer.typed = "every week"
        XCTAssertEqual(composer.words, "my plants keep dying every week")
        XCTAssertTrue(composer.canSend)

        // Words from the stopped listen are dropped
        transcriber.say("something else")
        XCTAssertEqual(composer.words, "my plants keep dying every week")

        XCTAssertEqual(composer.take(), "my plants keep dying every week")
        XCTAssertEqual(composer.words, "")
        XCTAssertFalse(composer.canSend)
        XCTAssertNil(composer.take(), "an empty pill sends nothing")
    }

    func testListeningDoesNotStartWhileTyping() async {
        let transcriber = SayingTranscriber()
        func makeTranscriber() -> RepairTranscribing {
            transcriber
        }
        let composer = PillVoiceComposer(makeTranscriber: makeTranscriber)
        composer.isTyping = true
        await composer.startListening()
        XCTAssertFalse(composer.isListening)
        XCTAssertEqual(transcriber.starts, 0)
    }

    // MARK: Pull while open

    func testPullsAtOnceThenEveryThreeSecondsUntilCancelled() async {
        var pulls = 0
        var sleeps: [Duration] = []
        func isActive() -> Bool {
            true
        }
        func pull() async {
            pulls += 1
        }
        // The third sleep is where the screen went away
        func sleep(_ duration: Duration) async throws {
            sleeps.append(duration)
            if sleeps.count == 3 {
                throw CancellationError()
            }
        }
        await MakeLivePull.run(isActive: isActive, pull: pull, sleep: sleep)
        XCTAssertEqual(pulls, 3)
        XCTAssertEqual(sleeps, [.seconds(3), .seconds(3), .seconds(3)])
    }

    func testNoPullWhileMidasIsNotInFront() async {
        var pulls = 0
        var sleeps = 0
        func isActive() -> Bool {
            false
        }
        func pull() async {
            pulls += 1
        }
        func sleep(_ duration: Duration) async throws {
            sleeps += 1
            if sleeps == 2 {
                throw CancellationError()
            }
        }
        await MakeLivePull.run(isActive: isActive, pull: pull, sleep: sleep)
        XCTAssertEqual(pulls, 0)
    }

    // MARK: Opening from a push

    private func makeDirectory(cached entries: [SidekickEntry]) throws -> SidekickDirectory {
        try JSONEncoder().encode(entries).write(to: cacheURL)
        let writer = SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: Self.noReload)
        return SidekickDirectory(cacheFileURL: cacheURL, fetcher: NoFetch(), sharedListWriter: writer)
    }

    nonisolated private static func noReload() {}

    nonisolated private static func noToken() -> String? {
        nil
    }

    private static func noSync() async {}

    private func makeCenter() throws -> MakeCenter {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        let api = MakeAPI(platformOrigin: try XCTUnwrap(URL(string: "https://example.invalid")), session: .shared, sessionToken: Self.noToken)
        return MakeCenter(store: LocalRecordStore(fileURL: storeURL), api: api, defaults: defaults, sync: Self.noSync)
    }

    func testAPersonsPushOpensMakeOnItsRequest() throws {
        let make = SidekickEntry(id: "make", name: "Make", symbolName: "plus", backgroundHex: "#000000", version: "built-in")
        let router = SidekickRouter(directory: try makeDirectory(cached: [make]))
        let center = try makeCenter()
        router.openMakeRequest("request01", center: center)
        XCTAssertEqual(router.path.map(\.id), ["make"])
        XCTAssertEqual(center.pendingRequestId, "request01", "Make's home opens the thread once it is on screen")
    }

    func testTheFoundersPushOpensTheInboxOnItsThread() throws {
        let inbox = SidekickEntry(id: "make-inbox", name: "Inbox", symbolName: "tray", backgroundHex: "#000000", version: "built-in")
        let router = SidekickRouter(directory: try makeDirectory(cached: [inbox]))
        let center = try makeCenter()
        router.openInboxThread(userId: "user0001", reqId: "request01", center: center)
        XCTAssertEqual(router.path.map(\.id), ["make-inbox"])
        XCTAssertEqual(center.pendingInboxThread, MakeThreadRef(userId: "user0001", reqId: "request01"))
    }

    func testNoInboxForSomeoneWhoIsNotTheFounder() throws {
        let router = SidekickRouter(directory: try makeDirectory(cached: []))
        let center = try makeCenter()
        router.openInboxThread(userId: "user0001", reqId: "request01", center: center)
        XCTAssertTrue(router.path.isEmpty, "the server lists the Inbox only for the founder")
        XCTAssertNil(center.pendingInboxThread)
    }

    // MARK: The home grid

    func testMakeGoesAfterJessUntilTheServerListsIt() {
        let jess = SidekickEntry(id: "jess", name: "jess", symbolName: "mic", backgroundHex: "#FFFFFF", version: "built-in")
        let reminders = SidekickEntry(id: "reminders", name: "Reminders", symbolName: "checklist", backgroundHex: "#C9F24D", version: "7")
        XCTAssertEqual(MakeSidekick.addingLocalEntries(to: [jess, reminders], includeInbox: false).map(\.id), ["jess", "make", "reminders"])
        XCTAssertEqual(MakeSidekick.addingLocalEntries(to: [jess, reminders], includeInbox: true).map(\.id), ["jess", "make", "make-inbox", "reminders"])
        XCTAssertEqual(MakeSidekick.addingLocalEntries(to: [reminders], includeInbox: false).map(\.id), ["make", "reminders"])
        let listed = [jess, MakeSidekick.localEntry, reminders]
        XCTAssertEqual(MakeSidekick.addingLocalEntries(to: listed, includeInbox: false), listed, "never twice")
        XCTAssertEqual(MakeSidekick.localEntry.name, "Make")
        XCTAssertEqual(MakeSidekick.builtInIds, ["jess", "make", "make-inbox"])
    }

    func testMakesTileIsTheMakeTileAsset() {
        XCTAssertEqual(MakeTileIcon.imageName, "MakeTile")
        let appBundle = Bundle(for: RecordSchemaEngine.self)
        let light = UIImage(named: MakeTileIcon.imageName, in: appBundle, compatibleWith: UITraitCollection(userInterfaceStyle: .light))
        let dark = UIImage(named: MakeTileIcon.imageName, in: appBundle, compatibleWith: UITraitCollection(userInterfaceStyle: .dark))
        XCTAssertNotNil(light)
        XCTAssertNotNil(dark)
    }

    // MARK: The swipe catcher

    func testTheSwipeCatcherSitsOnItsOwnScreenNotTheNavigationStack() {
        let screen = UIViewController()
        let navigation = UINavigationController(rootViewController: screen)
        navigation.loadViewIfNeeded()
        screen.loadViewIfNeeded()
        let container = UIView()
        screen.view.addSubview(container)
        let probe = RepairUnavailableSwipeInstaller.ProbeView()
        container.addSubview(probe)
        XCTAssertTrue(RepairUnavailableSwipeInstaller.ProbeView.screenView(above: probe) === screen.view)

        let loose = RepairUnavailableSwipeInstaller.ProbeView()
        UIView().addSubview(loose)
        XCTAssertNil(RepairUnavailableSwipeInstaller.ProbeView.screenView(above: loose))
    }

    func testTheCatcherAddsOnePassiveRecognizerAndTakesItAway() {
        let host = UIView()
        func swiped() {}
        let coordinator = RepairUnavailableSwipeInstaller.Coordinator(onSwipe: swiped)
        coordinator.attach(to: host)
        coordinator.attach(to: host)
        let recognizers = host.gestureRecognizers ?? []
        XCTAssertEqual(recognizers.count, 1)
        XCTAssertTrue(recognizers.first is ThreeFingerSwipeRecognizer)
        XCTAssertEqual(recognizers.first?.cancelsTouchesInView, false, "taps and scrolls on Make work as before")
        coordinator.detach()
        XCTAssertTrue((host.gestureRecognizers ?? []).isEmpty)
    }

    // MARK: The shared pill

    func testThePillBarKeepsB3sSixtyPointsOnMake() async throws {
        let box = FrameBox()
        let controller = UIHostingController(rootView: PillBarHost(onPillLayout: box.record))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
        }
        for _ in 0..<50 where box.frame == .zero {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(box.frame.height, RepairPillSpec.height, accuracy: 1)
        XCTAssertEqual(box.frame.width, 402 - RepairPillSpec.sideMargin * 2, accuracy: 1)
    }
}
