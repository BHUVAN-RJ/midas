import SwiftUI
import UIKit
import XCTest
@testable import Midas

// jess's one icon everywhere (founder, 2026-10-26): the written "Jess" tile, not the catalog's
// `circle.circle.fill` on black, wherever a Sidekick icon is drawn: the home grid, widget folders,
// Make. The tile image lives in Shared.xcassets, so the widget extension carries it too.
final class JessIconEverywhereTests: XCTestCase {
    /// jess as the catalog lists it (backend/src/jess-sidekick.ts): the old circle symbol on black.
    private let jessFromCatalog = SidekickEntry(id: "jess", name: "jess", symbolName: "circle.circle.fill", backgroundHex: "#000000", version: "built-in")

    func testJessIsDrawnAsTheWrittenJessNotTheCatalogSymbol() {
        XCTAssertEqual(SidekickArtwork.artwork(forSidekickId: "jess"), .jessWord)
        XCTAssertEqual(SidekickIconContent.content(for: jessFromCatalog), .artwork(.jessWord))
    }

    func testTheHomeGridAndTheSharedIconUseTheSameImage() {
        XCTAssertEqual(JessTileIcon.imageName, JessTileArtwork.imageName)
    }

    func testTheWidgetExtensionCarriesTheJessTile() throws {
        let plugIns = try XCTUnwrap(Bundle.main.builtInPlugInsURL, "the app has no PlugIns folder")
        let widgetBundle = try XCTUnwrap(Bundle(url: plugIns.appendingPathComponent("MidasWidgets.appex")), "MidasWidgets.appex is not embedded")
        let image = UIImage(named: JessTileArtwork.imageName, in: widgetBundle, compatibleWith: nil)
        XCTAssertNotNil(image, "the widget extension cannot load JessTile, so a folder would show no jess icon")
    }

    @MainActor
    func testTheSharedIconIsPaperWithInkInLightModeNotABlackTile() throws {
        let iconView = SidekickIconView(content: SidekickIconContent.content(for: jessFromCatalog), size: 120)
        let renderer = ImageRenderer(content: iconView.environment(\.colorScheme, .light))
        renderer.scale = 1
        let rendered = try XCTUnwrap(renderer.uiImage?.cgImage, "the jess icon did not render")
        let brightness = try averageBrightness(of: rendered)
        // The old icon was a white circle on black (well under half bright); the tile is mostly
        // white paper with the word in ink.
        XCTAssertGreaterThan(brightness, 0.7, "the jess icon renders dark: still the old circle on black?")
        XCTAssertLessThan(brightness, 0.99, "the jess icon renders blank: the word is missing")
    }

    // MARK: - Pixels

    private func averageBrightness(of cgImage: CGImage) throws -> Double {
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colourSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: colourSpace,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                return false
            }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn)
        // Only the middle half: the rounded corners are transparent
        var total = 0.0
        var count = 0
        for row in (height / 4)..<(height * 3 / 4) {
            for column in (width / 4)..<(width * 3 / 4) {
                let offset = (row * width + column) * 4
                let channelSum = Double(pixels[offset]) + Double(pixels[offset + 1]) + Double(pixels[offset + 2])
                total += channelSum / (3 * 255)
                count += 1
            }
        }
        return total / Double(count)
    }
}
