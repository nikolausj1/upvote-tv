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
    @Published var isShowingCachedContent = false
    @Published var cachedContentDate: Date?

    private let provider: ContentProvider
    let watchedManager: WatchedStateManager

    init(provider: ContentProvider, watchedManager: WatchedStateManager) {
        self.provider = provider
        self.watchedManager = watchedManager
    }

    // MARK: - Computed

    var filteredPosts: [Post] {
        NSFWFilterService.filter(posts)
    }

    var unwatchedPosts: [Post] {
        filteredPosts.filter { !isWatched($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var watchedPosts: [Post] {
        filteredPosts.filter { isWatched($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
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

    // MARK: - Debug

    // Flip to true to test the "You're Caught Up" state
    private let debugMarkAllWatched = false

    // MARK: - Actions

    func loadPosts() async {
        isLoading = true
        loadError = nil
        do {
            let fetched = try await provider.fetchUpvotedPosts()
            posts = fetched
            isShowingCachedContent = false
            if debugMarkAllWatched {
                for post in fetched { watchedManager.markWatched(post.id) }
            }
            refreshWatchedMap()
        } catch let error as ContentProviderError {
            loadError = error
            // If we have cached posts, keep showing them with stale banner
            if !posts.isEmpty {
                isShowingCachedContent = true
            }
        } catch {
            loadError = .unknown(underlying: error)
            if !posts.isEmpty {
                isShowingCachedContent = true
            }
        }
        isLoading = false
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

    private func refreshWatchedMap() {
        let ids = posts.map(\.id)
        watchedMap = watchedManager.watchedStateMap(for: ids)
    }
}
