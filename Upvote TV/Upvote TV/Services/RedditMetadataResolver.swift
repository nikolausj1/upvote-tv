import Foundation

/// Resolves a Reddit QueueItem to a full `Post` via the public web JSON endpoint
/// `https://www.reddit.com/comments/{id}.json`.
///
/// No authentication required. Structure matches the authenticated API;
/// this is the same JSON reddit.com serves to search engines.
struct RedditMetadataResolver {
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = AppConfig.resolverTimeout
            config.timeoutIntervalForResource = AppConfig.resolverTimeout
            // tvOS is fine with the default user agent for reddit.com's web endpoint.
            self.session = URLSession(configuration: config)
        }
    }

    func resolve(_ item: QueueItem) async throws -> Post {
        guard let url = URL(string: "https://www.reddit.com/comments/\(item.id).json?raw_json=1") else {
            throw ContentProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // A descriptive UA avoids reddit's generic-client throttling.
        request.setValue("UpvoteTV/1.0 (tvOS; personal use)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                break
            case 429:
                throw ContentProviderError.rateLimited
            default:
                throw ContentProviderError.networkError
            }
        }

        let decoded: Root
        do {
            decoded = try JSONDecoder().decode(Root.self, from: data)
        } catch {
            throw ContentProviderError.invalidResponse
        }

        guard let child = decoded.first?.data.children.first else {
            throw ContentProviderError.invalidResponse
        }
        return normalize(child.data, queueItem: item)
    }

    // MARK: - Normalization

    private func normalize(_ data: PostData, queueItem: QueueItem) -> Post {
        let type = classify(data)
        let createdAt = Date(timeIntervalSince1970: data.created_utc ?? 0)
        let domain = data.domain

        var mediaURL: URL?
        var previewImage: URL?
        var thumbnail: URL?
        var galleryItems: [GalleryItem]?
        var outbound: URL?
        var textBody: String?

        switch type {
        case .video:
            if let redditVideo = data.media?.reddit_video {
                mediaURL = URL(string: redditVideo.hls_url ?? redditVideo.fallback_url ?? "")
            }
            previewImage = bestPreview(from: data.preview, targetWidth: 1920)
            thumbnail = bestPreview(from: data.preview, targetWidth: 480)

        case .image:
            // Use the source URL when it's an i.redd.it or imgur direct link.
            if let direct = data.url_overridden_by_dest, let u = URL(string: direct) {
                mediaURL = u
            }
            previewImage = bestPreview(from: data.preview, targetWidth: 1920) ?? mediaURL
            thumbnail = bestPreview(from: data.preview, targetWidth: 480) ?? mediaURL

        case .gallery:
            galleryItems = buildGalleryItems(data)
            previewImage = galleryItems?.first?.imageURL
            thumbnail = bestPreview(from: data.preview, targetWidth: 480) ?? previewImage

        case .text:
            textBody = data.selftext

        case .youtube:
            if let dest = data.url_overridden_by_dest, let u = URL(string: dest) {
                outbound = u
            }
            previewImage = bestPreview(from: data.preview, targetWidth: 1920)
            thumbnail = bestPreview(from: data.preview, targetWidth: 480)

        case .link, .unsupported:
            if let dest = data.url_overridden_by_dest, let u = URL(string: dest) {
                outbound = u
            }
            previewImage = bestPreview(from: data.preview, targetWidth: 1920)
            thumbnail = bestPreview(from: data.preview, targetWidth: 480)
        }

        return Post(
            id: queueItem.id,
            title: data.title ?? "(no title)",
            subreddit: data.subreddit,
            author: data.author,
            createdAt: createdAt,
            postType: type,
            thumbnailURL: thumbnail,
            previewImageURL: previewImage,
            mediaURL: mediaURL,
            galleryItems: galleryItems,
            textBody: textBody,
            outboundURL: outbound,
            domain: domain,
            isNSFW: data.over_18 ?? false,
            score: data.score,
            sharedAt: queueItem.sharedAt,
            resolvedAt: Date()
        )
    }

    private func classify(_ data: PostData) -> PostType {
        if let domain = data.domain {
            if domain.contains("youtube.com") || domain.contains("youtu.be") {
                return .youtube
            }
        }
        if data.is_gallery == true { return .gallery }
        if data.is_video == true { return .video }
        if let hint = data.post_hint {
            switch hint {
            case "hosted:video", "rich:video": return .video
            case "image": return .image
            case "self": return .text
            case "link": return .link
            default: break
            }
        }
        if data.is_self == true { return .text }
        if let domain = data.domain {
            if domain == "i.redd.it" { return .image }
            if domain == "v.redd.it" { return .video }
            if domain == "reddit.com" { return .link }
        }
        if data.url_overridden_by_dest != nil { return .link }
        return .unsupported
    }

    /// Picks the preview resolution closest to `targetWidth` without exceeding it excessively.
    private func bestPreview(from preview: Preview?, targetWidth: Int) -> URL? {
        guard let images = preview?.images, let first = images.first else { return nil }
        var candidates: [(Int, String)] = first.resolutions.compactMap { ($0.width, $0.url) }
        if let source = first.source {
            candidates.append((source.width, source.url))
        }
        // Sort by |width - target|, prefer widths <= target if a tie.
        let best = candidates.min { lhs, rhs in
            let dl = abs(lhs.0 - targetWidth)
            let dr = abs(rhs.0 - targetWidth)
            if dl != dr { return dl < dr }
            return lhs.0 < rhs.0
        }
        guard let best else { return nil }
        return URL(string: best.1)
    }

    private func buildGalleryItems(_ data: PostData) -> [GalleryItem]? {
        guard let galleryData = data.gallery_data,
              let metadata = data.media_metadata else {
            return nil
        }
        var items: [GalleryItem] = []
        for (index, entry) in galleryData.items.enumerated() {
            guard let meta = metadata[entry.media_id] else { continue }
            // Prefer the source URL. Fall back to the largest preview.
            let best: MediaMetadata.Resolution?
            if let s = meta.s {
                best = s
            } else {
                best = meta.p?.max(by: { ($0.x ?? 0) < ($1.x ?? 0) })
            }
            guard let best,
                  let urlString = best.u,
                  let url = URL(string: urlString) else { continue }
            items.append(
                GalleryItem(
                    id: entry.media_id,
                    imageURL: url,
                    width: best.x ?? 1920,
                    height: best.y ?? 1080,
                    position: index
                )
            )
        }
        return items.isEmpty ? nil : items
    }

    // MARK: - Wire format

    private typealias Root = [Listing]

    private struct Listing: Decodable {
        let data: ListingData
    }

    private struct ListingData: Decodable {
        let children: [Child]
    }

    private struct Child: Decodable {
        let data: PostData
    }

    private struct PostData: Decodable {
        let id: String?
        let title: String?
        let subreddit: String?
        let author: String?
        let created_utc: TimeInterval?
        let over_18: Bool?
        let score: Int?
        let domain: String?
        let selftext: String?
        let is_self: Bool?
        let is_video: Bool?
        let is_gallery: Bool?
        let post_hint: String?
        let url_overridden_by_dest: String?
        let media: Media?
        let preview: Preview?
        let gallery_data: GalleryData?
        let media_metadata: [String: MediaMetadata]?
    }

    private struct Media: Decodable {
        let reddit_video: RedditVideo?
    }

    private struct RedditVideo: Decodable {
        let hls_url: String?
        let fallback_url: String?
    }

    private struct Preview: Decodable {
        let images: [PreviewImage]
    }

    private struct PreviewImage: Decodable {
        let source: Source?
        let resolutions: [Source]

        struct Source: Decodable {
            let url: String
            let width: Int
            let height: Int
        }
    }

    private struct GalleryData: Decodable {
        let items: [GalleryEntry]
    }

    private struct GalleryEntry: Decodable {
        let media_id: String
    }

    private struct MediaMetadata: Decodable {
        let s: Resolution?
        let p: [Resolution]?

        struct Resolution: Decodable {
            let u: String?
            let x: Int?
            let y: Int?
        }
    }
}
