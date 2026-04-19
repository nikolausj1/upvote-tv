import Foundation
import OSLog

private let gistLog = Logger(subsystem: "com.justinnikolaus.Upvote-TV", category: "Gist")

/// HTTP client that reads and writes the queue JSON to a GitHub Gist.
///
/// Reads: `GET /gists/{id}` → extract the `queue.json` file's content → decode.
/// Writes: `PATCH /gists/{id}` with the full file content as a single atomic replace.
/// GitHub's PATCH is atomic on their side; we don't need to emulate temp-file+rename.
struct GistQueueClient {
    enum ClientError: Error, Equatable {
        case configurationMissing       // Secrets.plist absent or token/id blank
        case unauthorized               // 401 / 403 (PAT invalid or insufficient scope)
        case notFound                   // 404 — gist deleted or ID wrong
        case rateLimited                // 429 or GitHub's secondary rate limit
        case badResponse                // 2xx with unexpected body
        case network(URLError.Code?)    // transport-level
    }

    private let session: URLSession
    private let gistID: String?
    private let token: String?

    init(
        session: URLSession? = nil,
        gistID: String? = SecretsLoader.shared.gistID,
        token: String? = SecretsLoader.shared.gistToken
    ) {
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = AppConfig.resolverTimeout
            config.timeoutIntervalForResource = AppConfig.resolverTimeout
            self.session = URLSession(configuration: config)
        }
        self.gistID = gistID
        self.token = token
    }

    // MARK: - Public API

    /// Fetch the queue items. Returns `[]` if the gist file is absent or contains no items.
    func fetch() async throws -> [QueueItem] {
        let (id, token) = try requireConfig()
        let url = URL(string: AppConfig.gistAPIBase + id)!

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        gistLog.info("GET gist \(id, privacy: .public)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            gistLog.error("GET transport error: \(urlError.code.rawValue, privacy: .public)")
            throw ClientError.network(urlError.code)
        }

        if let http = response as? HTTPURLResponse {
            gistLog.info("GET status \(http.statusCode, privacy: .public)")
            switch http.statusCode {
            case 200: break
            case 401, 403: throw ClientError.unauthorized
            case 404: throw ClientError.notFound
            case 429: throw ClientError.rateLimited
            default: throw ClientError.badResponse
            }
        }

        // Pull out the queue.json file's content
        struct GistResponse: Decodable {
            let files: [String: GistFile]
        }
        struct GistFile: Decodable {
            let content: String?
        }

        let parsed: GistResponse
        do {
            parsed = try JSONDecoder().decode(GistResponse.self, from: data)
        } catch {
            throw ClientError.badResponse
        }

        guard let file = parsed.files[AppConfig.queueFileName] ?? parsed.files.first?.value,
              let content = file.content,
              let contentData = content.data(using: .utf8) else {
            // Gist exists but has no queue file yet — treat as empty queue.
            return []
        }

        return try decodeQueueItems(from: contentData)
    }

    /// Replace the queue file content with `items`. Atomic on GitHub's side.
    func upsert(_ items: [QueueItem]) async throws {
        let (id, token) = try requireConfig()
        let url = URL(string: AppConfig.gistAPIBase + id)!

        let bodyData = try encodeQueueItems(items)
        guard let bodyString = String(data: bodyData, encoding: .utf8) else {
            throw ClientError.badResponse
        }

        let patchBody: [String: Any] = [
            "files": [
                AppConfig.queueFileName: [
                    "content": bodyString
                ]
            ]
        ]
        let patchData = try JSONSerialization.data(withJSONObject: patchBody)

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = patchData

        gistLog.info("PATCH gist \(id, privacy: .public) with \(items.count, privacy: .public) items")

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch let urlError as URLError {
            gistLog.error("PATCH transport error: \(urlError.code.rawValue, privacy: .public)")
            throw ClientError.network(urlError.code)
        }

        if let http = response as? HTTPURLResponse {
            gistLog.info("PATCH status \(http.statusCode, privacy: .public)")
            switch http.statusCode {
            case 200, 201: return
            case 401, 403: throw ClientError.unauthorized
            case 404: throw ClientError.notFound
            case 429: throw ClientError.rateLimited
            default: throw ClientError.badResponse
            }
        }
    }

    // MARK: - Private helpers

    private func requireConfig() throws -> (String, String) {
        guard let id = gistID, !id.isEmpty,
              let token = token, !token.isEmpty else {
            gistLog.error("Gist config missing (gistID or token empty)")
            throw ClientError.configurationMissing
        }
        return (id, token)
    }

    /// Decode the stored JSON into `[QueueItem]`. Tolerant of ISO8601 with/without fractional seconds.
    private func decodeQueueItems(from data: Data) throws -> [QueueItem] {
        struct Envelope: Decodable {
            let version: Int
            let items: [ItemDTO]
        }
        struct ItemDTO: Decodable {
            let id: String
            let url: String
            let source: String
            let sharedAt: String
        }

        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ClientError.badResponse
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        return envelope.items.compactMap { dto in
            guard let url = URL(string: dto.url),
                  let source = QueueSource(rawValue: dto.source) else {
                return nil
            }
            let shared = iso.date(from: dto.sharedAt) ?? isoPlain.date(from: dto.sharedAt) ?? Date()
            return QueueItem(id: dto.id, url: url, source: source, sharedAt: shared)
        }
    }

    private func encodeQueueItems(_ items: [QueueItem]) throws -> Data {
        struct Envelope: Encodable {
            let version: Int
            let items: [ItemDTO]
        }
        struct ItemDTO: Encodable {
            let id: String
            let url: String
            let source: String
            let sharedAt: String
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let envelope = Envelope(
            version: AppConfig.queueSchemaVersion,
            items: items.map {
                ItemDTO(
                    id: $0.id,
                    url: $0.url.absoluteString,
                    source: $0.source.rawValue,
                    sharedAt: iso.string(from: $0.sharedAt)
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }
}
