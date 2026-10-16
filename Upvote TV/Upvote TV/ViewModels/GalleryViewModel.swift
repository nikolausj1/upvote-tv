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

    /// The load currently in flight, if any, so a refresh can supersede it instead of
    /// running two hydrations side by side against the same rate-limit budget.
    private var loadTask: Task<Void, Never>?
    /// When the most recent load started. `refreshIfStale` uses it to ignore refresh
    /// triggers that land right on top of one another (scene-phase flicker at launch, a
    /// timer tick just after a return from the background).
    private(set) var lastLoadStartedAt: Date?

    init(provider: ContentProvider, watchedManager: WatchedStateManager) {
        self.provider = provider
        self.watchedManager = watchedManager
    }

    // MARK: - Computed state

    var filteredPosts: [Post] {
        // Posts Reddit has confirmed are gone are dropped outright. There is no way to view
        // one and no action worth taking on it, so leaving it in the list only costs the
        // user a manual mark-watched or remove.
        NSFWFilterService.filter(posts).filter { !$0.isUnavailable }
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

    /// The queue is accessible but has nothing to show. Browse view renders EmptyQueueView.
    /// Reads the filtered list, not the raw one: a queue holding only removed posts (or only
    /// NSFW ones with the filter on) renders nothing, and a blank list reads as a bug.
    var showEmptyQueue: Bool {
        !isLoading && loadError == nil && hasAttemptedLoad && filteredPosts.isEmpty
    }

    // MARK: - Debug

    // Flip to true to test the "You're Caught Up" state
    private let debugMarkAllWatched = false

    // MARK: - Actions

    func loadPosts() async {
        lastLoadStartedAt = Date()
        if !hasAttemptedLoad {
            isLoading = true
        }
        loadError = nil
        do {
            // Snapshots arrive progressively: cached posts first, then each freshly
            // resolved one. Drop the loading state on the first snapshot so the user sees
            // their queue immediately instead of waiting out the slowest resolve.
            for try await snapshot in provider.postsStream(deprioritizing: watchedIDsSnapshot()) {
                posts = snapshot
                if debugMarkAllWatched {
                    for post in snapshot { watchedManager.markWatched(post.id) }
                }
                refreshWatchedMap()
                // Only stand down the skeleton once there's something to show. An empty
                // snapshot mid-hydration means "nothing resolved yet", and treating that
                // as a finished load would flash the empty-queue screen on a cold start.
                if !snapshot.isEmpty {
                    hasAttemptedLoad = true
                    isLoading = false
                }
            }
        } catch {
            // A superseded load (cancelled by a newer refresh or by the view going away) is
            // not a failure, and must not leave an error on screen over a list that the
            // replacement load is about to update.
            if Task.isCancelled { return }
            // A refresh that fails while there is already a queue on screen keeps the queue
            // on screen: cached content is the safety net (Architecture Rule 6), and a
            // full-screen error over a perfectly good list is the wrong trade for a blip
            // while the TV was asleep. Only an initial load with nothing to show reports.
            if posts.isEmpty || !hasAttemptedLoad {
                loadError = (error as? ContentProviderError) ?? .unknown
            }
        }
        hasAttemptedLoad = true
        isLoading = false
    }

    /// Re-fetches the queue without touching what is on screen, unless a load started less
    /// than `minimumInterval` ago. Called when the app returns to the foreground and on the
    /// periodic foreground timer, so a post shared while the TV sat on the Browse screen,
    /// or while the app was in the background, shows up without a force-quit.
    ///
    /// Any load still in flight is superseded: its gist snapshot is already stale, and
    /// whatever it resolved so far is in the cache for the new load to pick up for free.
    func refreshIfStale(minimumInterval: TimeInterval = AppConfig.minimumRefreshInterval) {
        if let last = lastLoadStartedAt, Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            await self?.loadPosts()
        }
    }

    /// Watched ids known before the load starts, so the provider can resolve them last.
    /// Derived from the store rather than `watchedMap`, which is empty on a cold launch.
    private func watchedIDsSnapshot() -> Set<String> {
        let ids = posts.map(\.id)
        guard !ids.isEmpty else { return [] }
        return Set(watchedManager.watchedStateMap(for: ids).filter(\.value).keys)
    }

    /// A thumbnail failed to load. Reddit's preview URLs are signed, and the long cache TTL
    /// means a rotated signature would otherwise leave a permanently broken image. Marking
    /// the one post stale gets it re-resolved on the next refresh without expiring the
    /// whole queue on a timer.
    func reportThumbnailFailure(for postID: String) {
        provider.invalidateThumbnail(postID: postID)
    }

    /// Re-poll the queue file without showing a loading spinner. Used by EmptyQueueView.
    ///
    /// Only meaningful while the queue is genuinely empty. Since `showEmptyQueue` reads the
    /// *filtered* list, this view also appears when every item is hidden (all removed, or
    /// all NSFW with the filter on) — and there, re-hydrating every 10s would re-resolve
    /// posts already known to be dead against a rate-limit budget shared with the whole
    /// household. Nothing changes until someone shares something new anyway.
    func pollForNewItems() {
        guard posts.isEmpty else { return }
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
