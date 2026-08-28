import Foundation
import SwiftData

/// Primary v1 content provider. Reads the queue from a GitHub Gist and hydrates each
/// item into a full `Post`.
///
/// Hydration has three tiers, cheapest first:
/// 1. **Share-time metadata** written into `queue.json` by the iOS Share Extension. Free:
///    already in the file we just fetched, so it costs no Reddit request at all.
/// 2. **Local cache** (`CachedPost`) within its TTL. Also free.
/// 3. **A live resolve.** The only tier that spends rate-limit budget, so everything above
///    exists to avoid reaching it.
///
/// Posts are emitted progressively: the first snapshot carries every item that tiers 1 and
/// 2 could satisfy, and each live resolve pushes an updated snapshot as it lands. On
/// resolver failure a stale cache entry is used if there is one, otherwise a minimal
/// fallback `Post` with `postType == .unsupported`.
@MainActor
final class QueueContentProvider: ContentProvider {
    private let client: GistQueueClient
    private let redditResolver: RedditMetadataResolver
    private let youtubeResolver: YouTubeMetadataResolver
    private let cache: MetadataCache
    /// Thumbnail-failure reports honored so far this refresh cycle. Reset at the start of
    /// each `hydrate`. Caps how much re-resolve work a burst of image failures can trigger —
    /// see `invalidateThumbnail`.
    private var honoredThumbnailFailures = 0
    /// A single refresh cannot honor more than this many thumbnail-failure reports. A wall
    /// of stale signed URLs coming back at once (e.g. after a long time away) would
    /// otherwise mark most of the queue stale in one pass and trigger a re-resolve burst
    /// this app is built to avoid. Excess reports are simply dropped; the rot they'd flag
    /// gets caught on a later refresh instead.
    private static let maxThumbnailFailuresPerRefresh = 10
    /// A thumbnail failing this soon after it was resolved is almost certainly a transient
    /// network hiccup, not a rotted signed URL — signed preview URLs don't expire that fast.
    private static let minAgeForThumbnailFailure: TimeInterval = 24 * 60 * 60

    init(
        modelContext: ModelContext,
        client: GistQueueClient = GistQueueClient(),
        redditResolver: RedditMetadataResolver = RedditMetadataResolver(),
        youtubeResolver: YouTubeMetadataResolver = YouTubeMetadataResolver()
    ) {
        self.client = client
        self.redditResolver = redditResolver
        self.youtubeResolver = youtubeResolver
        self.cache = MetadataCache(modelContext: modelContext)
    }

    // MARK: - ContentProvider

    func postsStream(deprioritizing watchedIDs: Set<String>) -> AsyncThrowingStream<[Post], Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.hydrate(deprioritizing: watchedIDs, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func hydrate(
        deprioritizing watchedIDs: Set<String>,
        into continuation: AsyncThrowingStream<[Post], Error>.Continuation
    ) async throws {
        // A fresh cap for every refresh — thumbnail failures reported during the previous
        // one don't count against this one.
        honoredThumbnailFailures = 0

        let items = try await fetchQueue()

        if items.isEmpty {
            continuation.yield([])
            return
        }

        let cached = cache.bulkFetch(postIDs: items.map(\.id))
        let now = Date()

        var resolved: [String: Post] = [:]
        var toFetch: [QueueItem] = []

        for item in items {
            // Tier 1: the phone already resolved this at share time.
            if let metadata = item.metadata {
                let post = Self.post(from: metadata, item: item)
                resolved[item.id] = post
                // Persist so the work survives this launch, and so removing the item from
                // the gist later doesn't lose the metadata we already have.
                if cached[item.id] == nil { cache.store(post) }
                continue
            }
            // Tier 2: cached and still fresh.
            if let cachedPost = cached[item.id],
               let resolvedAt = cachedPost.resolvedAt,
               now.timeIntervalSince(resolvedAt) < AppConfig.cacheTTL(forPostID: item.id) {
                resolved[item.id] = cachedPost
                continue
            }
            // Tier 3: needs the network.
            toFetch.append(item)
        }

        // Show everything we already have before spending a single request. Skip a wholly
        // empty first snapshot when there's still work queued: "nothing yet" is not the
        // same as "nothing", and the browse view reads an empty list as an empty queue.
        let initial = items.compactMap { resolved[$0.id] ?? cached[$0.id] }
        if !initial.isEmpty || toFetch.isEmpty {
            continuation.yield(initial)
        }

        guard !toFetch.isEmpty else { return }

        // Order the work by how visible it is. Never-seen posts render as raw-URL cards
        // right now, so they come first. Watched posts sit at the bottom of the list and
        // are rarely opened, so they come last regardless of age.
        toFetch.sort { lhs, rhs in
            let lhsWatched = watchedIDs.contains(lhs.id)
            let rhsWatched = watchedIDs.contains(rhs.id)
            if lhsWatched != rhsWatched { return !lhsWatched }

            let lhsSeen = cached[lhs.id] != nil
            let rhsSeen = cached[rhs.id] != nil
            if lhsSeen != rhsSeen { return !lhsSeen }

            return lhs.sharedAt > rhs.sharedAt
        }

        await withTaskGroup(of: (String, Result<ResolvedMetadata, Error>).self) { group in
            let reddit = self.redditResolver
            let youtube = self.youtubeResolver
            var index = 0

            func addTask(_ item: QueueItem) {
                group.addTask {
                    do {
                        let metadata = try await Self.resolve(item, reddit: reddit, youtube: youtube)
                        return (item.id, .success(metadata))
                    } catch {
                        return (item.id, .failure(error))
                    }
                }
            }

            while index < AppConfig.resolverConcurrency && index < toFetch.count {
                addTask(toFetch[index])
                index += 1
            }

            while let (id, result) = await group.next() {
                if Task.isCancelled { break }

                guard let item = toFetch.first(where: { $0.id == id }) else { continue }
                switch result {
                case .success(let metadata):
                    let post = Self.post(from: metadata, item: item)
                    cache.store(post)
                    resolved[id] = post
                case .failure:
                    // Keep whatever we had; a stale card beats a raw URL.
                    if let stale = cached[id] {
                        resolved[id] = stale
                    } else {
                        resolved[id] = Self.fallbackPost(for: item)
                    }
                }

                continuation.yield(items.compactMap { resolved[$0.id] ?? cached[$0.id] })

                if index < toFetch.count {
                    addTask(toFetch[index])
                    index += 1
                }
            }
        }
    }

    func removeItem(postID: String) async throws {
        // Re-read to minimize the race window with concurrent Share Extension writes.
        let current: [QueueItem]
        do {
            current = try await client.fetch()
        } catch GistQueueClient.ClientError.notFound {
            cache.remove(postID: postID)
            return
        } catch GistQueueClient.ClientError.configurationMissing,
                GistQueueClient.ClientError.unauthorized {
            throw ContentProviderError.configurationMissing
        } catch {
            throw ContentProviderError.unknown
        }

        let filtered = current.filter { $0.id != postID }

        do {
            try await client.upsert(filtered)
        } catch {
            throw ContentProviderError.unknown
        }
        cache.remove(postID: postID)
    }

    func invalidateThumbnail(postID: String) {
        guard honoredThumbnailFailures < Self.maxThumbnailFailuresPerRefresh else { return }
        // A post resolved moments ago failing to load its image is a network hiccup, not
        // URL rot — only a cached entry old enough for its signed preview URL to plausibly
        // have expired is worth spending a re-resolve on.
        guard let resolvedAt = cache.fetch(postID: postID)?.resolvedAt,
              Date().timeIntervalSince(resolvedAt) > Self.minAgeForThumbnailFailure else {
            return
        }
        honoredThumbnailFailures += 1
        cache.markStale(postID: postID)
    }

    // MARK: - Queue fetch

    private func fetchQueue() async throws -> [QueueItem] {
        do {
            return try await client.fetch()
        } catch GistQueueClient.ClientError.configurationMissing {
            throw ContentProviderError.configurationMissing
        } catch GistQueueClient.ClientError.unauthorized {
            throw ContentProviderError.configurationMissing
        } catch GistQueueClient.ClientError.notFound {
            // Gist deleted or ID wrong — surface as configuration problem.
            throw ContentProviderError.configurationMissing
        } catch GistQueueClient.ClientError.rateLimited {
            throw ContentProviderError.rateLimited
        } catch GistQueueClient.ClientError.badResponse {
            throw ContentProviderError.invalidResponse
        } catch GistQueueClient.ClientError.network {
            throw ContentProviderError.networkError
        } catch {
            throw ContentProviderError.unknown
        }
    }

    // MARK: - Mapping

    private static func resolve(
        _ item: QueueItem,
        reddit: RedditMetadataResolver,
        youtube: YouTubeMetadataResolver
    ) async throws -> ResolvedMetadata {
        switch item.source {
        case .reddit: return try await reddit.resolve(item)
        case .youtube: return try await youtube.resolve(item)
        }
    }

    /// Projects the transport-shaped `ResolvedMetadata` onto the tvOS view model.
    static func post(from metadata: ResolvedMetadata, item: QueueItem) -> Post {
        Post(
            id: item.id,
            title: metadata.title,
            subreddit: metadata.subreddit,
            author: metadata.author,
            createdAt: metadata.publishedAt ?? item.sharedAt,
            postType: metadata.postType,
            thumbnailURL: metadata.thumbnailURL,
            previewImageURL: metadata.thumbnailURL,
            mediaURL: metadata.mediaURL,
            galleryItems: nil,
            textBody: nil,
            outboundURL: metadata.outboundURL ?? item.url,
            domain: metadata.domain ?? item.url.host,
            isNSFW: false,
            score: nil,
            sharedAt: item.sharedAt,
            resolvedAt: metadata.resolvedAt
        )
    }

    private static func fallbackPost(for item: QueueItem) -> Post {
        Post(
            id: item.id,
            title: item.url.absoluteString,
            subreddit: nil,
            author: nil,
            createdAt: item.sharedAt,
            postType: .unsupported,
            thumbnailURL: nil,
            previewImageURL: nil,
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: item.url,
            domain: item.url.host,
            isNSFW: false,
            score: nil,
            sharedAt: item.sharedAt,
            resolvedAt: nil
        )
    }
}
