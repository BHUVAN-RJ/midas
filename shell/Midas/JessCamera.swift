import SwiftUI
import UIKit

// jess's camera (founder, 2026-11-02, docs/mockups/jess-camera-2026-11-02.html): a quiet camera button
// right of the orb on the jess screen opens iOS's camera; Use Photo sends the photo with the words
// heard so far, and the Workdesk card shows it. The photo is shrunk on the phone before it is sent
// and stays on the phone with its card; the server never keeps it.

enum JessCameraSpec {
    /// The button, right of the orb (DESIGN.md 1a: quiet, chip colour, ink glyph).
    static let buttonSize: CGFloat = 48
    static let glyphSize: CGFloat = 20
    /// From the orb's edge to the button.
    static let gapFromOrb: CGFloat = 28
    /// The longest side of the photo sent, and its JPEG quality.
    static let maxSide: CGFloat = 1024
    static let jpegQuality: CGFloat = 0.7
    static let symbol = "camera"
    static let accessibilityLabel = "Camera"

    /// The size a photo is shrunk to: the longest side at most `maxSide`, never enlarged.
    static func shrunkSize(_ size: CGSize) -> CGSize {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else {
            return size
        }
        let scale = maxSide / longest
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }

    /// The photo as sent: shrunk, JPEG. Nil when it cannot be encoded.
    static func jpeg(from image: UIImage) -> Data? {
        let target = shrunkSize(image.size)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        func drawShrunk(_ context: UIGraphicsImageRendererContext) {
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        let shrunk = renderer.image(actions: drawShrunk)
        return shrunk.jpegData(compressionQuality: jpegQuality)
    }

    /// The camera, or the photo library where there is none (the simulator).
    static var sourceType: UIImagePickerController.SourceType {
        UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
    }
}

/// The quiet camera button.
struct JessCameraButton: View {
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let tokens = RepairTokens.forScheme(colorScheme)
        Button(action: action) {
            Image(systemName: JessCameraSpec.symbol)
                .font(.system(size: JessCameraSpec.glyphSize, weight: .regular))
                .foregroundStyle(tokens.ink.color)
                .frame(width: JessCameraSpec.buttonSize, height: JessCameraSpec.buttonSize)
                .background(tokens.paper2.color, in: Circle())
                .overlay(Circle().stroke(tokens.rule.color, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(JessCameraSpec.accessibilityLabel))
    }
}

/// iOS's camera (UIImagePickerController). Hands back the photo, or nil on Cancel.
struct JessCameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = JessCameraSpec.sourceType
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void

        init(onFinish: @escaping (UIImage?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// The photo on a Workdesk card.
struct JessCardPhoto: View {
    let jpeg: Data
    let size: CGFloat

    var body: some View {
        if let image = UIImage(data: jpeg) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .accessibilityLabel(Text(VoiceReminderCopy.photo))
        }
    }
}
