import Foundation

public struct AhaKeyTrustDecision: Codable, Equatable, Sendable {
    public var allowed: Bool
    public var reason: String?

    public static let allowed = AhaKeyTrustDecision(allowed: true, reason: nil)

    public static func denied(_ reason: String) -> AhaKeyTrustDecision {
        AhaKeyTrustDecision(allowed: false, reason: reason)
    }
}

public struct AhaKeyTrustPolicy: Sendable {
    public var allowedHosts: Set<String>
    public var allowedOrigins: Set<String>
    public var token: String

    public init(
        allowedHosts: Set<String> = ["127.0.0.1", "127.0.0.1:17342", "localhost", "localhost:17342"],
        allowedOrigins: Set<String> = ["http://127.0.0.1:5173", "http://localhost:5173", "http://127.0.0.1:5174", "http://localhost:5174", "http://127.0.0.1:4173", "http://localhost:4173"],
        token: String
    ) {
        self.allowedHosts = allowedHosts
        self.allowedOrigins = allowedOrigins
        self.token = token
    }

    public func authorize(host: String?, origin: String?, token candidate: String?, stateChanging: Bool) -> AhaKeyTrustDecision {
        guard let host, allowedHosts.contains(host) else {
            return .denied("invalid_host")
        }
        guard stateChanging else {
            return .allowed
        }
        guard let origin, allowedOrigins.contains(origin) else {
            return .denied("untrusted_origin")
        }
        guard let candidate, !candidate.isEmpty else {
            return .denied("missing_token")
        }
        guard candidate == token else {
            return .denied("invalid_token")
        }
        return .allowed
    }
}
