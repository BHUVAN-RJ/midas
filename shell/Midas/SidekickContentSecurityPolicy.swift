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

    static func policy(scriptHashes: [String], platformOrigin: URL) -> String {
        let scriptSources = scriptHashes.isEmpty ? "'none'" : scriptHashes.joined(separator: " ")
        let connectOrigin = platformOrigin.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let directives = [
            "default-src 'none'",
            "script-src \(scriptSources)",
            "style-src 'unsafe-inline'",
            "img-src data: blob:",
            "font-src data:",
            "connect-src \(connectOrigin)",
            "base-uri 'none'",
            "form-action 'none'",
        ]
        return directives.joined(separator: "; ")
    }
}
