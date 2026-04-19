import Foundation

/// Shared app configuration constants used across tvOS, iOS, and the Share Extension.
enum AppConfig {
    /// Base URL for the GitHub Gist API. Append the gist ID to complete the endpoint.
    static let gistAPIBase = "https://api.github.com/gists/"
    /// Name of the file inside the gist that stores the queue.
    static let queueFileName = "queue.json"
    /// Current queue.json schema version.
    static let queueSchemaVersion = 1
    /// How long cached post metadata remains fresh.
    static let cacheTTL: TimeInterval = 24 * 60 * 60
    /// Per-request network timeout for metadata resolvers and queue fetches.
    static let resolverTimeout: TimeInterval = 10
    /// Maximum concurrent metadata resolutions.
    static let resolverConcurrency = 10
    /// Empty-queue poll interval.
    static let emptyQueuePollInterval: TimeInterval = 10
}
