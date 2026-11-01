import SwiftUI
import XCTest
@testable import Midas

// Settings and delete (founder, 2026-10-31; docs/briefs/build-22-2026-10-31.md, mockup
// docs/mockups/settings-delete-2026-10-31.html): E1 the initial on the home grid, S2 Settings,
// press and hold to delete a Sidekick (jiggle, minus, C3), jess, Make and the Inbox never
// deletable, Sign Out, Delete Account (A1, then X1, then the welcome), and one account's records
// never showing or uploading under another's.

private let settingsShellRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

private func temporaryFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appending(path: "settings-delete-\(UUID().uuidString)/\(name)")
}

private func entry(_ id: String, _ name: String, version: String = "v1") -> SidekickEntry {
    SidekickEntry(id: id, name: name, symbolName: "drop", backgroundHex: "#30D5C8", version: version)
}

private let water = entry("water", "Water")
private let reminders = entry("reminders", "Reminders")
private let jess = entry("jess", "jess", version: "built-in")
private let make = entry("make", "Make", version: "built-in")
private let inbox = entry("make-inbox", "Inbox", version: "built-in")

// MARK: - Words

final class SettingsCopyTests: XCTestCase {
    func testTheWordsAreTheFoundersPicks() {
        XCTAssertEqual(SettingsCopy.sidekicksSection, "Sidekicks")
        XCTAssertEqual(SettingsCopy.signOut, "Sign Out")
        XCTAssertEqual(SettingsCopy.deleteAccount, "Delete Account")
        // A1
        XCTAssertEqual(SettingsCopy.deleteAccountTitle, "Delete Account?")
        XCTAssertEqual(SettingsCopy.deleteAccountLine, "All Sidekicks and data go too.")
        // X1
        XCTAssertEqual(SettingsCopy.accountDeletedLine, "Your account will be deleted within 7 days.")
        XCTAssertEqual(SettingsCopy.ok, "OK")
        // C3
        XCTAssertEqual(SettingsCopy.deleteSidekickTitle("Water"), "Delete Water?")
        XCTAssertEqual(SettingsCopy.sidekickDataLine, "Its data goes too.")
        XCTAssertEqual(SettingsCopy.delete, "Delete")
        XCTAssertEqual(SettingsCopy.cancel, "Cancel")
        XCTAssertEqual(SettingsCopy.done, "Done")
        XCTAssertEqual(SettingsCopy.deleteSidekickLabel("Water"), "Delete Water")
    }

    func testE1ShowsTheFirstLetterOfTheName() {
        XCTAssertEqual(AccountInitial.letter(for: "bhuvan"), "B")
        XCTAssertEqual(AccountInitial.letter(for: "  Priya "), "P")
        XCTAssertEqual(AccountInitial.letter(for: "Émile"), "É")
        XCTAssertEqual(AccountInitial.letter(for: ""), "")
    }
}

// MARK: - Which Sidekicks can be deleted

final class SidekickDeletionTests: XCTestCase {
    func testJessMakeAndTheInboxCannotBeDeletedEveryOtherSidekickCan() {
        XCTAssertFalse(SidekickDeletion.canDelete(jess))
        XCTAssertFalse(SidekickDeletion.canDelete(make))
        XCTAssertFalse(SidekickDeletion.canDelete(inbox))
        XCTAssertFalse(SidekickDeletion.canDelete(SettingsPage.entry))
        XCTAssertTrue(SidekickDeletion.canDelete(water))
        XCTAssertTrue(SidekickDeletion.canDelete(reminders))
        XCTAssertTrue(SidekickDeletion.canDelete(entry("plants", "Plants")))
    }

    func testSettingsHasAnIdNoServerSidekickCanHave() {
        let serverIdPattern = try? Regex("^[a-z0-9-]{1,40}$")
        XCTAssertNotNil(serverIdPattern)
        if let serverIdPattern {
            XCTAssertNil(SettingsPage.id.wholeMatch(of: serverIdPattern))
        }
        XCTAssertTrue(SettingsPage.isSettings(SettingsPage.entry))
        XCTAssertFalse(SettingsPage.isSettings(water))
    }
}

// MARK: - The press-and-hold arrangement

@MainActor
final class HomeArrangementTests: XCTestCase {
    func testATapOpensATileUntilTheTilesJiggleThenDoesNothing() {
        let arrangement = HomeArrangement()
        var opened: [String] = []
        var jessOpened = 0
        func open(_ sidekick: SidekickEntry) {
            opened.append(sidekick.id)
        }
        func openJess() {
            jessOpened += 1
        }
        arrangement.openSidekick = open
        arrangement.tapped(water, openJess: openJess)
        arrangement.tapped(jess, openJess: openJess)
        XCTAssertEqual(opened, ["water"])
        XCTAssertEqual(jessOpened, 1)

        arrangement.startArranging()
        XCTAssertTrue(arrangement.isArranging)
        arrangement.tapped(water, openJess: openJess)
        arrangement.tapped(jess, openJess: openJess)
        XCTAssertEqual(opened, ["water"], "a tap while jiggling opens nothing")
        XCTAssertEqual(jessOpened, 1)

        arrangement.stopArranging()
        XCTAssertFalse(arrangement.isArranging)
        arrangement.tapped(water, openJess: openJess)
        XCTAssertEqual(opened, ["water", "water"])
    }

    func testTheMinusShowsOnlyWhileJigglingAndNeverOnJessMakeOrTheInbox() {
        let arrangement = HomeArrangement()
        XCTAssertFalse(arrangement.showsMinus(on: water))
        arrangement.startArranging()
        XCTAssertTrue(arrangement.showsMinus(on: water))
        XCTAssertTrue(arrangement.showsMinus(on: reminders))
        XCTAssertFalse(arrangement.showsMinus(on: jess))
        XCTAssertFalse(arrangement.showsMinus(on: make))
        XCTAssertFalse(arrangement.showsMinus(on: inbox))
    }

    func testTheHomeScreenWiresTheGridSettingsAndTheDeleteSheet() throws {
        let app = try String(contentsOf: settingsShellRoot.appending(path: "Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains(".environment(arrangement)"), "the grid gets the press-and-hold state")
        XCTAssertTrue(app.contains("HomeTopBar(userName: userName"), "E1 sits on the home grid")
        XCTAssertTrue(app.contains("router.path.append(SettingsPage.entry)"), "the initial pushes Settings")
        XCTAssertTrue(app.contains("SettingsView(userName: userName"))
        XCTAssertTrue(app.contains("SidekickDeleteSheet(sidekick: sidekick, account: account"), "the minus opens C3")
        XCTAssertTrue(app.contains("beforeRestore: adoptAccount(user)"), "the account adopts the store before its restore")
        let grid = try String(contentsOf: settingsShellRoot.appending(path: "Midas/SidekickHomeGrid.swift"), encoding: .utf8)
        XCTAssertTrue(grid.contains(".onLongPressGesture(minimumDuration: 0.5, perform: startArranging)"))
        XCTAssertTrue(grid.contains("HomeTileJiggle(isOn: isArranging"))
        let settings = try String(contentsOf: settingsShellRoot.appending(path: "Midas/SettingsView.swift"), encoding: .utf8)
        XCTAssertTrue(settings.contains("SwipeBackEnabler()"), "Settings goes home by the left-edge swipe")
        XCTAssertFalse(settings.contains("chevron.left"), "no back arrow")
    }
}

// MARK: - The server calls

final class AccountAPIRequestTests: XCTestCase {
    private let origin = URL(string: "https://midas-api.example.dev")!

    func testDeletingASidekickIsADeleteOfItsPathWithTheSession() throws {
        let request = try RemoteAccountAPI.removeSidekickRequest(platformOrigin: origin, sidekickId: "water", token: "t1")
        XCTAssertEqual(request.httpMethod, "DELETE")
        XCTAssertEqual(request.url?.absoluteString, "https://midas-api.example.dev/sidekicks/water")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t1")
    }

    func testSignOutAndTheDeletionRequestArePosts() throws {
        let signOut = try RemoteAccountAPI.accountRequest(platformOrigin: origin, path: "account/sign-out", token: "t1")
        XCTAssertEqual(signOut.httpMethod, "POST")
        XCTAssertEqual(signOut.url?.absoluteString, "https://midas-api.example.dev/account/sign-out")
        XCTAssertEqual(signOut.value(forHTTPHeaderField: "Authorization"), "Bearer t1")
        let deletion = try RemoteAccountAPI.accountRequest(platformOrigin: origin, path: "account/delete-request", token: "t1")
        XCTAssertEqual(deletion.url?.absoluteString, "https://midas-api.example.dev/account/delete-request")
        let source = try String(contentsOf: settingsShellRoot.appending(path: "Midas/AccountAPI.swift"), encoding: .utf8)
        XCTAssertTrue(source.contains("path: \"account/sign-out\""))
        XCTAssertTrue(source.contains("path: \"account/delete-request\""))
    }

    func testNoSessionSendsNothing() {
        XCTAssertThrowsError(try RemoteAccountAPI.removeSidekickRequest(platformOrigin: origin, sidekickId: "water", token: nil)) { error in
            XCTAssertEqual(error as? AccountAPIError, .notSignedIn)
        }
        XCTAssertThrowsError(try RemoteAccountAPI.accountRequest(platformOrigin: origin, path: "account/sign-out", token: nil)) { error in
            XCTAssertEqual(error as? AccountAPIError, .notSignedIn)
        }
    }

    func testStatusesMapToTheirErrors() {
        XCTAssertNoThrow(try RemoteAccountAPI.check(status: 200))
        XCTAssertNoThrow(try RemoteAccountAPI.check(status: 201))
        XCTAssertThrowsError(try RemoteAccountAPI.check(status: 401)) { error in
            XCTAssertEqual(error as? AccountAPIError, .notSignedIn)
        }
        XCTAssertThrowsError(try RemoteAccountAPI.check(status: 404)) { error in
            XCTAssertEqual(error as? AccountAPIError, .noSuchSidekick)
        }
        XCTAssertThrowsError(try RemoteAccountAPI.check(status: 500)) { error in
            XCTAssertEqual(error as? AccountAPIError, .server(status: 500))
        }
    }
}

// MARK: - The records on the phone

@MainActor
final class LocalRecordStoreAccountTests: XCTestCase {
    private func storeWithRecords(fileURL: URL) throws -> LocalRecordStore {
        let store = LocalRecordStore(fileURL: fileURL)
        try store.set(sidekickId: "water", key: "drink:1", value: .object(["ml": .number(250)]))
        try store.set(sidekickId: "water", key: "drink:2", value: .object(["ml": .number(300)]))
        try store.set(sidekickId: "reminders", key: "reminder:a", value: .object(["title": .string("Call mum")]))
        return store
    }

    func testForgettingASidekickTakesItsRecordsOutboxAndRefusalsOnly() throws {
        let fileURL = temporaryFile("records.json")
        let store = try storeWithRecords(fileURL: fileURL)
        var waterOpIds: [String] = []
        for pendingOp in store.pendingOps() where pendingOp.sidekickId == "water" {
            waterOpIds.append(pendingOp.opId)
        }
        try store.markRefused(reasonsByOpId: [waterOpIds[0]: "does not fit"])
        XCTAssertEqual(store.refusedOpCount, 1)
        var heard: [LocalRecordChange] = []
        func hear(_ change: LocalRecordChange) {
            heard.append(change)
        }
        store.addChangeObserver(hear)

        try store.forgetSidekick("water")

        XCTAssertTrue(store.query(sidekickId: "water", keyPrefix: "").isEmpty)
        XCTAssertEqual(store.query(sidekickId: "reminders", keyPrefix: "").count, 1)
        var outboxSidekicks: [String] = []
        for pendingOp in store.pendingOps() {
            outboxSidekicks.append(pendingOp.sidekickId)
        }
        XCTAssertEqual(outboxSidekicks, ["reminders"], "no delete ops queued: the server appended them")
        XCTAssertEqual(store.refusedOpCount, 0)
        XCTAssertEqual(heard, [LocalRecordChange(sidekickId: "water", key: "drink:1"), LocalRecordChange(sidekickId: "water", key: "drink:2")])

        let reopened = LocalRecordStore(fileURL: fileURL)
        XCTAssertNil(reopened.get(sidekickId: "water", key: "drink:1"), "kept on disk")
        XCTAssertNotNil(reopened.get(sidekickId: "reminders", key: "reminder:a"))
    }

    func testTheFirstAccountAdoptsTheStoreAsItIsAndKeepsItOnTheNextSignIn() throws {
        let fileURL = temporaryFile("records.json")
        let store = try storeWithRecords(fileURL: fileURL)
        try store.markInitialPullCompleted()
        XCTAssertNil(store.ownerUserId, "a store from before sign-out has no owner")
        XCTAssertFalse(try store.adoptOwner("u-priya"))
        XCTAssertEqual(store.ownerUserId, "u-priya")
        XCTAssertNotNil(store.get(sidekickId: "water", key: "drink:1"), "nothing lost on the update")
        XCTAssertFalse(try store.adoptOwner("u-priya"))
        XCTAssertEqual(store.pendingOps().count, 3)
        XCTAssertTrue(store.hasCompletedInitialPull)
        XCTAssertEqual(LocalRecordStore(fileURL: fileURL).ownerUserId, "u-priya", "kept on disk")
    }

    func testAnotherAccountStartsWithAnEmptyStoreAndAFullRestore() throws {
        let fileURL = temporaryFile("records.json")
        let store = try storeWithRecords(fileURL: fileURL)
        try store.adoptOwner("u-priya")
        try store.applyRemote(ops: [], lastSeq: 41)
        try store.markInitialPullCompleted()

        XCTAssertTrue(try store.adoptOwner("u-sam"))

        XCTAssertEqual(store.ownerUserId, "u-sam")
        XCTAssertTrue(store.query(sidekickId: "water", keyPrefix: "").isEmpty)
        XCTAssertTrue(store.query(sidekickId: "reminders", keyPrefix: "").isEmpty)
        XCTAssertTrue(store.pendingOps().isEmpty, "Priya's changes never upload as Sam's")
        XCTAssertEqual(store.lastPulledSeq, 0)
        XCTAssertFalse(store.hasCompletedInitialPull, "Sam's records are restored first")
        let reopened = LocalRecordStore(fileURL: fileURL)
        XCTAssertEqual(reopened.ownerUserId, "u-sam")
        XCTAssertTrue(reopened.pendingOps().isEmpty)
    }

    func testDeleteAccountErasesEverythingAndTheOwner() throws {
        let fileURL = temporaryFile("records.json")
        let store = try storeWithRecords(fileURL: fileURL)
        try store.adoptOwner("u-priya")
        var heardCount = 0
        func hear(_ change: LocalRecordChange) {
            heardCount += 1
        }
        store.addChangeObserver(hear)
        try store.eraseAll()
        XCTAssertNil(store.ownerUserId)
        XCTAssertTrue(store.queryAllSidekicks(keyPrefix: "").isEmpty)
        XCTAssertTrue(store.pendingOps().isEmpty)
        XCTAssertEqual(heardCount, 3, "pages, widgets and notifications hear every record go")
        // The next account adopts the empty store without another erase
        XCTAssertFalse(try store.adoptOwner("u-new"))
    }

    func testAStoreFileFromBeforeOwnersStillOpens() throws {
        let fileURL = temporaryFile("records.json")
        let oldFile = #"{"formatVersion":2,"records":{"water":{"drink:1":{"ml":250}}},"outbox":[],"lastPulledSeq":7,"hasCompletedInitialPull":true}"#
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(oldFile.utf8).write(to: fileURL)
        let store = LocalRecordStore(fileURL: fileURL)
        XCTAssertNil(store.ownerUserId)
        XCTAssertEqual(store.get(sidekickId: "water", key: "drink:1"), .object(["ml": .number(250)]))
        XCTAssertEqual(store.lastPulledSeq, 7)
        XCTAssertTrue(store.hasCompletedInitialPull)
    }
}

// MARK: - The list on the phone

@Sendable
private func skipSettingsWidgetReload() {}

private final class FixedListings: SidekickDirectoryFetching, @unchecked Sendable {
    let listings: [SidekickListing]

    init(listings: [SidekickListing]) {
        self.listings = listings
    }

    func fetchSidekicks() async throws -> [SidekickEntry] {
        var entries: [SidekickEntry] = []
        for listing in listings {
            entries.append(listing.entry)
        }
        return entries
    }

    func fetchListings() async throws -> [SidekickListing] {
        listings
    }
}

@MainActor
final class SidekickDirectoryRemovalTests: XCTestCase {
    private func loadedDirectory(cacheURL: URL) async -> SidekickDirectory {
        let listings = [
            SidekickListing(entry: water, types: .object(["water.drink": .object([:])]), agent: .object(["description": .string("Water")])),
            SidekickListing(entry: reminders, types: nil),
        ]
        let writer = SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: skipSettingsWidgetReload)
        let directory = SidekickDirectory(cacheFileURL: cacheURL, fetcher: FixedListings(listings: listings), sharedListWriter: writer)
        await directory.refresh()
        return directory
    }

    func testADeletedSidekickLeavesTheListAtOnceAndOnDisk() async {
        let cacheURL = temporaryFile("directory.json")
        let directory = await loadedDirectory(cacheURL: cacheURL)
        directory.removeEntry(withId: "water")
        XCTAssertEqual(directory.entries, [reminders])
        XCTAssertNil(directory.types(forSidekickId: "water"))
        XCTAssertNil(directory.agent(forSidekickId: "water"), "jess no longer offers its tools")
        let writer = SharedSidekickListWriter(fileURL: nil, now: Date.init, reloadWidgets: skipSettingsWidgetReload)
        let reopened = SidekickDirectory(cacheFileURL: cacheURL, fetcher: FixedListings(listings: []), sharedListWriter: writer)
        XCTAssertEqual(reopened.entries, [reminders])
    }

    func testClearingEmptiesTheListUntilTheServerAnswers() async {
        let cacheURL = temporaryFile("directory.json")
        let directory = await loadedDirectory(cacheURL: cacheURL)
        XCTAssertTrue(directory.hasLoadedFromServer)
        directory.clear()
        XCTAssertTrue(directory.entries.isEmpty)
        XCTAssertFalse(directory.hasLoadedFromServer)
        XCTAssertNil(directory.agent(forSidekickId: "water"))
    }
}

// MARK: - Sign out in the AuthModel

private final class SettingsMemorySessionStore: SessionStore, @unchecked Sendable {
    var token: String?
    init(token: String?) { self.token = token }
    func loadToken() -> String? { token }
    func saveToken(_ token: String) { self.token = token }
    func clearToken() { token = nil }
}

private struct SignedInAuthAPI: AuthAPI {
    func registrationChallenge(name: String) async throws -> RegistrationChallenge {
        throw AuthAPIError.badResponse
    }

    func completeRegistration(challengeId: String, registration: PasskeyRegistration) async throws -> AuthSession {
        throw AuthAPIError.badResponse
    }

    func loginChallenge() async throws -> LoginChallenge {
        throw AuthAPIError.badResponse
    }

    func completeLogin(challengeId: String, assertion: PasskeyAssertion) async throws -> AuthSession {
        throw AuthAPIError.badResponse
    }

    func currentUser(token: String) async throws -> MidasUser {
        MidasUser(id: "u-priya", name: "Priya")
    }
}

private struct NoPasskeys: PasskeyAuthenticating {
    func createPasskey(for challenge: RegistrationChallenge) async throws -> PasskeyRegistration {
        throw PasskeyError.canceled
    }

    func signIn(with challenge: LoginChallenge) async throws -> PasskeyAssertion {
        throw PasskeyError.canceled
    }
}

@MainActor
final class AuthSignOutTests: XCTestCase {
    func testSignOutForgetsTheTokenAndShowsTheWelcome() async {
        let store = SettingsMemorySessionStore(token: "t1")
        let auth = AuthModel(api: SignedInAuthAPI(), store: store, passkeys: NoPasskeys())
        await auth.start()
        XCTAssertEqual(auth.user, MidasUser(id: "u-priya", name: "Priya"))
        auth.signOut()
        XCTAssertEqual(auth.state, .signedOut)
        XCTAssertNil(auth.user)
        XCTAssertNil(store.token)
    }
}

// MARK: - The flows, step by step

@MainActor
private final class StepLog {
    var steps: [String] = []
    var removeError: Error?
    var signOutError: Error?
    var deletionError: Error?
}

@MainActor
private func makeCenter(_ log: StepLog) -> AccountCenter {
    func syncNow() async {
        log.steps.append("sync")
    }
    func removeSidekickOnServer(_ sidekickId: String) async throws {
        log.steps.append("server delete \(sidekickId)")
        if let error = log.removeError {
            throw error
        }
    }
    func forgetSidekickLocally(_ sidekickId: String) {
        log.steps.append("forget \(sidekickId)")
    }
    func afterRecordsLeft() async {
        log.steps.append("catch up")
    }
    func signOutOnServer() async throws {
        log.steps.append("server sign out")
        if let error = log.signOutError {
            throw error
        }
    }
    func requestDeletionOnServer() async throws {
        log.steps.append("server deletion request")
        if let error = log.deletionError {
            throw error
        }
    }
    func eraseAccountLocally() {
        log.steps.append("erase")
    }
    func goHome() {
        log.steps.append("home")
    }
    let dependencies = AccountCenter.Dependencies(syncNow: syncNow, removeSidekickOnServer: removeSidekickOnServer, forgetSidekickLocally: forgetSidekickLocally, afterRecordsLeft: afterRecordsLeft, signOutOnServer: signOutOnServer, requestDeletionOnServer: requestDeletionOnServer, eraseAccountLocally: eraseAccountLocally, goHome: goHome)
    let center = AccountCenter(dependencies: dependencies)
    func endSession() {
        log.steps.append("signed out")
    }
    center.endSession = endSession
    return center
}

@MainActor
final class AccountCenterTests: XCTestCase {
    func testDeletingASidekickBacksUpThenDeletesOnTheServerThenOnThePhone() async {
        let log = StepLog()
        let center = makeCenter(log)
        let isDeleted = await center.deleteSidekick(water)
        XCTAssertTrue(isDeleted)
        XCTAssertEqual(log.steps, ["sync", "server delete water", "forget water", "catch up"])
        XCTAssertNil(center.sidekickDeleteError)
        XCTAssertFalse(center.isDeletingSidekick)
    }

    func testJessMakeAndTheInboxAreNeverSentForDeletion() async {
        let log = StepLog()
        let center = makeCenter(log)
        for sidekick in [jess, make, inbox] {
            let isDeleted = await center.deleteSidekick(sidekick)
            XCTAssertFalse(isDeleted)
        }
        XCTAssertEqual(log.steps, [])
    }

    func testOfflineTheSidekickAndItsDataStayAndC3SaysSo() async {
        let log = StepLog()
        log.removeError = URLError(.notConnectedToInternet)
        let center = makeCenter(log)
        let isDeleted = await center.deleteSidekick(water)
        XCTAssertFalse(isDeleted)
        XCTAssertEqual(log.steps, ["sync", "server delete water"], "nothing leaves the phone")
        XCTAssertEqual(center.sidekickDeleteError, "Can’t connect. Try again.")
        center.clearSidekickDeleteError()
        XCTAssertNil(center.sidekickDeleteError)
    }

    func testASidekickTheServerAlreadyLetGoGoesFromThePhoneToo() async {
        let log = StepLog()
        log.removeError = AccountAPIError.noSuchSidekick
        let center = makeCenter(log)
        let isDeleted = await center.deleteSidekick(water)
        XCTAssertTrue(isDeleted)
        XCTAssertEqual(log.steps, ["sync", "server delete water", "forget water", "catch up"])
    }

    func testSignOutBacksUpEndsTheSessionAndGoesToTheWelcomeEvenOffline() async {
        let log = StepLog()
        let center = makeCenter(log)
        await center.signOut()
        XCTAssertEqual(log.steps, ["sync", "server sign out", "home", "signed out"])

        let offlineLog = StepLog()
        offlineLog.signOutError = URLError(.notConnectedToInternet)
        let offlineCenter = makeCenter(offlineLog)
        await offlineCenter.signOut()
        XCTAssertEqual(offlineLog.steps, ["sync", "server sign out", "home", "signed out"])
    }

    func testDeleteAccountRecordsTheRequestErasesThePhoneShowsX1ThenTheWelcome() async {
        let log = StepLog()
        let center = makeCenter(log)
        await center.requestAccountDeletion()
        XCTAssertEqual(log.steps, ["server deletion request", "erase"])
        XCTAssertTrue(center.showsAccountDeleted, "X1")
        XCTAssertNil(center.accountDeletionError)
        XCTAssertFalse(center.isRequestingDeletion)

        center.finishAccountDeletion()
        XCTAssertFalse(center.showsAccountDeleted)
        XCTAssertEqual(log.steps, ["server deletion request", "erase", "home", "signed out"])
    }

    func testDeleteAccountOfflineKeepsEverythingAndSaysSo() async {
        let log = StepLog()
        log.deletionError = URLError(.notConnectedToInternet)
        let center = makeCenter(log)
        await center.requestAccountDeletion()
        XCTAssertEqual(log.steps, ["server deletion request"])
        XCTAssertFalse(center.showsAccountDeleted)
        XCTAssertEqual(center.accountDeletionError, "Can’t connect. Try again.")
    }

    func testTheLiveStepsTouchTheRealStoreListAndSession() throws {
        let services = try String(contentsOf: settingsShellRoot.appending(path: "Midas/ShellServices.swift"), encoding: .utf8)
        XCTAssertTrue(services.contains("try? store.forgetSidekick(sidekickId)"))
        XCTAssertTrue(services.contains("directory.removeEntry(withId: sidekickId)"))
        XCTAssertTrue(services.contains("await notificationEngine.refresh()"), "a deleted Reminders' notifications are taken off")
        XCTAssertTrue(services.contains("try? store.eraseAll()"))
        XCTAssertTrue(services.contains("store.adoptOwner(userId)"))
        let app = try String(contentsOf: settingsShellRoot.appending(path: "Midas/MidasApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("ShellServices.shared.account.endSession = auth.signOut"))
    }
}

// MARK: - The screens draw

@MainActor
final class SettingsScreensRenderTests: XCTestCase {
    private func ignore() {}

    func testSettingsC3X1AndTheTopBarRenderInBothModes() {
        let center = makeCenter(StepLog())
        for scheme in [ColorScheme.light, .dark] {
            let settings = SettingsView(userName: "Priya", sidekicks: [jess, make, water, reminders], account: center).frame(width: 402, height: 874).environment(\.colorScheme, scheme)
            XCTAssertNotNil(ImageRenderer(content: settings).uiImage, "Settings in \(scheme)")
            let sheet = SidekickDeleteSheet(sidekick: water, account: center, onClose: ignore).frame(width: 402, height: SidekickDeleteSheet.height).environment(\.colorScheme, scheme)
            XCTAssertNotNil(ImageRenderer(content: sheet).uiImage, "C3 in \(scheme)")
            let deleted = AccountDeletedView(onOK: ignore).frame(width: 402, height: 874).environment(\.colorScheme, scheme)
            XCTAssertNotNil(ImageRenderer(content: deleted).uiImage, "X1 in \(scheme)")
            for isArranging in [false, true] {
                let bar = HomeTopBar(userName: "Priya", isArranging: isArranging, onOpenSettings: ignore, onDone: ignore).frame(width: 402).environment(\.colorScheme, scheme)
                XCTAssertNotNil(ImageRenderer(content: bar).uiImage)
            }
            let tile = SidekickHomeTile(sidekick: water, onDelete: ignore).environment(\.colorScheme, scheme)
            XCTAssertNotNil(ImageRenderer(content: tile).uiImage, "a tile with its minus in \(scheme)")
        }
    }
}
