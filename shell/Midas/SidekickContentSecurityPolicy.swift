import Foundation

/// Builds the CSP the shell attaches to every Sidekick page. The shell, not the backend, owns
/// the policy: the backend only supplies the script hashes recorded at deploy time.
enum SidekickContentSecurityPolicy {
    // A hash source exactly as CSP writes it. Anything else in the header (for example
    // 'unsafe-inline') is dropped so a bad header cannot loosen the policy.
    private static let hashSourcePattern = #"^'sha256-[A-Za-z0-9+/]+={0,2}'$"#

    static func validScriptHashes(fromHeader headerValue: String?) -> [String] {
        guard let headerValue else {
            return []
        }
        let candidateSources = headerValue.split(separator: " ")
        var validSources: [String] = []
        for candidateSource in candidateSources {
            let source = String(candidateSource)
            let matchesHashForm = source.range(of: hashSourcePattern, options: .regularExpression) != nil
            if matchesHashForm {
                validSources.append(source)
            }
        }
        return validSources
    }

    /// `sidekickOrigin` (sidekick://<id>) is added to connect-src so the Sidekick can reach the
    /// shell's local store channel on its own origin, and no other Sidekick's.
    static func policy(scriptHashes: [String], platformOrigin: URL, sidekickOrigin: String? = nil) -> String {
        let scriptSources = scriptHashes.isEmpty ? "'none'" : scriptHashes.joined(separator: " ")
        let platformConnectOrigin = platformOrigin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var connectSources = [platformConnectOrigin]
        if let sidekickOrigin {
            connectSources.append(sidekickOrigin)
        }
        let directives = [
            "default-src 'none'",
            "script-src \(scriptSources)",
            "style-src 'unsafe-inline'",
            "img-src data: blob:",
            "font-src data:",
            "connect-src \(connectSources.joined(separator: " "))",
            "base-uri 'none'",
            "form-action 'none'",
        ]
        return directives.joined(separator: "; ")
    }
}
