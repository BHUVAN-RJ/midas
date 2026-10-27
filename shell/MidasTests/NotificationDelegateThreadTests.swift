import XCTest
@testable import Midas

/// Crash 2026-10-26 21:00, Midas Test build 18: a reminder button pressed with Midas in the
/// background aborted the app ("abort() called" in -[UIApplication
/// _performBlockAfterCATransactionCommitSynchronizes:], from the async
/// `userNotificationCenter(_:didReceive:)`). The async form answers iOS from a background thread.
/// The delegate must use the completion-handler form and answer on the main actor.
/// iOS gives no way to build a UNNotificationResponse in a test, so this reads the delegate's source.
final class NotificationDelegateThreadTests: XCTestCase {

    private func delegateSource() throws -> String {
        let shellRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: shellRoot.appending(path: "Midas/ShellServices.swift"), encoding: .utf8)
    }

    func testNoNotificationCallbackUsesTheAsyncForm() throws {
        let source = try delegateSource()
        XCTAssertFalse(source.contains("didReceive response: UNNotificationResponse) async"), "async didReceive answers iOS off the main thread")
        XCTAssertFalse(source.contains("willPresent notification: UNNotification) async"), "async willPresent answers iOS off the main thread")
    }

    func testBothCallbacksAnswerFromTheMainActor() throws {
        let source = try delegateSource()
        let didReceiveStart = try XCTUnwrap(source.range(of: "didReceive response: UNNotificationResponse, withCompletionHandler"))
        let willPresentStart = try XCTUnwrap(source.range(of: "willPresent notification: UNNotification, withCompletionHandler"))
        for start in [didReceiveStart, willPresentStart] {
            // The method's body up to the next callback or helper
            let body = String(source[start.upperBound...].prefix(900))
            let mainActorTask = try XCTUnwrap(body.range(of: "Task { @MainActor in"), "the work runs on the main actor")
            let completionCall = try XCTUnwrap(body.range(of: "completionHandler("), "iOS gets its answer")
            XCTAssertLessThan(mainActorTask.lowerBound, completionCall.lowerBound, "the answer is given inside the main-actor task")
        }
    }
}
