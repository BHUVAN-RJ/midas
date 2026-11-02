import XCTest

// App Store Connect warned on a Midas Test upload (2026-11-02) that default.metallib held Metal
// shader source. The Test config archives TestFlight builds and is debug-based, so it must turn
// Metal debug info off, like Release.
final class MetalDebugInfoConfigTests: XCTestCase {
    func testTheTestConfigLeavesShaderSourceOutOfUploads() throws {
        let testsFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let projectFile = testsFolder.deletingLastPathComponent().appendingPathComponent("project.yml")
        let projectText = try String(contentsOf: projectFile, encoding: .utf8)
        let testConfigStart = try XCTUnwrap(projectText.range(of: "  configs:\n    Test:\n"))
        let targetsStart = try XCTUnwrap(projectText.range(of: "\ntargets:"))
        let testConfigText = projectText[testConfigStart.upperBound..<targetsStart.lowerBound]
        XCTAssertTrue(testConfigText.contains("MTL_ENABLE_DEBUG_INFO: \"NO\""))
    }
}
