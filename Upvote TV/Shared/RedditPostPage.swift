import Foundation

/// The full `reddit.com/comments/{id}/` post page, reduced to the fields a card needs.
///
/// **Why this exists.** Reddit announced (r/modnews `1wubgvt`, 2026-09-30) that RSS feeds
/// stop on 2026-11-13. The feed was the only *public* surface carrying the `v.redd.it`
/// video URL; the OpenGraph preview page never has. The full post page does: Reddit's own
/// web client renders the post from a `<shreddit-post>` element whose attributes carry the
/// title, type, subreddit, author, timestamp and media link, plus a `<shreddit-player>`
/// whose `src` is the HLS playlist. Probed 2026-10-09 against the live queue: 8 of 8 posts,
/// every video with a playable HLS URL, from a plain tvOS-style User-Agent.
///
/// **The challenge.** The page sits behind a small JavaScript interstitial. The served
/// script computes `solution = constant + constant` for a 16-character constant embedded in
/// the script, then re-requests the same URL with `solution`, `js_challenge=1` and the form's
/// `jsc_token` as query parameters. The response sets session cookies (`token_v2`, `loid`)
/// that skip the challenge for the rest of the session, so a cookie-keeping `URLSession`
/// solves it once per resolver, not once per post. `Challenge` recognises exactly that
/// shape and nothing else: if Reddit changes the solver, `challenge(in:)` returns nil and
/// the resolver falls through to OpenGraph instead of submitting a wrong answer.
///
/// **The budget.** This page is metered separately from the feed and OpenGraph endpoints:
/// ~225 units per ~6-minute window at 2 units a page (`RedditRateLimiter.Profile.page`).
/// The pages are heavy (~1.1 MB each) but a 100-item queue still fits in one window.
///
/// Parsing is regex over the raw HTML, same as the rest of the resolver: the page is a
/// megabyte of markup and the handful of attributes read here live on two elements.
struct RedditPostPage: Equatable, Sendable {
    /// `post-type` attribute as Reddit emits it: `video`, `image`, `gallery`, `link`,
    /// `text`, `crosspost`, …
    var postType: String?
    var title: String?
    /// Bare subreddit name (`sports`, not `r/sports`).
    var subreddit: String?
    var author: String?
    var published: Date?
    /// `content-href`: the post's own media (`https://v.redd.it/{id}`, an `i.redd.it`
    /// image) or, for link posts, the outbound URL. For removed posts Reddit points it back
    /// at the permalink.
    var contentHref: URL?
    var domain: String?
    /// The HLS playlist from `<shreddit-player src>`, reduced to its stable, unsigned form.
    var hlsURL: URL?
    /// The player's `poster`, or the first preview image in the post. Best effort.
    var previewImage: URL?
    var permalink: URL?
    /// `nsfw` boolean attribute on `<shreddit-post>`. The feed never carried this, so the
    /// NSFW toggle has had nothing to act on for Reddit items since the `.json` API closed.
    var isNSFW: Bool
    /// Author-deleted, or removed by a moderator or by Reddit. Reddit strips the title
    /// to `[deleted]` / `[ Removed by moderator ]` and/or sets `moderation-verdict`.
    var isUnavailable: Bool

    // MARK: - Parsing

    /// Parses the page. Returns nil unless a `<shreddit-post>` element is present, so a
    /// block page, a login wall or an unsolved challenge can never be read as a post.
    static func parse(_ html: String) -> RedditPostPage? {
        guard let postTag = RedditMetadataResolver.firstMatch(in: html, pattern: "<shreddit-post\\b([^>]*)>", group: 1) else {
            return nil
        }
        let attrs = attributes(in: postTag)

        var page = RedditPostPage(isNSFW: false, isUnavailable: false)
        page.postType = attrs["post-type"]
        page.title = attrs["post-title"].flatMap { $0.isEmpty ? nil : $0 }
        page.subreddit = attrs["subreddit-name"]
            ?? attrs["subreddit-prefixed-name"].map { $0.hasPrefix("r/") ? String($0.dropFirst(2)) : $0 }
        page.author = attrs["author"].flatMap { $0.isEmpty || $0 == "[deleted]" ? nil : $0 }
        page.published = attrs["created-timestamp"].flatMap(parseTimestamp)
        page.contentHref = attrs["content-href"].flatMap { URL(string: $0) }
        page.domain = attrs["domain"]
        page.permalink = attrs["permalink"].flatMap { URL(string: $0, relativeTo: URL(string: "https://www.reddit.com"))?.absoluteURL }
        page.isNSFW = attrs["nsfw"] != nil

        let verdict = attrs["moderation-verdict"] ?? ""
        page.isUnavailable = RedditMetadataResolver.isUnavailableTitle(page.title)
            || verdict.lowercased().contains("removed")
            || attrs["author"] == "[deleted]"

        if let playerTag = RedditMetadataResolver.firstMatch(in: html, pattern: "<shreddit-player\\b([^>]*)>", group: 1) {
            let playerAttrs = attributes(in: playerTag)
            page.hlsURL = playerAttrs["src"].flatMap { URL(string: $0) }.flatMap(stableHLSURL)
            page.previewImage = playerAttrs["poster"].flatMap { URL(string: $0) }
        }
        if page.hlsURL == nil, let href = page.contentHref, let hls = stableHLSURL(href) {
            // `content-href` is the bare `https://v.redd.it/{id}`; the player tag can be
            // missing on a page served without the media slot.
            page.hlsURL = hls
        }
        if page.previewImage == nil {
            page.previewImage = firstPreviewImage(in: html)
        }
        if let image = page.previewImage, RedditMetadataResolver.isPlaceholderImage(image) {
            page.previewImage = nil
        }
        return page
    }

    /// `name="value"` pairs from one tag's attribute string, entity-decoded. Boolean
    /// attributes (`nsfw`, `is-embeddable`) appear with an empty value.
    static func attributes(in tag: String) -> [String: String] {
        var result: [String: String] = [:]
        guard let regex = try? NSRegularExpression(pattern: "\\s([a-zA-Z][\\w-]*)(?:=\"([^\"]*)\")?") else {
            return result
        }
        let ns = tag as NSString
        for match in regex.matches(in: tag, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1)).lowercased()
            let value = match.range(at: 2).location == NSNotFound ? "" : ns.substring(with: match.range(at: 2))
            if result[name] == nil {
                result[name] = RedditMetadataResolver.decodeEntities(value)
            }
        }
        return result
    }

    /// Reddit's `created-timestamp` looks like `2026-10-05T15:41:09.265000+0000`: six
    /// fractional digits and a numeric offset without a colon, which ISO8601DateFormatter
    /// rejects. Normalise, then parse.
    static func parseTimestamp(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // "+0000" → "+00:00"
        if let offset = s.range(of: "[+-]\\d{4}$", options: .regularExpression) {
            let o = s[offset]
            s.replaceSubrange(offset, with: "\(o.prefix(3)):\(o.suffix(2))")
        }
        // Trim fractional seconds to three digits (the formatter accepts at most that many).
        if let dot = s.range(of: ".", options: .literal), let end = s[dot.upperBound...].firstIndex(where: { !$0.isNumber }) {
            let digits = s[dot.upperBound..<end]
            if digits.count > 3 {
                s.replaceSubrange(dot.upperBound..<end, with: digits.prefix(3))
            }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: s) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }

    /// Reduces any `v.redd.it` URL (the bare `content-href`, or the player's signed, query-
    /// laden playlist) to `https://v.redd.it/{id}/HLSPlaylist.m3u8`. The signed form carries
    /// an expiry; the bare playlist has played without one for the life of this project and
    /// matches what the RSS path has always cached, so a post resolved either way looks the
    /// same in the cache.
    static func stableHLSURL(_ url: URL) -> URL? {
        guard url.host?.lowercased() == "v.redd.it" else { return nil }
        guard let id = url.pathComponents.dropFirst().first, !id.isEmpty,
              id.range(of: "^[A-Za-z0-9]+$", options: .regularExpression) != nil else { return nil }
        return URL(string: "https://v.redd.it/\(id)/HLSPlaylist.m3u8")
    }

    /// First post-content preview image on the page. Avatars and subreddit icons also live
    /// on `preview.redd.it`/`styles.redditmedia.com`, so this is restricted to
    /// `external-preview.redd.it` and to `preview.redd.it` paths that are not avatars.
    static func firstPreviewImage(in html: String) -> URL? {
        let candidates = [
            "(https://external-preview\\.redd\\.it/[^\"'\\s<]+)",
            "(https://preview\\.redd\\.it/(?!snoovatar|avatars)[^\"'\\s<]+)",
            "(https://i\\.redd\\.it/[A-Za-z0-9._-]+)"
        ]
        for pattern in candidates {
            if let raw = RedditMetadataResolver.firstMatch(in: html, pattern: pattern, group: 1),
               let url = URL(string: RedditMetadataResolver.decodeEntities(raw)) {
                return url
            }
        }
        return nil
    }

    // MARK: - Challenge

    /// The JavaScript interstitial Reddit serves ahead of the post page, and its answer.
    struct Challenge: Equatable, Sendable {
        /// `<input name="jsc_token" value="…">` from the hidden form.
        var token: String
        /// The constant the served script doubles: `(async e=>e+e)("…")`.
        var constant: String

        var solution: String { constant + constant }

        /// Recognises the interstitial. Returns nil for anything that is not exactly the
        /// known `e+e` solver, so an unfamiliar challenge is treated as a miss rather than
        /// answered wrongly.
        static func challenge(in html: String) -> Challenge? {
            guard html.contains("js_challenge"),
                  let token = RedditMetadataResolver.firstMatch(
                    in: html, pattern: "name=\"jsc_token\"\\s+value=\"([^\"]+)\"", group: 1),
                  let constant = RedditMetadataResolver.firstMatch(
                    in: html, pattern: "\\(async e=>e\\+e\\)\\(\"([^\"]+)\"\\)", group: 1),
                  !token.isEmpty, !constant.isEmpty else {
                return nil
            }
            return Challenge(token: token, constant: constant)
        }

        /// The URL the served script would navigate to: the same page with the answer in
        /// the query string. Parameter order matches the form so the request looks like the
        /// browser's.
        func solvedURL(for pageURL: URL) -> URL? {
            guard var components = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) else { return nil }
            var items = components.queryItems ?? []
            items.removeAll { ["solution", "js_challenge", "jsc_token", "jsc_orig_r"].contains($0.name) }
            items.append(contentsOf: [
                URLQueryItem(name: "solution", value: solution),
                URLQueryItem(name: "js_challenge", value: "1"),
                URLQueryItem(name: "jsc_token", value: token),
                URLQueryItem(name: "jsc_orig_r", value: "")
            ])
            components.queryItems = items
            return components.url
        }
    }
}
