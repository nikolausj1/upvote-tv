import Foundation

/// Classifies a shared URL into a `QueueItem` ready to be appended to the queue.
///
/// Used by the iOS Share Extension to turn a URL from the share sheet into something
/// the tvOS app can hydrate. Also used by the tvOS-side Reddit resolver to spot
/// YouTube-linked Reddit posts.
///
/// Supported inputs:
/// - `reddit.com/r/<sub>/comments/<id>/...` (any subdomain: www, old, new, np, m)
/// - `redd.it/<id>` (short link)
/// - `youtube.com/watch?v=<id>` (any subdomain: www, m, music)
/// - `youtu.be/<id>`
/// - `youtube.com/shorts/<id>`
/// - `youtube.com/live/<id>`
enum URLClassifier {
    /// Attempts to classify `url` into a `QueueItem`. Returns `nil` if the URL
    /// is neither a supported Reddit nor YouTube post.
    static func classify(_ url: URL, sharedAt: Date = Date()) -> QueueItem? {
        if let redditID = extractRedditID(from: url) {
            let canonical = URL(string: "https://www.reddit.com/comments/\(redditID)") ?? url
            return QueueItem(id: redditID, url: canonical, source: .reddit, sharedAt: sharedAt)
        }
        if let youtubeID = extractYouTubeID(from: url) {
            let canonical = URL(string: "https://www.youtube.com/watch?v=\(youtubeID)") ?? url
            return QueueItem(id: youtubeID, url: canonical, source: .youtube, sharedAt: sharedAt)
        }
        return nil
    }

    // MARK: - Reddit

    /// Extracts the short Reddit post id from a URL, or nil if the URL isn't a Reddit post.
    static func extractRedditID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        // redd.it/<id>
        if host == "redd.it" {
            let id = url.pathComponents.dropFirst().first ?? ""
            return isValidRedditID(String(id)) ? String(id) : nil
        }

        // reddit.com variants
        let isReddit = host == "reddit.com"
            || host.hasSuffix(".reddit.com")
        guard isReddit else { return nil }

        // Reject media subdomains — they aren't post URLs.
        if host == "i.redd.it" || host == "v.redd.it" { return nil }

        // Canonical /r/<sub>/comments/<id>/... or /comments/<id>/...
        let parts = url.pathComponents.filter { $0 != "/" }
        if let idx = parts.firstIndex(of: "comments"), idx + 1 < parts.count {
            let id = parts[idx + 1]
            return isValidRedditID(id) ? id : nil
        }
        return nil
    }

    /// Reddit post IDs are base-36 (alphanumeric lowercase), historically 5–8 chars.
    /// Accept 4–10 to be forward-compatible.
    private static func isValidRedditID(_ candidate: String) -> Bool {
        guard candidate.count >= 4, candidate.count <= 10 else { return false }
        return candidate.allSatisfy { $0.isLetter || $0.isNumber }
    }

    // MARK: - YouTube

    /// Extracts the YouTube video id from a URL, or nil if the URL isn't a YouTube video.
    static func extractYouTubeID(from url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }

        // youtu.be/<id>
        if host == "youtu.be" {
            let id = url.pathComponents.dropFirst().first ?? ""
            return isValidYouTubeID(String(id)) ? String(id) : nil
        }

        // youtube.com, m.youtube.com, music.youtube.com, www.youtube.com
        let isYouTube = host == "youtube.com"
            || host.hasSuffix(".youtube.com")
        guard isYouTube else { return nil }

        // watch?v=<id>
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let v = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidYouTubeID(v) {
            return v
        }

        // /shorts/<id>, /live/<id>, /embed/<id>, /v/<id>
        let parts = url.pathComponents.filter { $0 != "/" }
        for segment in ["shorts", "live", "embed", "v"] {
            if let idx = parts.firstIndex(of: segment), idx + 1 < parts.count {
                let id = parts[idx + 1]
                return isValidYouTubeID(id) ? id : nil
            }
        }
        return nil
    }

    /// YouTube video IDs are 11 characters — alphanumeric plus underscore and hyphen.
    private static func isValidYouTubeID(_ candidate: String) -> Bool {
        guard candidate.count == 11 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return candidate.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
