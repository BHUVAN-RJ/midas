import XCTest
@testable import Midas

/// iOS kills an app that starts the microphone or speech recognition without these Info.plist
/// strings. Their wording is the founder's (2026-10-13): app-wide and generic, because the same
/// prompts serve the repair layer now and the voice assistant later. Checks the built app's plist.
final class VoicePermissionConfigTests: XCTestCase {
    func testInfoPlistAsksForTheMicrophoneInTheFoundersWords() {
        let microphoneText = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        XCTAssertEqual(microphoneText, "Midas uses the microphone for voice features.")
    }

    func testInfoPlistAsksForSpeechRecognitionInTheFoundersWords() {
        let speechText = Bundle.main.object(forInfoDictionaryKey: "NSSpeechRecognitionUsageDescription") as? String
        XCTAssertEqual(speechText, "Midas turns your voice into text on this iPhone.")
    }
}
