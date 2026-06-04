import Foundation

/// Resolves a Reddit `QueueItem` to a `Post` using two unauthenticated endpoints that
/// are still reachable after Reddit gated the public `.json` API.
///
/// **Why not `.json`:** As of ~June 2026 Reddit blocks `reddit.com/comments/{id}.json`
/// behind the Responsible Builder Policy ("blocked due to a network policy"), regardless
/// of User-Agent. The authenticated OAuth API needs Data API approval (pending).
///
/// **What we use instead (per post, fetched concurrently):**
/// 1. **OpenGraph preview page** — the post's HTML fetched with a crawler-style UA
///    (`AppConfig.redditPreviewUserAgent`). Reddit serves social-unfurl `<meta>` tags:
///    a clean title (page `<title>` = `"{title} : r/{sub}"`), subreddit, and a preview
///    image. This is the same surface iMessage/Slack/Discord use.
/// 2. **RSS feed** (`reddit.com/comments/{id}.rss`) — still unauthenticated, and crucially
///    it exposes the post's **actual media**: the `v.redd.it` video id (→ a playable HLS
///    stream), `i.redd.it` images, or an outbound YouTube link. The OG page is stripped of
///    media, so RSS is what restores in-app playback.
///
/// Title/subreddit/thumbnail come from OG (cleaner); post type + media come from RSS.
/// Both fetches are best-effort — the resolve only throws if *both* fail, so a partial
/// outage still yields a usable card. Restore a JSON/OAuth resolver to this same `Post`
/// shape if Reddit Data API access is later approved (PRD Phase 7).
struct RedditMetadataResolver {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = AppConfig.resolverTimeout
            config.timeoutIntervalForResource = AppConfig.resolverTimeout
            self.session = URLSession(configuration: config)
        }
    }

    func resolve(_ item: QueueItem) async throws -> Post {
        async let ogTask = fetchOpenGraph(item)
        async let mediaTask = fetchMedia(item)
        let og = await ogTask
        let media = await mediaTask

        // Only give up if neither endpoint produced anything usable.
        if og == nil && media == nil {
            throw ContentProviderError.networkError
        }

        return assemble(item: item, og: og, media: media)
    }

    // MARK: - Assembly

    private func assemble(item: QueueItem, og: OpenGraph?, media: RedditMedia?) -> Post {
        var title = og?.title ?? item.url.absoluteString
        if title.isEmpty { title = item.url.absoluteString }
        let subreddit = og?.subreddit ?? media?.subreddit
        let preview = media?.thumbnail ?? og?.preview
        let outbound = media?.outbound ?? og?.canonical ?? item.url

        let postType = media?.postType ?? .link

        return Post(
            id: item.id,
            title: title,
            subreddit: subreddit,
            author: nil,
            createdAt: item.sharedAt,
            postType: postType,
            thumbnailURL: preview,
            previewImageURL: preview,
            mediaURL: media?.mediaURL,
            galleryItems: nil,
            textBody: nil,
            outboundURL: outbound,
            domain: "reddit.com",
            isNSFW: false,
            score: nil,
            sharedAt: item.sharedAt,
            resolvedAt: Date()
        )
    }

    // MARK: - OpenGraph fetch

    private struct OpenGraph {
        var title: String?
        var subreddit: String?
        var preview: URL?
        var canonical: URL?
    }

    private func fetchOpenGraph(_ item: QueueItem) async -> OpenGraph? {
        guard let url = URL(string: "https://www.reddit.com/comments/\(item.id)/"),
              let html = await fetchString(url, accept: "text/html,application/xhtml+xml") else {
            return nil
        }

        let pageTitle = Self.tagTitle(in: html)
        let ogImage = Self.metaContent(in: html, key: "og:image", attribute: "property")
            ?? Self.metaContent(in: html, key: "twitter:image", attribute: "name")
        let ogURL = Self.metaContent(in: html, key: "og:url", attribute: "property")

        var result = OpenGraph()
        if let pageTitle, let parsed = Self.splitTitleAndSubreddit(pageTitle) {
            result.title = parsed.title
            result.subreddit = parsed.subreddit
        } else {
            result.title = pageTitle ?? Self.metaContent(in: html, key: "og:title", attribute: "property")
        }
        if result.subreddit == nil {
            result.subreddit = Self.subreddit(fromCanonicalURL: ogURL)
        }
        result.preview = ogImage.flatMap { URL(string: $0) }
        result.canonical = ogURL.flatMap { URL(string: $0) }

        // Nothing useful → treat as a miss so the media fetch can still carry the card.
        if result.title == nil && result.preview == nil { return nil }
        return result
    }

    // MARK: - RSS media fetch

    private struct RedditMedia {
        var postType: PostType
        var mediaURL: URL?
        var outbound: URL?
        var thumbnail: URL?
        var subreddit: String?
    }

    private func fetchMedia(_ item: QueueItem) async -> RedditMedia? {
        guard let url = URL(string: "https://www.reddit.com/comments/\(item.id).rss"),
              let rss = await fetchString(url, accept: "application/atom+xml,application/xml") else {
            return nil
        }

        // The post itself is the first <entry>; later entries are comments. Scope media
        // detection to that entry so a commenter's link can't be mistaken for the post.
        let parts = rss.components(separatedBy: "<entry>")
        let postEntry = parts.count > 1 ? parts[1] : rss

        let thumbnail = Self.metaThumbnail(in: postEntry).flatMap { URL(string: $0) }
        let subreddit = Self.rssSubreddit(in: postEntry)

        // Priority: Reddit-hosted video → image → external YouTube → plain link.
        if let vid = Self.firstMatch(in: postEntry, pattern: "v\\.redd\\.it/([A-Za-z0-9]+)", group: 1),
           let hls = URL(string: "https://v.redd.it/\(vid)/HLSPlaylist.m3u8") {
            return RedditMedia(postType: .video, mediaURL: hls, outbound: nil,
                               thumbnail: thumbnail, subreddit: subreddit)
        }
        if let img = Self.firstMatch(in: postEntry, pattern: "(i\\.redd\\.it/[A-Za-z0-9._-]+)", group: 1),
           let imageURL = URL(string: "https://\(img)") {
            return RedditMedia(postType: .image, mediaURL: imageURL, outbound: nil,
                               thumbnail: thumbnail ?? imageURL, subreddit: subreddit)
        }
        if let yt = Self.firstMatch(
            in: Self.decodeEntities(postEntry),
            pattern: "(https?://(?:www\\.)?(?:youtube\\.com/watch\\?v=[\\w-]+|youtu\\.be/[\\w-]+))",
            group: 1
        ), let ytURL = URL(string: yt) {
            return RedditMedia(postType: .youtube, mediaURL: nil, outbound: ytURL,
                               thumbnail: thumbnail, subreddit: subreddit)
        }

        // No recognizable media — a text/self post or external link. Carry what we have.
        return RedditMedia(postType: .link, mediaURL: nil, outbound: nil,
                           thumbnail: thumbnail, subreddit: subreddit)
    }

    // MARK: - Networking

    private func fetchString(_ url: URL, accept: String) async -> String? {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(AppConfig.redditPreviewUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request) else { return nil }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
        return String(data: data, encoding: .utf8)
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
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " ")
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }
        result = replaceNumericEntities(result)
        return result
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
