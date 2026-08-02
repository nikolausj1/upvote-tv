import Foundation

/// Resolves metadata for a freshly shared item, on the phone, at the moment of sharing.
///
/// This exists because Reddit meters per IP and the TV's problem is that it wants the whole
/// queue at once, while the phone wants exactly one post. Moving the request here is the
/// least bursty shape available.
///
/// **It is deliberately unable to fail.** Every path returns `nil` rather than throwing:
/// a share must never be lost, delayed, or turned into an error because enrichment didn't
/// work out. `nil` simply means tvOS resolves the item later, exactly as it did before
/// share-time resolution existed.
struct ShareTimeResolver {
    private let reddit: RedditMetadataResolver
    private let youtube: YouTubeMetadataResolver
    private let timeout: TimeInterval

    init(
        reddit: RedditMetadataResolver = RedditMetadataResolver(),
        youtube: YouTubeMetadataResolver = YouTubeMetadataResolver(),
        timeout: TimeInterval = AppConfig.shareResolveTimeout
    ) {
        self.reddit = reddit
        self.youtube = youtube
        self.timeout = timeout
    }

    /// Best-effort metadata for `item`, or `nil` if it couldn't be had in time.
    ///
    /// The timeout is a hard ceiling on the user's wait: the share sheet is a foreground,
    /// human-facing moment, and a slow network must not hold it open. Whichever finishes
    /// first, the resolve or the clock, decides the answer.
    func resolve(_ item: QueueItem) async -> ResolvedMetadata? {
        await withTaskGroup(of: ResolvedMetadata?.self) { group in
            group.addTask {
                do {
                    switch item.source {
                    case .reddit: return try await reddit.resolve(item)
                    case .youtube: return try await youtube.resolve(item)
                    }
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeout))
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
