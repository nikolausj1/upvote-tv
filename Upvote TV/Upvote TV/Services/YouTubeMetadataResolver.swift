import Foundation

/// Resolves a YouTube QueueItem to a `Post` via the public oEmbed endpoint
/// `https://www.youtube.com/oembed?url={videoUrl}&format=json`.
struct YouTubeMetadataResolver {
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
        guard item.source == .youtube else {
            throw ContentProviderError.invalidResponse
        }

        // oEmbed accepts any canonical YouTube URL (watch, youtu.be, shorts, live).
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else {
            throw ContentProviderError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: item.url.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else {
            throw ContentProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                break
            case 401, 403, 404:
                // Unlisted/private/removed videos return these.
                throw ContentProviderError.invalidResponse
            case 429:
                throw ContentProviderError.rateLimited
            default:
                throw ContentProviderError.networkError
            }
        }

        let decoded: OEmbedResponse
        do {
            decoded = try JSONDecoder().decode(OEmbedResponse.self, from: data)
        } catch {
            throw ContentProviderError.invalidResponse
        }

        return Post(
            id: item.id,
            title: decoded.title ?? "(no title)",
            subreddit: nil,
            author: decoded.author_name,
            createdAt: item.sharedAt, // oEmbed doesn't expose upload date; use sharedAt as proxy
            postType: .youtube,
            thumbnailURL: decoded.thumbnail_url.flatMap { URL(string: $0) },
            previewImageURL: decoded.thumbnail_url.flatMap { URL(string: $0) },
            mediaURL: nil,
            galleryItems: nil,
            textBody: nil,
            outboundURL: item.url,
            domain: item.url.host,
            isNSFW: false,
            score: nil,
            sharedAt: item.sharedAt,
            resolvedAt: Date()
        )
    }

    private struct OEmbedResponse: Decodable {
        let title: String?
        let author_name: String?
        let thumbnail_url: String?
        let thumbnail_width: Int?
        let thumbnail_height: Int?
    }
}
