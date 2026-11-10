import SwiftUI
import UIKit
import XCTest
@testable import Midas

/// The Money icon (founder, 2026-11-09: "lets go with C and update the icon everywhere"): concept
/// "C · Wallet" from docs/mockups/money-icon-options-2026-11-09.html, drawn by the shell instead of
/// the catalog's dollar sign, and tuned so it still reads at 29 pt (Settings' list) in light and dark.
@MainActor
final class MoneyIconTests: XCTestCase {

    // MARK: Which icon

    func testMoneyShowsTheWalletArtworkNotItsCatalogSymbol() {
        let entry = SidekickEntry(id: "money", name: "Money", symbolName: "dollarsign.circle.fill", backgroundHex: "#2E9E5B",
                                  version: "1", backgroundDarkHex: "#1F7A45")

        let content = SidekickIconContent.content(for: entry)

        XCTAssertEqual(SidekickArtwork.artwork(forSidekickId: "money"), .moneyWallet)
        XCTAssertEqual(content, .artwork(.moneyWallet))
    }

    // MARK: Colours

    func testBothPalettesAreMoneysColours() {
        let light = MoneyWalletArtwork.colors(isDark: false)
        let dark = MoneyWalletArtwork.colors(isDark: true)
        XCTAssertEqual(light.tile, "#F3F1EA")
        XCTAssertEqual(light.wallet, "#101210", "Money's ink")
        XCTAssertEqual(light.bill, "#2E9E5B", "Money's Groceries green, day")
        XCTAssertEqual(dark.tile, "#141614")
        XCTAssertEqual(dark.wallet, "#F4F5F2", "Money's night ink")
        XCTAssertEqual(dark.bill, "#4CC97A", "Money's Groceries green, night")
        XCTAssertLessThan(SidekickWidgetInk.luminance(dark.tile)!, 0.05, "the tile is dark at night")
    }

    func testNoColourIsPurpleOrViolet() {
        let light = MoneyWalletArtwork.colors(isDark: false)
        let dark = MoneyWalletArtwork.colors(isDark: true)
        for hex in [light.tile, light.wallet, light.bill, dark.tile, dark.wallet, dark.bill] {
            XCTAssertNotNil(SidekickColor.rgbComponents(fromHex: hex), hex)
            guard let hue = Self.hueDegrees(of: hex) else {
                // A grey: no hue
                continue
            }
            XCTAssertFalse((250.0...330.0).contains(hue), "\(hex) is purple or violet (hue \(hue))")
        }
    }

    /// The mockup's C had a light-green bill on cream (1.9:1); at 29 pt it went muddy. Each part
    /// now stands apart from the tile in both appearances.
    func testEachPartStandsOutFromTheTileInBothAppearances() {
        for isDark in [false, true] {
            let colors = MoneyWalletArtwork.colors(isDark: isDark)
            XCTAssertGreaterThanOrEqual(SidekickWidgetInk.contrast(colors.bill, colors.tile), 3, "bill on tile, dark \(isDark)")
            XCTAssertGreaterThanOrEqual(SidekickWidgetInk.contrast(colors.wallet, colors.tile), 7, "wallet on tile, dark \(isDark)")
        }
    }

    // MARK: Shapes at 29 pt

    func testTheSmallestPartsAreStillBigAt29Points() {
        let pointsPerUnit: CGFloat = 29.0 / 100.0
        // The bill shows above the gap around the wallet
        let billTop = MoneyWalletArtwork.billPath().boundingRect.minY
        let gapTop = MoneyWalletArtwork.walletRect.minY - MoneyWalletArtwork.gapWidth
        XCTAssertGreaterThanOrEqual((gapTop - billTop) * pointsPerUnit, 5, "the bill stands at least 5 pt out of the wallet")
        // The gap between bill and wallet is at least 1 pt, so they never run together
        XCTAssertGreaterThanOrEqual(MoneyWalletArtwork.gapWidth * pointsPerUnit, 1)
        // The tab's slot and rim
        let slot = MoneyWalletArtwork.slotRect()
        XCTAssertGreaterThanOrEqual(slot.height * pointsPerUnit, 3.5, "the slot is at least 3.5 pt tall")
        XCTAssertGreaterThanOrEqual(MoneyWalletArtwork.tabRimWidth * pointsPerUnit, 1.4, "the rim is at least 1.4 pt")
        // The tab sticks out past the wallet's side, so its outline says "wallet"
        XCTAssertGreaterThanOrEqual(MoneyWalletArtwork.tabRect.maxX - MoneyWalletArtwork.walletRect.maxX, 5)
        // Everything sits inside the tile with a margin
        for bounds in [MoneyWalletArtwork.billPath().boundingRect, MoneyWalletArtwork.gapPath().boundingRect, MoneyWalletArtwork.tabPath().boundingRect] {
            XCTAssertGreaterThanOrEqual(bounds.minX, 6)
            XCTAssertLessThanOrEqual(bounds.maxX, 94)
            XCTAssertGreaterThanOrEqual(bounds.minY, 6)
            XCTAssertLessThanOrEqual(bounds.maxY, 94)
        }
    }

    func testTheBillLeansBackAsInTheMockup() {
        let bill = MoneyWalletArtwork.billPath()
        XCTAssertEqual(MoneyWalletArtwork.billTiltDegrees, -8)
        // Turned anticlockwise: its top right corner is higher than its top left
        XCTAssertTrue(bill.contains(CGPoint(x: 70, y: 13)), "the right top corner rises")
        XCTAssertFalse(bill.contains(CGPoint(x: 26, y: 15)), "the left top corner drops")
    }

    // MARK: Drawn at 29 pt

    func testThe29PointTileShowsEachPartInItsColour() throws {
        let view = SidekickIconView(content: .artwork(.moneyWallet), size: 29)
        let pointsPerUnit: CGFloat = 29.0 / 100.0
        for (scheme, isDark) in [(ColorScheme.light, false), (ColorScheme.dark, true)] {
            let colors = MoneyWalletArtwork.colors(isDark: isDark)
            let image = try XCTUnwrap(render(view, colorScheme: scheme))
            let label = isDark ? "dark" : "light"
            // Points on the 100-unit canvas well inside each part
            assertNear(pixelHex(of: image, atX: 50 * pointsPerUnit, y: 5 * pointsPerUnit), colors.tile, "tile, \(label)")
            assertNear(pixelHex(of: image, atX: 50 * pointsPerUnit, y: 25 * pointsPerUnit), colors.bill, "bill, \(label)")
            assertNear(pixelHex(of: image, atX: 50 * pointsPerUnit, y: 38 * pointsPerUnit), colors.tile, "gap between bill and wallet, \(label)")
            assertNear(pixelHex(of: image, atX: 30 * pointsPerUnit, y: 66 * pointsPerUnit), colors.wallet, "wallet, \(label)")
            assertNear(pixelHex(of: image, atX: 74 * pointsPerUnit, y: 65 * pointsPerUnit), colors.tile, "slot in the tab, \(label)")
        }
    }

    // MARK: Helpers

    /// Hue in degrees of a colour with some saturation; nil for greys (no hue to speak of)
    private static func hueDegrees(of hex: String) -> Double? {
        guard let rgb = SidekickColor.rgbComponents(fromHex: hex) else {
            return nil
        }
        let largest = max(rgb.red, rgb.green, rgb.blue)
        let smallest = min(rgb.red, rgb.green, rgb.blue)
        let spread = largest - smallest
        guard spread > 0.08 else {
            return nil
        }
        var hue: Double
        if largest == rgb.red {
            hue = 60 * ((rgb.green - rgb.blue) / spread)
        } else if largest == rgb.green {
            hue = 60 * ((rgb.blue - rgb.red) / spread + 2)
        } else {
            hue = 60 * ((rgb.red - rgb.green) / spread + 4)
        }
        if hue < 0 {
            hue += 360
        }
        return hue
    }

    private func render<Content: View>(_ content: Content, colorScheme: ColorScheme) -> UIImage? {
        let renderer = ImageRenderer(content: content.environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        // Drawn twice, the first one thrown away (a first drawing can come back blank on a new simulator)
        _ = renderer.uiImage
        return renderer.uiImage
    }

    private func pixelHex(of image: UIImage, atX x: CGFloat, y: CGFloat) -> String? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        let pixelX = (x * image.scale).rounded(.down)
        let pixelY = CGFloat(cgImage.height) - (y * image.scale).rounded(.down) - 1
        context.draw(cgImage, in: CGRect(x: -pixelX, y: -pixelY, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)))
        return String(format: "#%02X%02X%02X", pixel[0], pixel[1], pixel[2])
    }

    private func assertNear(_ actualHex: String?, _ expectedHex: String, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let actualHex, let actual = SidekickColor.rgbComponents(fromHex: actualHex),
              let expected = SidekickColor.rgbComponents(fromHex: expectedHex) else {
            return XCTFail("no pixel: \(message)", file: file, line: line)
        }
        let channels = [(actual.red, expected.red), (actual.green, expected.green), (actual.blue, expected.blue)]
        for (actualValue, expectedValue) in channels {
            XCTAssertLessThanOrEqual(abs(actualValue - expectedValue) * 255, 4, "\(message): \(actualHex) is not \(expectedHex)", file: file, line: line)
        }
    }
}
