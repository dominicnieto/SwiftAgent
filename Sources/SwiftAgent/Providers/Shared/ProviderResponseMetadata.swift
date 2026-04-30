import Foundation

extension ResponseMetadata {
    static func providerHTTPMetadata(
        requestID: UUID,
        headers: [String: String],
        providerName: String,
        modelID: String? = nil
    ) -> ResponseMetadata {
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        var rateLimits: [String: RateLimitState] = [:]

        let requestRateLimit = RateLimitState(
            limit: normalizedHeaders.intValue(for: "x-ratelimit-limit-requests"),
            remaining: normalizedHeaders.intValue(for: "x-ratelimit-remaining-requests"),
            resetAt: normalizedHeaders.dateValue(for: "x-ratelimit-reset-requests"),
            retryAfter: normalizedHeaders.timeIntervalValue(for: "retry-after")
        )
        if requestRateLimit.hasValues {
            rateLimits["requests"] = requestRateLimit
        }

        let tokenRateLimit = RateLimitState(
            limit: normalizedHeaders.intValue(for: "x-ratelimit-limit-tokens"),
            remaining: normalizedHeaders.intValue(for: "x-ratelimit-remaining-tokens"),
            resetAt: normalizedHeaders.dateValue(for: "x-ratelimit-reset-tokens"),
            retryAfter: nil
        )
        if tokenRateLimit.hasValues {
            rateLimits["tokens"] = tokenRateLimit
        }

        let warnings = normalizedHeaders["openai-warning"].map {
            [LanguageModelWarning(code: "provider_warning", message: $0)]
        } ?? []

        return ResponseMetadata(
            requestID: requestID,
            providerRequestID: normalizedHeaders["x-request-id"] ?? normalizedHeaders["request-id"],
            providerName: providerName,
            modelID: modelID,
            rateLimits: rateLimits,
            warnings: warnings,
            providerMetadata: normalizedHeaders.providerMetadata
        )
    }
}

private extension RateLimitState {
    var hasValues: Bool {
        limit != nil || remaining != nil || resetAt != nil || retryAfter != nil
    }
}

private extension Dictionary where Key == String, Value == String {
    func intValue(for key: String) -> Int? {
        self[key].flatMap { Int($0) }
    }

    func timeIntervalValue(for key: String) -> TimeInterval? {
        self[key].flatMap { TimeInterval($0) }
    }

    func dateValue(for key: String) -> Date? {
        guard let value = self[key] else { return nil }
        if let seconds = TimeInterval(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        return ISO8601DateFormatter().date(from: value)
    }

    var providerMetadata: [String: JSONValue] {
        reduce(into: [String: JSONValue]()) { result, pair in
            result[pair.key] = .string(pair.value)
        }
    }
}
