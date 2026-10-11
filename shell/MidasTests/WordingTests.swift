import XCTest
@testable import Midas

/// On-screen words follow docs/WRITING.md: say the action, then stop (founder approved the
/// wording mockup docs/mockups/wording-2026-10-10.html on 2026-10-10).
final class WordingTests: XCTestCase {

    // MARK: Import sheet: a title and the buttons, nothing else

    func testImportSheetExplainingLinesNeverComeBack() throws {
        let sheetSource = try shellSource(named: "AppleRemindersImportSheet.swift")

        let removedLines = [
            "Midas reads your lists and reminders",
            "Nothing in Apple Reminders is changed",
            "Already brought them in from your Mac",
            "Anything that changed on your iPhone is updated",
            "AppleRemindersImportCopy.explanation",
            "AppleRemindersImportCopy.reconcileNote",
        ]
        for removedLine in removedLines {
            XCTAssertFalse(sheetSource.contains(removedLine), "Import sheet shows a removed line again: \(removedLine)")
        }
    }

    func testImportSheetShowsOnlyTheTitleAndTheButtonLabel() throws {
        let sheetSource = try shellSource(named: "AppleRemindersImportSheet.swift")

        // Any new Text(...) on the sheet would be a line beyond the title and the button
        let textViewCount = sheetSource.components(separatedBy: "Text(").count - 1
        XCTAssertEqual(textViewCount, 2)
        XCTAssertTrue(sheetSource.contains("Text(AppleRemindersImportCopy.title)"))
        XCTAssertTrue(sheetSource.contains("Text(AppleRemindersImportCopy.continueButton)"))
    }

    func testImportSheetWords() {
        XCTAssertEqual(AppleRemindersImportCopy.title, "Import Apple Reminders")
        XCTAssertEqual(AppleRemindersImportCopy.continueButton, "Continue")
        XCTAssertEqual(AppleRemindersImportCopy.notNowButton, "Not Now")
        XCTAssertEqual(AppleRemindersImportCopy.workingLabel, "Importing…")
    }

    // MARK: Welcome, restore, home

    func testWelcomeHasNoQuestionLine() throws {
        let welcomeSource = try shellSource(named: "WelcomeView.swift")

        XCTAssertFalse(welcomeSource.contains("What should we call you?"))
        XCTAssertEqual(WelcomeCopy.namePlaceholder, "Name")
    }

    func testWelcomeErrorsNameWhatFailed() {
        XCTAssertEqual(AuthCopy.cannotConnect, "Can’t connect. Try again.")
        XCTAssertEqual(AuthCopy.nameMissing, "Enter a name.")
        XCTAssertEqual(AuthCopy.unknownPasskey, "No account for this passkey.")
        XCTAssertEqual(AuthCopy.createAccountFailed, "Can’t create account. Try again.")
        XCTAssertEqual(AuthCopy.signInFailed, "Can’t sign in. Try again.")
    }

    func testNoGenericErrorOrTechnicalWordsInTheShell() throws {
        let sources = try ["AuthModel.swift", "MidasApp.swift", "WelcomeView.swift"].map(shellSource(named:))

        for source in sources {
            XCTAssertFalse(source.contains("Something went wrong"))
            XCTAssertFalse(source.contains("safe on the server"))
            XCTAssertFalse(source.contains("Restoring your records"))
            XCTAssertFalse(source.contains("Couldn't reach Midas"))
        }
    }

    func testRestoreAndHomeWords() {
        XCTAssertEqual(RestoreCopy.working, "Restoring…")
        XCTAssertEqual(RestoreCopy.failedTitle, "Can’t Connect")
        XCTAssertEqual(RestoreCopy.retryButton, "Try Again")
        XCTAssertEqual(HomeCopy.empty, "No Sidekicks")
    }

    // MARK: Notification buttons

    func testNotificationButtonsAreTitleCase() {
        XCTAssertEqual(ReminderAction.done.buttonTitle, "Done")
        XCTAssertEqual(ReminderAction.snoozeTenMinutes.buttonTitle, "Snooze 10 Minutes")
        XCTAssertEqual(ReminderAction.snoozeOneHour.buttonTitle, "Snooze 1 Hour")
        XCTAssertEqual(ReminderAction.snoozeUntilTomorrow.buttonTitle, "Snooze Until Tomorrow")
    }

    // MARK: Helpers

    private func shellSource(named fileName: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory.deletingLastPathComponent().appending(path: "Midas").appending(path: fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}
