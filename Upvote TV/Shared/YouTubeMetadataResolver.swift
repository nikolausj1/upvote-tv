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

    func resolve(_ item: QueueItem) async throws -> ResolvedMetadata {
        guard item.source == .youtube else {
            throw MetadataResolveError.invalidResponse
        }

        // oEmbed accepts any canonical YouTube URL (watch, youtu.be, shorts, live).
        guard var components = URLComponents(string: "https://www.youtube.com/oembed") else {
            throw MetadataResolveError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: item.url.absoluteString),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components.url else {
            throw MetadataResolveError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw MetadataResolveError.unreachable
        }

        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                break
            case 401, 403, 404:
                // Unlisted/private/removed videos return these.
                throw MetadataResolveError.invalidResponse
            case 429:
                throw MetadataResolveError.rateLimited
            default:
                throw MetadataResolveError.unreachable
            }
        }

        let decoded: OEmbedResponse
        do {
            decoded = try JSONDecoder().decode(OEmbedResponse.self, from: data)
        } catch {
            throw MetadataResolveError.invalidResponse
        }

        return ResolvedMetadata(
            title: decoded.title ?? "(no title)",
            author: decoded.author_name,
            // oEmbed doesn't expose the upload date; leave it nil rather than pass off
            // `sharedAt` as a publish date.
            publishedAt: nil,
            postType: .youtube,
            thumbnailURL: decoded.thumbnail_url.flatMap { URL(string: $0) },
            outboundURL: item.url,
            domain: item.url.host
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
