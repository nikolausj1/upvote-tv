import Foundation

/// Everything a resolver can learn about a queued item, in a form both platforms share.
///
/// This is deliberately *not* `Post`. `Post` is the tvOS view model and carries UI-only
/// concerns (gallery items, text bodies, watched-state affordances); this is the transport
/// and cache shape, so the same resolution code can run in the iOS Share Extension and be
/// written into `queue.json` for the TV to pick up without re-fetching.
///
/// tvOS maps this to `Post` in `QueueContentProvider`.
struct ResolvedMetadata: Codable, Hashable, Sendable {
    var title: String
    var subreddit: String?
    var author: String?
    /// When the item was posted at its source, as distinct from when it was queued.
    var publishedAt: Date?
    var postType: PostType
    var thumbnailURL: URL?
    var mediaURL: URL?
    var outboundURL: URL?
    var domain: String?
    /// When this metadata was fetched. Drives cache freshness on the TV.
    var resolvedAt: Date

    init(
        title: String,
        subreddit: String? = nil,
        author: String? = nil,
        publishedAt: Date? = nil,
        postType: PostType,
        thumbnailURL: URL? = nil,
        mediaURL: URL? = nil,
        outboundURL: URL? = nil,
        domain: String? = nil,
        resolvedAt: Date = Date()
    ) {
        self.title = title
        self.subreddit = subreddit
        self.author = author
        self.publishedAt = publishedAt
        self.postType = postType
        self.thumbnailURL = thumbnailURL
        self.mediaURL = mediaURL
        self.outboundURL = outboundURL
        self.domain = domain
        self.resolvedAt = resolvedAt
    }
}

/// Failure modes shared by the metadata resolvers. tvOS maps these onto its own
/// `ContentProviderError` for presentation; the Share Extension just ignores them and
/// writes the item without metadata, leaving the TV to try again later.
enum MetadataResolveError: Error, Equatable {
    /// Could not reach the source at all.
    case unreachable
    /// Reached it, but the response wasn't something we can use.
    case invalidResponse
    /// Throttled and out of budget within the caller's deadline.
    case rateLimited
}
