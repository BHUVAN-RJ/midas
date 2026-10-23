import UIKit
import XCTest
@testable import Midas

/// The `drawing` part shows the strokes on the screenshot, in the pen colour (Volt #CEFF00, founder
/// 2026-10-23, repair glow V1), where they were drawn.
final class RepairDrawingRendererTests: XCTestCase {
    private static func whiteScreenshot(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    /// RGBA of one pixel, read back from the bitmap.
    private func pixel(in image: UIImage, x: Int, y: Int) throws -> (red: UInt8, green: UInt8, blue: UInt8) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    func testStrokePixelsAreVoltOverTheScreenshot() throws {
        let screenshot = Self.whiteScreenshot(size: CGSize(width: 60, height: 60))
        let stroke = RepairStroke(points: [[10, 30, 0], [50, 30, 100]])
        let drawing = RepairDrawingRenderer.render(screenshot: screenshot, strokes: [stroke], penColor: RepairPen.uiColor)

        let onStroke = try pixel(in: drawing, x: 30, y: 30)
        XCTAssertEqual(Int(onStroke.red), 206, accuracy: 3)
        XCTAssertEqual(Int(onStroke.green), 255, accuracy: 2)
        XCTAssertEqual(Int(onStroke.blue), 0, accuracy: 2)

        let offStroke = try pixel(in: drawing, x: 30, y: 5)
        XCTAssertEqual(offStroke.red, 255)
        XCTAssertEqual(offStroke.green, 255)
        XCTAssertEqual(offStroke.blue, 255)
    }

    func testDrawingKeepsTheScreenshotSize() {
        let screenshot = Self.whiteScreenshot(size: CGSize(width: 37, height: 91))
        let drawing = RepairDrawingRenderer.render(screenshot: screenshot, strokes: [], penColor: RepairPen.uiColor)
        XCTAssertEqual(drawing.size, screenshot.size)
        XCTAssertEqual(drawing.scale, screenshot.scale)
    }

    func testPenIsVoltFromTheDesignRecord() {
        XCTAssertEqual(RepairPen.colorHex, "#CEFF00")
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        RepairPen.uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        XCTAssertEqual(Int((red * 255).rounded()), 0xCE)
        XCTAssertEqual(Int((green * 255).rounded()), 0xFF)
        XCTAssertEqual(Int((blue * 255).rounded()), 0x00)
    }
}
