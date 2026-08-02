import Foundation

struct QueueItem: Identifiable, Codable, Hashable {
    let id: String
    let url: URL
    let source: QueueSource
    let sharedAt: Date

    /// Metadata resolved on the phone at share time (queue schema v2).
    ///
    /// `nil` for anything written by an older build, or when resolution failed or was
    /// skipped at share time. tvOS resolves those itself, exactly as it always has, so
    /// this is purely an optimisation: it moves one request off the TV's rate-limit
    /// budget and onto the phone, at the moment of sharing, one post at a time.
    var metadata: ResolvedMetadata?

    init(id: String, url: URL, source: QueueSource, sharedAt: Date, metadata: ResolvedMetadata? = nil) {
        self.id = id
        self.url = url
        self.source = source
        self.sharedAt = sharedAt
        self.metadata = metadata
    }
}
