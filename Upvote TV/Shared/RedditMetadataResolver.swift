import Foundation

/// Resolves a Reddit `QueueItem` to a `Post` using unauthenticated endpoints that are
/// still reachable after Reddit gated the public `.json` API.
///
/// **Why not `.json`:** As of ~June 2026 Reddit blocks `reddit.com/comments/{id}.json`
/// behind the Responsible Builder Policy ("blocked due to a network policy"), regardless
/// of User-Agent. The authenticated OAuth API needs Data API approval (pending).
///
/// **The RSS feed is the primary source.** `reddit.com/comments/{id}.rss` is
/// unauthenticated and carries everything a card needs: the bare post title, the
/// subreddit (properly cased, from `<category term=…>`), the author, the publish date,
/// a `media:thumbnail`, and — crucially — the post's actual media, so `v.redd.it` video
/// still plays in-app.
///
/// **The OpenGraph preview page is a fallback only.** Fetching the post's HTML with a
/// crawler-style User-Agent (`AppConfig.redditPreviewUserAgent`) yields the same social
/// unfurl iMessage/Slack use, but it costs roughly 6x more rate-limit budget than the RSS
/// feed (burst-measured 2026-08-27: ~190 units including its 301 hop, vs ~33) while
/// carrying strictly less information. It is therefore only fetched when RSS fails
/// outright or returns no usable title.
///
/// **Rate limiting is a real constraint, not the whole ballgame.** Reddit meters these
/// endpoints on a ~9000-unit per-60-second per-IP budget; at ~33 units a feed, a 50-post
/// queue costs ~1650 and fits inside one window.
/// Every request goes through `RedditRateLimiter.shared`, which paces the fleet and waits
/// out the window instead of retrying into a 429. See that type for the measurements.
///
/// Both fetches are best-effort — the resolve only throws if *both* fail, so a partial
/// outage still yields a usable card. Restore a JSON/OAuth resolver to this same `Post`
/// shape if Reddit Data API access is later approved (PRD Phase 7).
struct RedditMetadataResolver {
    private let session: URLSession
    private let limiter: RedditRateLimiter

    init(session: URLSession? = nil, limiter: RedditRateLimiter = .shared) {
        self.limiter = limiter
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = AppConfig.resolverTimeout
            config.timeoutIntervalForResource = AppConfig.resolverTimeout
            self.session = URLSession(configuration: config)
        }
    }

    func resolve(_ item: QueueItem) async throws -> ResolvedMetadata {
        let deadline = Date().addingTimeInterval(AppConfig.redditResolveDeadline)

        // RSS first: cheaper and richer than the preview page.
        let media = await fetchMedia(item, before: deadline)

        // Pay for the heavier HTML page when RSS left us without a title — the one gap that
        // would otherwise render the card as a raw URL. A missing thumbnail is worth topping
        // up too, but only out of spare budget: a title is essential, an image is a bonus,
        // and on a cold queue every unit spent here is a unit some other post needs to
        // render at all. (Measured: ~44 of 59 real queue posts carry an RSS thumbnail.)
        var og: OpenGraph?
        if media?.title == nil {
            og = await fetchOpenGraph(item, before: deadline)
        } else if media?.thumbnail == nil, media?.isUnavailable == false {
            og = await fetchOpenGraphOpportunistically(item)
        }

        // Only give up if neither endpoint produced anything usable.
        if og == nil && media == nil {
            throw MetadataResolveError.unreachable
        }

        return try assemble(item: item, og: og, media: media)
    }

    // MARK: - Assembly

    private func assemble(item: QueueItem, og: OpenGraph?, media: RedditMedia?) throws -> ResolvedMetadata {
        // RSS titles are the bare post title; OG's come off the page `<title>` and need the
        // " : r/sub" suffix stripped. Both parsers return nil (never "") on a miss. Neither
        // resolving is treated as a total miss — the caller falls back to a stale cache
        // entry or an un-cached raw-URL card and retries next refresh, rather than caching
        // the URL itself as the title for a full 30 days.
        guard let title = media?.title ?? og?.title else {
            throw MetadataResolveError.unreachable
        }
        // Prefer RSS for the subreddit — `<category term=…>` is exact, where the OG path
        // recovers casing from a page title.
        let subreddit = media?.subreddit ?? og?.subreddit
        let preview = media?.thumbnail ?? og?.preview
        let outbound = media?.outbound ?? media?.canonical ?? og?.canonical ?? item.url

        // A post the author or a mod removed still has a feed entry, but its media is gone.
        // Surface it as an explicit dead card rather than a video that fails on playback.
        if media?.isUnavailable == true {
            return ResolvedMetadata(
                title: Self.unavailableTitle,
                subreddit: subreddit,
                publishedAt: media?.published,
                postType: .unsupported,
                outboundURL: outbound,
                domain: "reddit.com"
            )
        }

        return ResolvedMetadata(
            title: title,
            subreddit: subreddit,
            author: media?.author,
            publishedAt: media?.published,
            postType: media?.postType ?? .link,
            thumbnailURL: preview,
            mediaURL: media?.mediaURL,
            outboundURL: outbound,
            domain: "reddit.com"
        )
    }

    /// Shown in place of `[deleted]` / `[removed]`, which is what Reddit puts in the feed.
    static let unavailableTitle = "Post no longer available on Reddit"

    // MARK: - RSS fetch (primary)

    private struct RedditMedia {
        var postType: PostType
        var mediaURL: URL?
        var outbound: URL?
        var thumbnail: URL?
        var subreddit: String?
        var title: String?
        var author: String?
        var published: Date?
        var canonical: URL?
        var isUnavailable: Bool
    }

    private func fetchMedia(_ item: QueueItem, before deadline: Date) async -> RedditMedia? {
        // `limit=1` asks for the post plus one comment instead of the whole thread. Measured
        // on a real post: 3.5 KB instead of 33.5 KB, and about half the rate-limit units,
        // while still carrying the title, subreddit, author, thumbnail, and media link.
        // Everything past the first <entry> was being downloaded, charged for, and thrown
        // away.
        guard let url = URL(string: "https://www.reddit.com/comments/\(item.id).rss?limit=1"),
              let rss = await fetchString(url, accept: "application/atom+xml,application/xml", before: deadline,
                                           validate: Self.looksLikeAtomFeed) else {
            return nil
        }

        // The post itself is the first <entry>; later entries are comments. Scope media
        // detection to that entry so a commenter's link can't be mistaken for the post.
        let parts = rss.components(separatedBy: "<entry>")
        let postEntry = parts.count > 1 ? parts[1] : rss

        let rawTitle = Self.tagTitle(in: postEntry)
        let unavailable = Self.isUnavailableTitle(rawTitle)
        let subreddit = Self.rssSubreddit(in: postEntry)
        let author = Self.rssAuthor(in: postEntry)
        let published = Self.rssPublished(in: postEntry)
        let canonical = Self.rssCanonical(in: postEntry)

        // `<media:thumbnail>` is absent on plenty of posts; the preview <img> embedded in
        // the entry's escaped HTML content is the same image and covers most of the rest.
        var thumbnail = (Self.metaThumbnail(in: postEntry) ?? Self.contentImage(in: postEntry))
            .flatMap { URL(string: $0) }
        if let candidate = thumbnail, Self.isPlaceholderImage(candidate) { thumbnail = nil }

        func media(_ type: PostType, mediaURL: URL? = nil, outbound: URL? = nil, thumbnail: URL?) -> RedditMedia {
            RedditMedia(postType: type, mediaURL: mediaURL, outbound: outbound,
                        thumbnail: thumbnail, subreddit: subreddit, title: rawTitle,
                        author: author, published: published, canonical: canonical,
                        isUnavailable: unavailable)
        }

        // Priority: Reddit-hosted video → image → external YouTube → plain link.
        if let vid = Self.firstMatch(in: postEntry, pattern: "v\\.redd\\.it/([A-Za-z0-9]+)", group: 1),
           let hls = URL(string: "https://v.redd.it/\(vid)/HLSPlaylist.m3u8") {
            return media(.video, mediaURL: hls, thumbnail: thumbnail)
        }
        if let img = Self.firstMatch(in: postEntry, pattern: "(i\\.redd\\.it/[A-Za-z0-9._-]+)", group: 1),
           let imageURL = URL(string: "https://\(img)") {
            return media(.image, mediaURL: imageURL, thumbnail: thumbnail ?? imageURL)
        }
        if let yt = Self.firstMatch(
            in: Self.decodeEntities(postEntry),
            pattern: "(https?://(?:www\\.)?(?:youtube\\.com/watch\\?v=[\\w-]+|youtu\\.be/[\\w-]+))",
            group: 1
        ), let ytURL = URL(string: yt) {
            return media(.youtube, outbound: ytURL, thumbnail: thumbnail)
        }

        // No recognizable media — a text/self post or external link. Carry what we have.
        return media(.link, thumbnail: thumbnail)
    }

    // MARK: - OpenGraph fetch (fallback)

    private struct OpenGraph {
        var title: String?
        var subreddit: String?
        var preview: URL?
        var canonical: URL?
    }

    private func fetchOpenGraph(_ item: QueueItem, before deadline: Date) async -> OpenGraph? {
        guard let url = URL(string: "https://www.reddit.com/comments/\(item.id)/"),
              let html = await fetchString(url, accept: "text/html,application/xhtml+xml", before: deadline) else {
            return nil
        }
        return Self.parseOpenGraph(html)
    }

    /// Same fetch, but it gives up immediately unless the rate-limit window has room to
    /// spare. Used to fill in a thumbnail without ever delaying or starving a refresh.
    private func fetchOpenGraphOpportunistically(_ item: QueueItem) async -> OpenGraph? {
        guard let url = URL(string: "https://www.reddit.com/comments/\(item.id)/"),
              await limiter.acquireIfBudgetToSpare() else {
            return nil
        }
        // No retry here — this is a bonus thumbnail, so a throttle just means "not today".
        guard case .success(let html, _) = await performGET(url, accept: "text/html,application/xhtml+xml") else {
            return nil
        }
        return Self.parseOpenGraph(html)
    }

    private static func parseOpenGraph(_ html: String) -> OpenGraph? {
        // A page with no `og:` markup at all isn't a real unfurl — likely a bot-check or
        // block page — so its bare <title> must not be read as the post's title.
        let hasOpenGraphMarkup = html.range(of: "property=\"og:", options: .caseInsensitive) != nil
        let pageTitle = hasOpenGraphMarkup ? tagTitle(in: html) : nil
        let ogImage = metaContent(in: html, key: "og:image", attribute: "property")
            ?? metaContent(in: html, key: "twitter:image", attribute: "name")
        let ogURL = metaContent(in: html, key: "og:url", attribute: "property")

        var result = OpenGraph()
        if let pageTitle, let parsed = splitTitleAndSubreddit(pageTitle) {
            result.title = parsed.title
            result.subreddit = parsed.subreddit
        } else {
            result.title = pageTitle ?? metaContent(in: html, key: "og:title", attribute: "property")
        }
        if isUnavailableTitle(result.title) { result.title = nil }
        if result.subreddit == nil {
            result.subreddit = subreddit(fromCanonicalURL: ogURL)
        }
        if let image = ogImage.flatMap({ URL(string: $0) }), !isPlaceholderImage(image) {
            result.preview = image
        }
        result.canonical = ogURL.flatMap { URL(string: $0) }

        // Nothing useful → treat as a miss so the media fetch can still carry the card.
        if result.title == nil && result.preview == nil { return nil }
        return result
    }

    /// Reddit serves a generic branded card as `og:image` for posts with no real preview —
    /// the same image for every such post. It tells the viewer nothing, and the project
    /// style guide rules out Reddit branding outright, so treat it as "no thumbnail".
    static func isPlaceholderImage(_ url: URL) -> Bool {
        let string = url.absoluteString.lowercased()
        if string.contains("o0h58lzmax6a1") { return true }          // the observed default card
        if string.contains("redditstatic.com") { return true }        // brand/static assets
        if string.contains("/default") || string.contains("nsfw.png") { return true }
        return false
    }

    // MARK: - Networking

    private enum FetchOutcome {
        case success(body: String, contentType: String?)
        /// Reddit refused this request for budget reasons (429).
        case throttled
        case failed
    }

    /// Performs a rate-limited GET, waiting for budget if necessary. Returns nil on any
    /// failure — callers are best-effort and `resolve` decides if the post is a total loss.
    /// `validate` gets a look at the body and content-type before it's handed back, so a
    /// 200 that isn't actually the expected document (a block page served on the RSS path,
    /// say) can be treated as a miss instead of parsed as if it were real.
    private func fetchString(
        _ url: URL, accept: String, before deadline: Date,
        validate: (String, String?) -> Bool = { _, _ in true }
    ) async -> String? {
        // A 429 means this request arrived after the budget was already gone — typically
        // because a previous run, another device on the same IP, or the app's own cold
        // start spent the window before the limiter had any reading to go on. That
        // response teaches the limiter when the window resets, so re-entering the gate
        // parks until then and the retry lands in a fresh window. This is not retrying
        // into the wall: `acquire` will not admit until the budget is actually back.
        for _ in 0..<AppConfig.redditThrottleRetries {
            guard await limiter.acquire(before: deadline) else { return nil }
            switch await performGET(url, accept: accept) {
            case .success(let body, let contentType):
                return validate(body, contentType) ? body : nil
            case .throttled: continue
            case .failed: return nil
            }
        }
        return nil
    }

    /// Issues the request and settles up with the limiter. The caller must already hold a
    /// slot from `acquire`/`acquireIfBudgetToSpare`; this always hands exactly one back.
    private func performGET(_ url: URL, accept: String) async -> FetchOutcome {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(AppConfig.redditPreviewUserAgent, forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request) else {
            // No response to learn from, but the slot still has to be handed back.
            await limiter.record(nil)
            return .failed
        }

        let http = response as? HTTPURLResponse
        await limiter.record(http)

        if let http, http.statusCode == 429 { return .throttled }
        if let http, http.statusCode != 200 { return .failed }
        guard let body = String(data: data, encoding: .utf8) else { return .failed }
        return .success(body: body, contentType: http?.value(forHTTPHeaderField: "Content-Type"))
    }

    /// A 200 on the RSS URL isn't proof it's actually the Atom feed — a network-policy block
    /// page comes back with the same status. Require either an XML content-type or the
    /// `<feed` opening tag near the top of the body before trusting the response enough to
    /// parse it; otherwise its bare `<title>` (a block-page heading, not a post title) would
    /// get read as if it were the post's.
    static func looksLikeAtomFeed(body: String, contentType: String?) -> Bool {
        if let contentType, contentType.lowercased().contains("xml") { return true }
        return body.prefix(200).contains("<feed")
    }

    // MARK: - HTML / XML parsing

    /// Extracts and decodes the contents of the first `<title>…</title>` element.
    static func tagTitle(in html: String) -> String? {
        guard let raw = firstMatch(in: html, pattern: "<title[^>]*>(.*?)</title>", group: 1) else {
            return nil
        }
        let decoded = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    /// Reddit puts `[deleted]` or `[removed]` in the feed for posts that are gone. A
    /// moderator or automod removal can also show up dressed differently — `[ Removed by
    /// moderator ]`, `[ Removed by Reddit ]` — so also catch anything fully bracketed that
    /// mentions removal or deletion, without flagging a real title that merely contains
    /// those words.
    static func isUnavailableTitle(_ title: String?) -> Bool {
        guard let title else { return false }
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == "[deleted]" || normalized == "[removed]" { return true }
        guard normalized.hasPrefix("["), normalized.hasSuffix("]") else { return false }
        return normalized.contains("removed") || normalized.contains("deleted")
    }

    /// Returns the decoded `content` of a `<meta>` tag matching `attribute="key"`,
    /// tolerating either attribute order (`property`/`name` before or after `content`).
    static func metaContent(in html: String, key: String, attribute: String) -> String? {
        let k = NSRegularExpression.escapedPattern(for: key)
        let patterns = [
            "<meta[^>]*\(attribute)=\"\(k)\"[^>]*content=\"([^\"]*)\"",
            "<meta[^>]*content=\"([^\"]*)\"[^>]*\(attribute)=\"\(k)\""
        ]
        for pattern in patterns {
            if let raw = firstMatch(in: html, pattern: pattern, group: 1) {
                let decoded = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !decoded.isEmpty { return decoded }
            }
        }
        return nil
    }

    /// `<media:thumbnail url="…"/>` from an RSS entry.
    static func metaThumbnail(in entry: String) -> String? {
        guard let raw = firstMatch(in: entry, pattern: "<media:thumbnail[^>]*url=\"([^\"]*)\"", group: 1) else {
            return nil
        }
        let decoded = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    /// The preview `<img>` inside an RSS entry's `<content>`, which is HTML escaped inside
    /// the XML — so the markup needs one decode pass to find, and the URL another to use.
    static func contentImage(in entry: String) -> String? {
        guard let rawContent = firstMatch(in: entry, pattern: "<content[^>]*>(.*?)</content>", group: 1) else {
            return nil
        }
        let markup = decodeEntities(rawContent)
        guard let src = firstMatch(in: markup, pattern: "<img[^>]*src=\"([^\"]*)\"", group: 1) else {
            return nil
        }
        let decoded = decodeEntities(src).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.isEmpty ? nil : decoded
    }

    /// Subreddit from an RSS entry's `<category term="sub" label="r/sub"/>`, skipping the
    /// junk domain-based category Reddit emits at the feed level (term has a leading space).
    static func rssSubreddit(in entry: String) -> String? {
        guard let term = firstMatch(
            in: entry,
            pattern: "<category term=\"([A-Za-z0-9_]+)\" label=\"r/",
            group: 1
        ), !term.isEmpty else { return nil }
        return term
    }

    /// Author from an RSS entry's `<author><name>/u/name</name></author>`, without the `/u/`.
    static func rssAuthor(in entry: String) -> String? {
        guard let raw = firstMatch(in: entry, pattern: "<author>.*?<name>(.*?)</name>", group: 1) else {
            return nil
        }
        var name = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("/u/") { name.removeFirst(3) }
        return name.isEmpty ? nil : name
    }

    /// The post's `<published>` timestamp (ISO 8601), which is when it went up on Reddit —
    /// distinct from `sharedAt`, which is when someone in the house queued it.
    static func rssPublished(in entry: String) -> Date? {
        guard let raw = firstMatch(in: entry, pattern: "<published>(.*?)</published>", group: 1) else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: trimmed) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: trimmed)
    }

    /// The entry's canonical permalink, `<link href="…"/>`.
    static func rssCanonical(in entry: String) -> URL? {
        guard let raw = firstMatch(in: entry, pattern: "<link[^>]*href=\"([^\"]*)\"", group: 1) else {
            return nil
        }
        return URL(string: decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Splits Reddit's "{post title} : r/{subreddit}" page title into its parts.
    static func splitTitleAndSubreddit(_ pageTitle: String) -> (title: String, subreddit: String)? {
        guard let range = pageTitle.range(of: " : r/[A-Za-z0-9_]+$", options: .regularExpression) else {
            return nil
        }
        let title = String(pageTitle[pageTitle.startIndex..<range.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = pageTitle[range]
        guard let rSlash = suffix.range(of: "r/") else { return nil }
        let subreddit = String(suffix[rSlash.upperBound...])
        guard !title.isEmpty, !subreddit.isEmpty else { return nil }
        return (title, subreddit)
    }

    /// Extracts the subreddit from a canonical URL like `…/r/{subreddit}/comments/…`.
    static func subreddit(fromCanonicalURL urlString: String?) -> String? {
        guard let urlString,
              let match = firstMatch(in: urlString, pattern: "/r/([A-Za-z0-9_]+)/", group: 1),
              !match.isEmpty else {
            return nil
        }
        return match
    }

    // MARK: - Regex + entity helpers

    static func firstMatch(in text: String, pattern: String, group: Int) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > group,
              let r = Range(match.range(at: group), in: text) else {
            return nil
        }
        return String(text[r])
    }

    /// Decodes the small set of HTML entities Reddit emits in titles/meta/feeds,
    /// including numeric (decimal and hex) character references.
    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = s
        let named: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " ")
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = replaceNumericEntities(result)
        // `&amp;` must go last, otherwise `&amp;lt;` would decode two levels in one pass.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    private static func replaceNumericEntities(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&#(x?)([0-9A-Fa-f]+);") else {
            return s
        }
        let nsString = s as NSString
        var result = s
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: nsString.length))
        for match in matches.reversed() {
            let isHex = nsString.substring(with: match.range(at: 1)) == "x"
            let digits = nsString.substring(with: match.range(at: 2))
            guard let code = UInt32(digits, radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(code) else { continue }
            let full = nsString.substring(with: match.range)
            result = result.replacingOccurrences(of: full, with: String(scalar))
        }
        return result
    }
}
