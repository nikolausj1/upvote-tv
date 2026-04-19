import Foundation
import SwiftData
import Combine

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var posts: [Post] = []
    @Published var watchedMap: [String: Bool] = [:]
    @Published var isLoading = true
    @Published var focusedPostID: String?
    @Published var loadError: ContentProviderError?
    @Published var hasAttemptedLoad = false

    private let provider: ContentProvider
    let watchedManager: WatchedStateManager

    init(provider: ContentProvider, watchedManager: WatchedStateManager) {
        self.provider = provider
        self.watchedManager = watchedManager
    }

    // MARK: - Computed state

    var filteredPosts: [Post] {
        NSFWFilterService.filter(posts)
    }

    var unwatchedPosts: [Post] {
        filteredPosts.filter { !isWatched($0.id) }
            .sorted { Self.sortDate(for: $0) > Self.sortDate(for: $1) }
    }

    var watchedPosts: [Post] {
        filteredPosts.filter { isWatched($0.id) }
            .sorted { Self.sortDate(for: $0) > Self.sortDate(for: $1) }
    }

    private static func sortDate(for post: Post) -> Date {
        post.sharedAt ?? post.createdAt
    }

    var sortedPosts: [Post] {
        unwatchedPosts + watchedPosts
    }

    var allWatched: Bool {
        let visible = filteredPosts
        return !visible.isEmpty && visible.allSatisfy { isWatched($0.id) }
    }

    var hasUnwatched: Bool {
        filteredPosts.contains { !isWatched($0.id) }
    }

    var focusedPost: Post? {
        guard let id = focusedPostID else { return sortedPosts.first }
        return filteredPosts.first { $0.id == id }
    }

    func isWatched(_ postID: String) -> Bool {
        watchedMap[postID] ?? false
    }

    /// Queue transport can't be reached or isn't configured. Browse view renders ConnectionErrorView.
    var showConnectionError: Bool {
        guard let err = loadError else { return false }
        switch err {
        case .configurationMissing, .networkError, .rateLimited, .invalidResponse:
            return true
        case .unknown:
            return true
        }
    }

    /// The queue is accessible but has no items. Browse view renders EmptyQueueView.
    var showEmptyQueue: Bool {
        !isLoading && loadError == nil && hasAttemptedLoad && posts.isEmpty
    }

    // MARK: - Debug

    // Flip to true to test the "You're Caught Up" state
    private let debugMarkAllWatched = false

    // MARK: - Actions

    func loadPosts() async {
        if !hasAttemptedLoad {
            isLoading = true
        }
        loadError = nil
        do {
            let fetched = try await provider.fetchUpvotedPosts()
            posts = fetched
            if debugMarkAllWatched {
                for post in fetched { watchedManager.markWatched(post.id) }
            }
            refreshWatchedMap()
        } catch let error as ContentProviderError {
            loadError = error
        } catch {
            loadError = .unknown
        }
        hasAttemptedLoad = true
        isLoading = false
    }

    /// Re-poll the queue file without showing a loading spinner. Used by EmptyQueueView.
    func pollForNewItems() {
        Task { await loadPosts() }
    }

    func toggleWatched(for postID: String) {
        let newValue = watchedManager.toggleWatched(postID)
        watchedMap[postID] = newValue
    }

    func markWatched(_ postID: String) {
        watchedManager.markWatched(postID)
        watchedMap[postID] = true
    }

    func markUnwatched(_ postID: String) {
        watchedManager.markUnwatched(postID)
        watchedMap[postID] = false
    }

    /// Remove an item from the queue. Updates the in-memory list immediately, then
    /// persists via the provider (which rewrites queue.json and drops the cache entry).
    func removeFromQueue(postID: String) {
        posts.removeAll { $0.id == postID }
        watchedMap[postID] = nil
        Task {
            do {
                try await provider.removeItem(postID: postID)
            } catch {
                // Best-effort: the UI is already updated. On next fetch the item may reappear
                // if the remote write failed (e.g., iCloud glitch). Swallow silently in v1.
            }
        }
    }

    private func refreshWatchedMap() {
        let ids = posts.map(\.id)
        watchedMap = watchedManager.watchedStateMap(for: ids)
    }
}
