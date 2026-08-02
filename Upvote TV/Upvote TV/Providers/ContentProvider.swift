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
    /// Emits the queue as it hydrates, rather than making the caller wait for all of it.
    ///
    /// Each element is the complete best-known list, so a consumer can just assign it. The
    /// first emission carries everything already cached (usually the whole queue); later
    /// emissions arrive as individual posts finish resolving.
    ///
    /// This matters because Reddit's rate limit means a cold queue genuinely cannot be
    /// hydrated quickly (see `RedditRateLimiter`). Waiting for the last post before showing
    /// the first one turns an unavoidable delay into an empty screen.
    ///
    /// `deprioritizing` names posts the user has already watched. They sort to the bottom
    /// of the list and are rarely opened, so they resolve last and never hold up the items
    /// actually on screen.
    func postsStream(deprioritizing watchedIDs: Set<String>) -> AsyncThrowingStream<[Post], Error>

    /// Remove an item from the queue (if backed by a mutable transport) and drop its cached metadata.
    /// Default implementation is a no-op for providers that don't back a persistent queue.
    func removeItem(postID: String) async throws

    /// Mark one post's metadata stale because its thumbnail wouldn't load, so the next
    /// refresh re-resolves just that post. Default implementation is a no-op.
    func invalidateThumbnail(postID: String)
}

extension ContentProvider {
    func removeItem(postID: String) async throws {
        // Default: no-op. MockContentProvider inherits this.
    }

    func invalidateThumbnail(postID: String) {
        // Default: no-op. MockContentProvider inherits this.
    }
}

// `AppConfig` now lives in `Shared/AppConfig.swift` so iOS and Share Extension can use it too.
