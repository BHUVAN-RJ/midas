import Foundation
import Observation

/// Words of Settings and delete (founder, 2026-10-31; docs/mockups/settings-delete-2026-10-31.html,
/// docs/WRITING.md).
enum SettingsCopy {
    static let sidekicksSection = "Sidekicks"
    static let signOut = "Sign Out"
    static let deleteAccount = "Delete Account"
    static let deleteAccountTitle = "Delete Account?"
    static let deleteAccountLine = "All Sidekicks and data go too."
    static let accountDeletedLine = "Your account will be deleted within 7 days."
    static let ok = "OK"
    static let cancel = "Cancel"
    static let delete = "Delete"
    static let done = "Done"
    static let sidekickDataLine = "Its data goes too."
    static let cannotConnect = "Can’t connect. Try again."

    /// C3's title: "Delete Water?"
    static func deleteSidekickTitle(_ name: String) -> String {
        "Delete \(name)?"
    }

    /// The minus badge's VoiceOver name: "Delete Water"
    static func deleteSidekickLabel(_ name: String) -> String {
        "Delete \(name)"
    }
}

/// Which Sidekicks a person can delete from the home grid: every one but jess, Make and the
/// Inbox, which are built in (founder, 2026-10-31).
enum SidekickDeletion {
    static func canDelete(_ sidekick: SidekickEntry) -> Bool {
        if JessSidekick.isJess(sidekick) || MakeSidekick.isMake(sidekick) || MakeSidekick.isInbox(sidekick) {
            return false
        }
        return !SettingsPage.isSettings(sidekick)
    }
}

/// E1: the person's initial in the small circle at the top right of the home grid.
enum AccountInitial {
    static func letter(for name: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstCharacter = trimmedName.first else {
            return ""
        }
        return String(firstCharacter).uppercased()
    }
}

/// Settings is pushed onto the home grid's stack like a Sidekick (S2, no back arrow: the left-edge
/// swipe goes home). The stack holds SidekickEntry values, so Settings has its own entry, with an
/// id no server Sidekick can have (server ids are lowercase letters, digits and dashes).
enum SettingsPage {
    static let id = "midas.settings"
    static let entry = SidekickEntry(id: id, name: "Settings", symbolName: "gearshape", backgroundHex: "#111111", version: "built-in")

    static func isSettings(_ sidekick: SidekickEntry) -> Bool {
        sidekick.id == id
    }
}

/// Deleting a Sidekick, Sign Out and Delete Account, with their steps in order. The steps are
/// passed in, so the order is checked without a server or a phone.
@MainActor
@Observable
final class AccountCenter {
    struct Dependencies {
        /// Pushes the outbox first, so every change made before the delete is in the history.
        var syncNow: @MainActor () async -> Void
        var removeSidekickOnServer: (String) async throws -> Void
        /// The Sidekick's records and its tile leave the phone.
        var forgetSidekickLocally: @MainActor (String) -> Void
        /// Notifications, widgets and the list catch up after records left.
        var afterRecordsLeft: @MainActor () async -> Void
        var signOutOnServer: () async throws -> Void
        var requestDeletionOnServer: () async throws -> Void
        /// Delete Account: everything of this account leaves the phone.
        var eraseAccountLocally: @MainActor () -> Void
        /// Back to the home grid, so the next sign-in does not open on Settings.
        var goHome: @MainActor () -> Void
    }

    private(set) var isDeletingSidekick = false
    /// Shown in place of C3's line when the delete did not reach the server.
    private(set) var sidekickDeleteError: String?
    private(set) var isRequestingDeletion = false
    /// A1's request did not reach the server: an alert says so.
    var accountDeletionError: String?
    /// X1, "Your account will be deleted within 7 days.", after the server recorded the request.
    var showsAccountDeleted = false

    /// Set by RootView: the AuthModel's sign out.
    @ObservationIgnored var endSession: @MainActor () -> Void = AccountCenter.noSession

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    private static func noSession() {}

    /// C3's Delete. True when the Sidekick is gone (also when the server had already let it go).
    @discardableResult
    func deleteSidekick(_ sidekick: SidekickEntry) async -> Bool {
        guard SidekickDeletion.canDelete(sidekick), !isDeletingSidekick else {
            return false
        }
        isDeletingSidekick = true
        sidekickDeleteError = nil
        defer { isDeletingSidekick = false }
        await dependencies.syncNow()
        do {
            try await dependencies.removeSidekickOnServer(sidekick.id)
        } catch AccountAPIError.noSuchSidekick {
            // Deleted on another phone already: it goes here too
        } catch {
            sidekickDeleteError = SettingsCopy.cannotConnect
            return false
        }
        dependencies.forgetSidekickLocally(sidekick.id)
        await dependencies.afterRecordsLeft()
        return true
    }

    /// C3 opened or closed: an old error line does not carry over.
    func clearSidekickDeleteError() {
        sidekickDeleteError = nil
    }

    /// Sign Out: changes still on the phone go up first, the session ends on the server (best
    /// effort; offline it expires on its own), then the welcome screen. The records stay on the
    /// phone for the same account's next sign-in; another account starts empty
    /// (LocalRecordStore.adoptOwner).
    func signOut() async {
        await dependencies.syncNow()
        try? await dependencies.signOutOnServer()
        dependencies.goHome()
        endSession()
    }

    /// A1's "Delete Account". The server records it and the founder deletes within 7 days; the
    /// phone forgets the account at once and shows X1. A failure shows an alert and keeps
    /// everything.
    func requestAccountDeletion() async {
        guard !isRequestingDeletion else {
            return
        }
        isRequestingDeletion = true
        defer { isRequestingDeletion = false }
        do {
            try await dependencies.requestDeletionOnServer()
        } catch {
            accountDeletionError = SettingsCopy.cannotConnect
            return
        }
        dependencies.eraseAccountLocally()
        showsAccountDeleted = true
    }

    /// X1's OK: the signed-out welcome.
    func finishAccountDeletion() {
        showsAccountDeleted = false
        dependencies.goHome()
        endSession()
    }
}
