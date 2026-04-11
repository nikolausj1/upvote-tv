import Foundation

actor RateLimitHandler {
    private var remaining: Int = 60
    private var resetDate: Date = Date()
    private var usedCount: Int = 0

    // MARK: - Header Parsing

    func update(from response: HTTPURLResponse) {
        if let remainingStr = response.value(forHTTPHeaderField: "X-Ratelimit-Remaining"),
           let remainingVal = Double(remainingStr) {
            remaining = Int(remainingVal)
        }
        if let resetStr = response.value(forHTTPHeaderField: "X-Ratelimit-Reset"),
           let resetSeconds = Double(resetStr) {
            resetDate = Date().addingTimeInterval(resetSeconds)
        }
        if let usedStr = response.value(forHTTPHeaderField: "X-Ratelimit-Used"),
           let usedVal = Int(usedStr) {
            usedCount = usedVal
        }
    }

    // MARK: - Throttling

    var shouldWaitBeforeRequest: Bool {
        remaining <= 1 && resetDate > Date()
    }

    var waitDuration: TimeInterval {
        max(0, resetDate.timeIntervalSinceNow)
    }

    // MARK: - 429 Retry Logic

    /// Executes a URL request with automatic 429 retry (once).
    func execute(_ request: URLRequest, session: URLSession = .shared) async throws -> (Data, HTTPURLResponse) {
        // If we know we're rate limited, wait first
        if shouldWaitBeforeRequest {
            let wait = waitDuration
            if wait > 0 && wait < 120 {
                try await Task.sleep(for: .seconds(wait))
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ContentProviderError.invalidResponse
        }

        update(from: httpResponse)

        // Retry once on 429
        if httpResponse.statusCode == 429 {
            let retryAfter = retryDelay(from: httpResponse)
            try await Task.sleep(for: .seconds(retryAfter))

            let (retryData, retryResponse) = try await session.data(for: request)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else {
                throw ContentProviderError.invalidResponse
            }

            update(from: retryHTTP)

            if retryHTTP.statusCode == 429 {
                throw ContentProviderError.rateLimited
            }

            return (retryData, retryHTTP)
        }

        return (data, httpResponse)
    }

    private func retryDelay(from response: HTTPURLResponse) -> TimeInterval {
        // Use Retry-After header if present, otherwise use reset time, fallback to 5s
        if let retryStr = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = Double(retryStr) {
            return min(seconds, 60)
        }
        let reset = waitDuration
        if reset > 0 { return min(reset, 60) }
        return 5
    }

    // MARK: - Diagnostics

    var diagnostics: RateLimitDiagnostics {
        RateLimitDiagnostics(remaining: remaining, used: usedCount, resetsAt: resetDate)
    }
}

struct RateLimitDiagnostics: Sendable {
    let remaining: Int
    let used: Int
    let resetsAt: Date
}
