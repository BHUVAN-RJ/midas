import XCTest
@testable import Midas

final class SidekickContentSecurityPolicyTests: XCTestCase {
    private let platformOrigin = URL(string: "https://midas-api.midas-backend.workers.dev")!

    func testPolicyPinsScriptsToHashesAndConnectToPlatform() {
        let policy = SidekickContentSecurityPolicy.policy(scriptHashes: ["'sha256-AAA='"], platformOrigin: platformOrigin)
        XCTAssertTrue(policy.contains("default-src 'none'"))
        XCTAssertTrue(policy.contains("script-src 'sha256-AAA='"))
        XCTAssertTrue(policy.contains("connect-src https://midas-api.midas-backend.workers.dev"))
        XCTAssertFalse(policy.contains("unsafe-eval"))
    }

    func testNoHashesMeansNoScripts() {
        let policy = SidekickContentSecurityPolicy.policy(scriptHashes: [], platformOrigin: platformOrigin)
        XCTAssertTrue(policy.contains("script-src 'none'"))
    }

    func testHeaderParsingDropsAnythingThatIsNotAHashSource() {
        let header = "'sha256-abc+/12=' 'unsafe-inline' * 'sha256-XYZ' https://evil.example"
        let hashes = SidekickContentSecurityPolicy.validScriptHashes(fromHeader: header)
        XCTAssertEqual(hashes, ["'sha256-abc+/12='", "'sha256-XYZ'"])
    }

    func testMissingHeaderGivesNoHashes() {
        XCTAssertEqual(SidekickContentSecurityPolicy.validScriptHashes(fromHeader: nil), [])
    }
}
