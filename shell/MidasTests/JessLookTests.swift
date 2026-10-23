import SwiftUI
import UIKit
import XCTest
@testable import Midas

// jess's look, founder 2026-10-22 (docs/briefs/jess-look-lead.md): the listening core is Volt in the
// original jess purple's recipe, and jess's home tile is the written "Jess" in the Midas icon's hand.
@MainActor
final class JessLookTests: XCTestCase {
    func testTheListeningCoreIsVoltInBothModes() {
        XCTAssertEqual(JessOrbPalette.light.listening, JessOrbColor(hex: 0xCEFF00))
        XCTAssertEqual(JessOrbPalette.dark.listening, JessOrbColor(hex: 0xE7FF85))
        XCTAssertEqual(JessOrbPalette.light.coreColor(for: .listening), JessOrbColor(hex: 0xCEFF00))
        XCTAssertEqual(JessOrbPalette.dark.coreColor(for: .listening), JessOrbColor(hex: 0xE7FF85))
    }

    func testListeningLooksLikeNoOtherState() {
        for palette in [JessOrbPalette.light, JessOrbPalette.dark] {
            let listening = palette.coreColor(for: .listening)
            for state in [JessOrbState.idle, .thinking, .added, .failed] {
                XCTAssertNotEqual(listening, palette.coreColor(for: state), "listening matches \(state)")
            }
            // Only the core changes: ring and body stay ink and paper while listening.
            XCTAssertNotEqual(palette.ring, listening)
            XCTAssertNotEqual(palette.body, listening)
        }
    }

    func testDarkModeIsTheLightColourWithAboutHalfWhite() {
        // The original jess purple's recipe: #6A00FF light becomes #B48CFF dark, 52% white mixed in.
        let light = JessOrbPalette.light.listening
        let dark = JessOrbPalette.dark.listening
        let pairs = [(light.red, dark.red), (light.green, dark.green), (light.blue, dark.blue)]
        for (lightChannel, darkChannel) in pairs {
            let mixed = lightChannel + (1 - lightChannel) * 0.52
            XCTAssertEqual(darkChannel, mixed, accuracy: 1.0 / 255)
        }
    }

    func testTheListeningColourIsNotPurple() {
        // DESIGN.md §5a: never purple or violet (same rule as the orb's other colours).
        for colour in [JessOrbPalette.light.listening, JessOrbPalette.dark.listening] {
            let isPurple = colour.blue > colour.green + 0.15 && colour.red > colour.green + 0.15
            XCTAssertFalse(isPurple, "\(colour) reads as purple")
        }
    }

    func testTheJessTileShipsInLightAndDark() throws {
        let image = try XCTUnwrap(UIImage(named: JessTileIcon.imageName), "JessTile is missing from the asset catalog")
        let light = image.imageAsset?.image(with: UITraitCollection(userInterfaceStyle: .light)) ?? image
        let dark = try XCTUnwrap(image.imageAsset?.image(with: UITraitCollection(userInterfaceStyle: .dark)))
        // The corner is paper: white in light mode, #111111 in dark mode (as the Midas icon).
        let lightCorner = try cornerPixel(of: light)
        let darkCorner = try cornerPixel(of: dark)
        XCTAssertEqual(lightCorner, [255, 255, 255])
        XCTAssertEqual(darkCorner, [17, 17, 17])
        // The word is there: the centre row has ink, not only paper.
        XCTAssertTrue(try rowHasInk(of: light, paper: lightCorner), "no ink in the light tile")
        XCTAssertTrue(try rowHasInk(of: dark, paper: darkCorner), "no ink in the dark tile")
    }

    func testTheJessTileRendersAtHomeGridSize() throws {
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: JessTileIcon(size: SidekickHomeLayout.iconSize).environment(\.colorScheme, scheme))
            let rendered = try XCTUnwrap(renderer.uiImage, "jess tile did not render in \(scheme)")
            XCTAssertEqual(rendered.size.width, SidekickHomeLayout.iconSize, accuracy: 0.5)
        }
    }

    // MARK: - Pixels

    private func rgbaPixels(of image: UIImage) throws -> (pixels: [UInt8], width: Int, height: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colourSpace = CGColorSpace(name: CGColorSpace.sRGB)!
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
        return (pixels, width, height)
    }

    private func cornerPixel(of image: UIImage) throws -> [Int] {
        let bitmap = try rgbaPixels(of: image)
        let offset = (4 * bitmap.width + 4) * 4
        return [Int(bitmap.pixels[offset]), Int(bitmap.pixels[offset + 1]), Int(bitmap.pixels[offset + 2])]
    }

    private func rowHasInk(of image: UIImage, paper: [Int]) throws -> Bool {
        let bitmap = try rgbaPixels(of: image)
        let row = bitmap.height / 2
        for column in 0..<bitmap.width {
            let offset = (row * bitmap.width + column) * 4
            let difference = abs(Int(bitmap.pixels[offset]) - paper[0])
            if difference > 128 { return true }
        }
        return false
    }
}
