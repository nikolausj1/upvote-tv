import Foundation

enum ContentProviderError: Error, LocalizedError, Equatable {
    /// `Secrets.plist` is missing or the gist configuration is empty.
    case configurationMissing
    /// Could not reach the queue transport (GitHub, network, etc.).
    case networkError
    /// Transport responded with something we can't parse.
    case invalidResponse
    /// Transport rate-limited us.
    case rateLimited
    /// Catch-all for unexpected conditions.
    case unknown

    var errorDescription: String? {
        switch self {
        case .configurationMissing:
            return "Upvote TV is missing its queue configuration. Add your Gist ID and token to Secrets.plist."
        case .networkError:
            return "Can't reach the queue. Check your internet connection."
        case .invalidResponse:
            return "Received an unexpected response from the queue."
        case .rateLimited:
            return "Too many requests. Please try again in a moment."
        case .unknown:
            return "An unexpected error occurred."
        }
    }
}

protocol ContentProvider {
    func fetchUpvotedPosts() async throws -> [Post]

    /// Remove an item from the queue (if backed by a mutable transport) and drop its cached metadata.
    /// Default implementation is a no-op for providers that don't back a persistent queue.
    func removeItem(postID: String) async throws
}

extension ContentProvider {
    func removeItem(postID: String) async throws {
        // Default: no-op. MockContentProvider inherits this.
    }
}

// `AppConfig` now lives in `Shared/AppConfig.swift` so iOS and Share Extension can use it too.
