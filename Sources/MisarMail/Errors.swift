/// Errors thrown by ``MisarMailClient``.
public enum MisarMailError: Error, CustomStringConvertible {

    /// The API returned a non-2xx HTTP response.
    ///
    /// - Parameters:
    ///   - status:  HTTP status code.
    ///   - message: Human-readable description from the API response body.
    case apiError(status: Int, message: String)

    /// The subscription attached to the API key blocks this call.
    ///
    /// MisarMail meters per-plan server-side: a spent allowance answers 429 and
    /// a feature not on the plan answers 402. A distinct case rather than a
    /// generic 429 because retrying cannot help until the allowance resets or
    /// the plan changes — the client stops retrying on sight.
    case planLimitExceeded(
        status: Int,
        message: String,
        plan: String? = nil,
        upgradeURL: String? = nil,
        retryAfter: Int? = nil,
        feature: String? = nil
    )

    /// A network-level error prevented the request from completing, or the
    /// maximum number of retries was exhausted.
    ///
    /// - Parameter message: Underlying error description.
    case networkError(message: String)

    public var description: String {
        switch self {
        case .apiError(let status, let message):
            return "MisarMailError.apiError(\(status)): \(message)"
        case .planLimitExceeded(let status, let message, let plan, let url, _, _):
            var out = "MisarMailError.planLimitExceeded(\(status)): \(message)"
            if let plan { out += " [plan=\(plan)]" }
            if let url { out += " [upgrade=\(url)]" }
            return out
        case .networkError(let message):
            return "MisarMailError.networkError: \(message)"
        }
    }
}

public extension MisarMailError {
    /// The pricing URL to send the user to, when this is a plan refusal.
    var upgradeURL: String? {
        if case let .planLimitExceeded(_, _, _, url, _, _) = self { return url }
        return nil
    }
}
