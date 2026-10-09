import Foundation

/// WebAuthn JSON carries binary fields as unpadded base64url.
enum Base64URL {
    static func encode(_ data: Data) -> String {
        let standard = data.base64EncodedString()
        let urlSafe = standard
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        return urlSafe.replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ text: String) -> Data? {
        var standard = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder > 0 {
            standard += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: standard)
    }
}
