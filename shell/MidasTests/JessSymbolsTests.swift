import AppIntents
import UIKit
import XCTest
@testable import Midas

// jess outside the app, founder 2026-10-23 (docs/briefs/jess-look-lead.md): controls show the written
// "Jess" as our own symbol; the App Shortcut shows Apple's sound wave on a grayBlue tile, with an ink
// Spotlight platter.
@MainActor
final class JessSymbolsTests: XCTestCase {
    func testTheControlSymbolIsTheWrittenJess() throws {
        let symbol = try XCTUnwrap(UIImage(named: JessSymbols.control), "JessSymbol is missing from Shared.xcassets")
        XCTAssertTrue(symbol.isSymbolImage, "JessSymbol must be a symbol, or the control cannot show it")
        // The whole word, not the J alone or a microphone: much wider than tall.
        XCTAssertGreaterThan(symbol.size.width / symbol.size.height, 1.2)
    }

    func testTheControlUsesTheJessSymbol() throws {
        let source = try sourceFile("MidasWidgets/VoiceReminderControl.swift")
        XCTAssertTrue(source.contains("image: JessSymbols.control"))
        XCTAssertFalse(source.contains("systemImage: \"mic\""))
    }

    func testTheShortcutShowsAppleSoundWave() throws {
        XCTAssertEqual(JessSymbols.shortcut, "waveform")
        XCTAssertNotNil(UIImage(systemName: JessSymbols.shortcut))
        // App Intents takes only a literal there, so check the literal matches the constant.
        let source = try sourceFile("Midas/MidasShortcuts.swift")
        XCTAssertTrue(source.contains("systemImageName: \"\(JessSymbols.shortcut)\""))
    }

    func testTheShortcutTileIsGrayBlue() {
        XCTAssertEqual(MidasShortcuts.shortcutTileColor, .grayBlue)
    }

    func testTheSpotlightPlatterIsInkWithAWhiteSymbol() throws {
        let icons = try XCTUnwrap(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try XCTUnwrap(icons["CFBundlePrimaryIcon"] as? [String: Any])
        XCTAssertEqual(primary["NSAppIconComplementingColorNames"] as? [String], [JessSymbols.platterColour])
        XCTAssertEqual(primary["NSAppIconActionTintColorName"] as? String, JessSymbols.platterTint)
        // The app icon is still there next to the platter colours.
        XCTAssertEqual(primary["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertEqual(try rgb(of: JessSymbols.platterColour), [17, 17, 17])
        XCTAssertEqual(try rgb(of: JessSymbols.platterTint), [255, 255, 255])
    }

    // MARK: - Helpers

    private func sourceFile(_ path: String) throws -> String {
        let shell = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: shell.appendingPathComponent(path), encoding: .utf8)
    }

    private func rgb(of colourName: String) throws -> [Int] {
        let colour = try XCTUnwrap(UIColor(named: colourName), "\(colourName) is missing from Assets.xcassets")
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
        return [red, green, blue].map { channel in Int((channel * 255).rounded()) }
    }
}
