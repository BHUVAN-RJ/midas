import XCTest
@testable import Midas

/// iOS kills an app that starts the microphone or speech recognition without these Info.plist
/// strings. Their wording is the founder's and app-wide, because the same prompts serve the repair
/// layer and the voice assistant: speech recognition from 2026-10-13, the microphone from build 22
/// (founder, 2026-11-01, docs/PRODUCT.md Permissions; guideline 5.1.1(ii)). Checks the built
/// app's plist.
final class VoicePermissionConfigTests: XCTestCase {
    func testInfoPlistAsksForTheMicrophoneInTheFoundersWords() {
        let microphoneText = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        XCTAssertEqual(microphoneText, "Midas listens when you speak a request or an edit.")
    }

    func testInfoPlistAsksForSpeechRecognitionInTheFoundersWords() {
        let speechText = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String
        XCTAssertEqual(speechText, "Midas turns your voice into text on this iPhone.")
    }
}
