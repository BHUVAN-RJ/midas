import XCTest
@testable import Midas

/// Founder, 2026-10-15: Midas asks for the microphone and speech recognition when it opens, so
/// no voice feature (repair, Action button voice) stops for prompts, and the repair layer never
/// asks on its own.
final class VoicePermissionsTests: XCTestCase {
    func testFirstLaunchAsksForBothMicrophoneFirst() async {
        let system = FakeVoicePermissionSystem(microphone: .notAsked, speech: .notAsked, grantsWhenAsked: true)
        let state = await VoicePermissions.askAtLaunch(system: system)
        XCTAssertEqual(system.requestOrder, ["microphone", "speech"])
        XCTAssertEqual(state, .granted)
    }

    func testAnsweredPromptsAreNeverShownAgain() async {
        let grantedSystem = FakeVoicePermissionSystem(microphone: .granted, speech: .granted, grantsWhenAsked: true)
        await VoicePermissions.askAtLaunch(system: grantedSystem)
        XCTAssertEqual(grantedSystem.requestOrder, [])

        let deniedSystem = FakeVoicePermissionSystem(microphone: .denied, speech: .denied, grantsWhenAsked: true)
        let deniedState = await VoicePermissions.askAtLaunch(system: deniedSystem)
        XCTAssertEqual(deniedSystem.requestOrder, [])
        XCTAssertEqual(deniedState, .denied)
    }

    func testOnlyTheUnansweredPromptIsShown() async {
        let system = FakeVoicePermissionSystem(microphone: .granted, speech: .notAsked, grantsWhenAsked: true)
        await VoicePermissions.askAtLaunch(system: system)
        XCTAssertEqual(system.requestOrder, ["speech"])
    }

    func testEitherDenialMeansDenied() async {
        let system = FakeVoicePermissionSystem(microphone: .notAsked, speech: .notAsked, grantsWhenAsked: false)
        let state = await VoicePermissions.askAtLaunch(system: system)
        XCTAssertEqual(state, .denied)
        XCTAssertEqual(VoicePermissions.state(system: FakeVoicePermissionSystem(microphone: .granted, speech: .denied, grantsWhenAsked: true)), .denied)
        XCTAssertEqual(VoicePermissions.state(system: FakeVoicePermissionSystem(microphone: .granted, speech: .notAsked, grantsWhenAsked: true)), .notAsked)
    }

    func testMidasAsksOnceSignedInAndTheRepairLayerNeverAsks() throws {
        let appSource = try shellSource(named: "MidasApp.swift")
        XCTAssertTrue(appSource.contains("await VoicePermissions.askAtLaunch()"), "Midas no longer asks at launch")

        let repairFiles = ["RepairSession.swift", "RepairCanvasView.swift", "RepairSpeechTranscriber.swift"]
        for fileName in repairFiles {
            let source = try shellSource(named: fileName)
            XCTAssertFalse(source.contains("requestRecordPermission"), "\(fileName) asks for the microphone")
            XCTAssertFalse(source.contains("requestAuthorization"), "\(fileName) asks for speech recognition")
            XCTAssertFalse(source.contains("askAtLaunch"), "\(fileName) shows the launch prompts")
            XCTAssertFalse(source.contains("RepairPermissionScreen"), "\(fileName) brings back the permission screen")
        }
    }

    private func shellSource(named fileName: String) throws -> String {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let sourceURL = testsDirectory.deletingLastPathComponent().appending(path: "Midas").appending(path: fileName)
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }
}

/// Stands in for iOS: records which prompts were shown and answers them all the same way.
private final class FakeVoicePermissionSystem: VoicePermissionSystem, @unchecked Sendable {
    private(set) var microphone: VoicePermissionAnswer
    private(set) var speech: VoicePermissionAnswer
    private(set) var requestOrder: [String] = []
    private let grantsWhenAsked: Bool

    init(microphone: VoicePermissionAnswer, speech: VoicePermissionAnswer, grantsWhenAsked: Bool) {
        self.microphone = microphone
        self.speech = speech
        self.grantsWhenAsked = grantsWhenAsked
    }

    func requestMicrophone() async {
        requestOrder.append("microphone")
        microphone = grantsWhenAsked ? .granted : .denied
    }

    func requestSpeech() async {
        requestOrder.append("speech")
        speech = grantsWhenAsked ? .granted : .denied
    }
}
