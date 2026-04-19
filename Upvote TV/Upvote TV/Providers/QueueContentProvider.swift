import Foundation
import SwiftData

/// Primary v1 content provider. Reads the queue from a GitHub Gist and hydrates each
/// item into a full `Post` via the appropriate metadata resolver.
///
/// Flow per call:
/// 1. Fetch queue items from the gist (throws `.configurationMissing` if Secrets.plist is blank).
/// 2. Hydrate items: fresh cache → use directly; stale or missing → fetch metadata.
/// 3. Up to 10 concurrent metadata fetches, 10-second per-request timeout.
/// 4. On resolver failure: if stale cache exists, return it with a stale badge; otherwise
///    return a minimal fallback Post with postType = .unsupported.
@MainActor
final class QueueContentProvider: ContentProvider {
    private let client: GistQueueClient
    private let redditResolver: RedditMetadataResolver
    private let youtubeResolver: YouTubeMetadataResolver
    private let cache: MetadataCache

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

    func fetchUpvotedPosts() async throws -> [Post] {
        let items: [QueueItem]
        do {
            items = try await client.fetch()
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

        if items.isEmpty { return [] }

        // Prime with fresh cache where available.
        let cached = cache.bulkFetch(postIDs: items.map(\.id))
        let now = Date()

        var resolved: [String: Post] = [:]
        var toFetch: [QueueItem] = []

        for item in items {
            if let cachedPost = cached[item.id],
               let resolvedAt = cachedPost.resolvedAt,
               now.timeIntervalSince(resolvedAt) < AppConfig.cacheTTL {
                resolved[item.id] = cachedPost
            } else {
                toFetch.append(item)
            }
        }

        if !toFetch.isEmpty {
            let fetchedByID = await hydrate(toFetch)
            for (id, result) in fetchedByID {
                switch result {
                case .success(let post):
                    cache.store(post)
                    resolved[id] = post
                case .failure:
                    if let stale = cached[id] {
                        resolved[id] = stale
                    } else if let queueItem = items.first(where: { $0.id == id }) {
                        resolved[id] = fallbackPost(for: queueItem)
                    }
                }
            }
        }

        return items.compactMap { resolved[$0.id] }
    }

    func removeItem(postID: String) async throws {
        // Re-read to minimize the race window with concurrent Shortcut writes.
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

    // MARK: - Hydration

    /// Fetch metadata for the given queue items, up to `AppConfig.resolverConcurrency`
    /// tasks in flight at a time. Returns a dictionary keyed by queue-item id.
    private func hydrate(_ items: [QueueItem]) async -> [String: Result<Post, Error>] {
        let reddit = self.redditResolver
        let youtube = self.youtubeResolver
        let concurrency = min(AppConfig.resolverConcurrency, max(items.count, 1))

        return await withTaskGroup(of: (String, Result<Post, Error>).self) { group in
            var index = 0
            var results: [String: Result<Post, Error>] = [:]

            while index < concurrency && index < items.count {
                let item = items[index]
                index += 1
                group.addTask {
                    do {
                        let post = try await Self.resolve(item, reddit: reddit, youtube: youtube)
                        return (item.id, .success(post))
                    } catch {
                        return (item.id, .failure(error))
                    }
                }
            }

            while let (id, result) = await group.next() {
                results[id] = result
                if index < items.count {
                    let item = items[index]
                    index += 1
                    group.addTask {
                        do {
                            let post = try await Self.resolve(item, reddit: reddit, youtube: youtube)
                            return (item.id, .success(post))
                        } catch {
                            return (item.id, .failure(error))
                        }
                    }
                }
            }

            return results
        }
    }

    private static func resolve(
        _ item: QueueItem,
        reddit: RedditMetadataResolver,
        youtube: YouTubeMetadataResolver
    ) async throws -> Post {
        switch item.source {
        case .reddit: return try await reddit.resolve(item)
        case .youtube: return try await youtube.resolve(item)
        }
    }

    private func fallbackPost(for item: QueueItem) -> Post {
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
