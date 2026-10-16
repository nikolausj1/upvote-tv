import Testing
import Foundation
import SwiftData
@testable import Upvote_TV

/// A provider whose answers the test controls, one call at a time.
private final class ScriptedProvider: ContentProvider, @unchecked Sendable {
    enum Script { case posts([Post]); case failure(ContentProviderError) }
    private let lock = NSLock()
    private var script: [Script]
    private(set) var calls = 0

    init(_ script: [Script]) { self.script = script }

    func postsStream(deprioritizing watchedIDs: Set<String>) -> AsyncThrowingStream<[Post], Error> {
        lock.lock()
        calls += 1
        let next = script.isEmpty ? nil : script.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            switch next {
            case .posts(let posts)?:
                continuation.yield(posts)
                continuation.finish()
            case .failure(let error)?:
                continuation.finish(throwing: error)
            case nil:
                continuation.finish(throwing: ContentProviderError.unknown)
            }
        }
    }
}

private func makePost(_ id: String) -> Post {
    Post(id: id, title: "Post \(id)", subreddit: "test", author: nil, createdAt: Date(),
         postType: .link, thumbnailURL: nil, previewImageURL: nil, mediaURL: nil,
         galleryItems: nil, textBody: nil, outboundURL: URL(string: "https://example.com/\(id)")!,
         domain: "example.com", isNSFW: false, score: nil, sharedAt: Date(), resolvedAt: Date())
}

/// Owns the in-memory store for the duration of a test. `WatchedStateManager` holds only the
/// `ModelContext`; if the `ModelContainer` behind it is released, SwiftData traps on the
/// next fetch (observed as a SIGTRAP inside `watchedStateMap(for:)`), so the container has
/// to live at least as long as the view model.
@MainActor
private struct Harness {
    let container: ModelContainer
    let viewModel: GalleryViewModel

    init(_ provider: ContentProvider) throws {
        container = try ModelContainer(
            for: WatchedState.self, CachedPost.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        viewModel = GalleryViewModel(provider: provider,
                                     watchedManager: WatchedStateManager(modelContext: container.mainContext))
    }
}

@MainActor
struct GalleryViewModelRefreshTests {

    @Test func aFailedRefreshKeepsTheQueueOnScreen() async throws {
        let provider = ScriptedProvider([.posts([makePost("a")]), .failure(.networkError)])
        let harness = try Harness(provider)
        let vm = harness.viewModel

        await vm.loadPosts()
        #expect(vm.posts.map(\.id) == ["a"])
        #expect(vm.loadError == nil)

        // The TV was asleep, the network blipped: the list must stay, with no error screen.
        await vm.loadPosts()
        #expect(vm.posts.map(\.id) == ["a"])
        #expect(vm.loadError == nil)
        #expect(vm.showConnectionError == false)
        withExtendedLifetime(harness) {}
    }

    @Test func anInitialFailureStillReportsTheError() async throws {
        let harness = try Harness(ScriptedProvider([.failure(.networkError)]))
        let vm = harness.viewModel
        await vm.loadPosts()
        #expect(vm.loadError == .networkError)
        #expect(vm.showConnectionError)
        withExtendedLifetime(harness) {}
    }

    @Test func refreshPicksUpNewPostsWithoutShowingTheSkeleton() async throws {
        let provider = ScriptedProvider([.posts([makePost("a")]), .posts([makePost("b"), makePost("a")])])
        let harness = try Harness(provider)
        let vm = harness.viewModel
        await vm.loadPosts()
        #expect(vm.isLoading == false)

        vm.refreshIfStale(minimumInterval: 0)
        // Give the refresh task a moment to run.
        for _ in 0..<50 where vm.posts.count < 2 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(vm.posts.map(\.id) == ["b", "a"])
        #expect(vm.isLoading == false)
        #expect(provider.calls == 2)
        withExtendedLifetime(harness) {}
    }

    @Test func refreshTriggersCloseTogetherAreCoalesced() async throws {
        let provider = ScriptedProvider([.posts([makePost("a")]), .posts([makePost("a")]), .posts([makePost("a")])])
        let harness = try Harness(provider)
        let vm = harness.viewModel
        await vm.loadPosts()

        // Scene-phase flicker right after launch, or a timer tick on top of a foreground
        // return: within the minimum interval these must not start another load.
        vm.refreshIfStale(minimumInterval: 60)
        vm.refreshIfStale(minimumInterval: 60)
        try await Task.sleep(for: .milliseconds(100))
        #expect(provider.calls == 1)

        vm.refreshIfStale(minimumInterval: 0)
        try await Task.sleep(for: .milliseconds(100))
        #expect(provider.calls == 2)
        withExtendedLifetime(harness) {}
    }
}
