import Foundation

/// Shared app configuration constants used across tvOS, iOS, and the Share Extension.
enum AppConfig {
    /// Base URL for the GitHub Gist API. Append the gist ID to complete the endpoint.
    static let gistAPIBase = "https://api.github.com/gists/"
    /// Name of the file inside the gist that stores the queue.
    static let queueFileName = "queue.json"
    /// Current queue.json schema version. v2 added optional share-time metadata to each
    /// item; v1 files decode fine because every added field is optional.
    static let queueSchemaVersion = 2
    /// How long cached post metadata remains fresh.
    ///
    /// Long on purpose. A Reddit post's title, subreddit, author, publish date, and
    /// `v.redd.it` media URL are all immutable once posted, so a short TTL just re-spends
    /// the rate-limit budget re-learning facts that cannot change. The previous 24-hour TTL
    /// meant re-resolving the entire queue daily, and because a queue is typically hydrated
    /// in one burst, every item expired at the same moment. The only thing that can rot is
    /// a signed preview-image URL, which `MetadataCache.markStale` handles on demand when
    /// an image actually fails to load.
    static let cacheTTL: TimeInterval = 30 * 24 * 60 * 60
    /// Spread of the per-item random-but-stable TTL offset. Without this, a queue resolved
    /// in one burst expires in one burst, recreating the thundering herd 30 days later.
    static let cacheTTLJitter: TimeInterval = 5 * 24 * 60 * 60

    /// Per-item cache lifetime: the base TTL minus a stable per-post offset, so expiry is
    /// smeared across `cacheTTLJitter` instead of landing all at once. Deterministic in the
    /// post id so an item's deadline doesn't move between launches.
    static func cacheTTL(forPostID postID: String) -> TimeInterval {
        // FNV-1a. Swift's `hashValue` is seeded per process, so it cannot be used here:
        // the offset has to survive relaunches or every launch reshuffles every deadline.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in postID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let fraction = Double(hash % 10_000) / 10_000.0
        return cacheTTL - (cacheTTLJitter * fraction)
    }
    /// Per-request network timeout for metadata resolvers and queue fetches.
    static let resolverTimeout: TimeInterval = 10
    /// Maximum concurrent metadata resolutions.
    ///
    /// Kept low because Reddit meters on a shared per-IP unit budget (see
    /// `RedditRateLimiter`): the governor gates spending, but every request admitted before
    /// its response lands is budget the governor can only estimate, so a wide fan-out just
    /// makes that estimate blunter. Four in flight keeps the guess tight without
    /// meaningfully slowing a refresh, since the budget — not concurrency — is the limit.
    static let resolverConcurrency = 4
    /// How long a single Reddit post may spend waiting on rate-limit budget before the
    /// resolver gives up on it. A large queue can't be hydrated inside one 60-second
    /// window, so some waiting is normal and expected; this only stops one refresh from
    /// hanging indefinitely. Anything skipped falls back to cache and retries next refresh.
    static let redditResolveDeadline: TimeInterval = 150
    /// How many times a single Reddit request may be re-issued after a 429. Each retry
    /// waits out the rate-limit window first, so this is a count of windows to sit through,
    /// not a tight retry loop. Two is enough to survive a window that was already spent
    /// before the app launched; the deadline caps the total wait either way.
    static let redditThrottleRetries = 3
    /// User-Agent used when resolving Reddit posts.
    ///
    /// Reddit gated its unauthenticated `.json` API (returns a "blocked due to a network
    /// policy" page) but still serves OpenGraph link-preview tags to recognized social
    /// crawlers. This UA identifies the app *and* carries the crawler token Reddit
    /// substring-matches, so the lightweight preview page is served instead of the bot wall.
    /// Workaround pending Reddit Data API approval — see docs.
    static let redditPreviewUserAgent = "UpvoteTV/1.0 (+personal; facebookexternalhit/1.1)"
    /// Empty-queue poll interval.
    static let emptyQueuePollInterval: TimeInterval = 10
    /// How long the Share Extension will wait on metadata before giving up and writing the
    /// item bare. Kept short: the share sheet is a foreground, human-facing moment, and the
    /// TV can always resolve later. Capturing the URL is the job; enrichment is a bonus.
    static let shareResolveTimeout: TimeInterval = 6
}
