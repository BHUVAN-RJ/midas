import XCTest

/// Guideline 4.7.2: the shell exposes no native API to Sidekicks. A script message handler or
/// an injected user script anywhere in the app source fails this test.
final class NoNativeBridgeTests: XCTestCase {
    private static let forbiddenSymbols = [
        "WKScriptMessageHandler",
        "addScriptMessageHandler",
        "userContentController.add",
        "addUserScript",
        "WKUserScript",
    ]

    func testAppSourceRegistersNoBridge() throws {
        let testsDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let appSourceDirectory = testsDirectory.deletingLastPathComponent().appending(path: "Midas")
        let sourceFiles = try FileManager.default.contentsOfDirectory(at: appSourceDirectory, includingPropertiesForKeys: nil)
        var swiftFileCount = 0

        for sourceFile in sourceFiles where sourceFile.pathExtension == "swift" {
            swiftFileCount += 1
            let sourceText = try String(contentsOf: sourceFile, encoding: .utf8)
            for forbiddenSymbol in Self.forbiddenSymbols {
                XCTAssertFalse(sourceText.contains(forbiddenSymbol), "\(sourceFile.lastPathComponent) uses \(forbiddenSymbol)")
            }
        }
        XCTAssertGreaterThan(swiftFileCount, 0, "no app sources found at \(appSourceDirectory.path)")
    }
}
