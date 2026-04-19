import Foundation
import SwiftData

/// Thin wrapper over SwiftData's `CachedPost` store. Handles freshness lookup
/// and upserts, so callers can reason in terms of Post snapshots.
@MainActor
final class MetadataCache {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Returns the cached Post for the given id, if one exists. No freshness filter —
    /// callers decide whether to trust it based on `resolvedAt`.
    func fetch(postID: String) -> Post? {
        fetchCached(postID: postID)?.toPost()
    }

    /// Returns `true` if the cache has a post with `resolvedAt` within the TTL.
    func isFresh(postID: String, now: Date = Date()) -> Bool {
        guard let cached = fetchCached(postID: postID),
              let resolvedAt = cached.resolvedAt else {
            return false
        }
        return now.timeIntervalSince(resolvedAt) < AppConfig.cacheTTL
    }

    /// Upserts a Post snapshot into the cache.
    func store(_ post: Post) {
        if let existing = fetchCached(postID: post.id) {
            modelContext.delete(existing)
        }
        let cached = CachedPost(from: post)
        modelContext.insert(cached)
        try? modelContext.save()
    }

    /// Bulk-loads cached posts for the given ids. Returned dictionary is keyed by post id.
    func bulkFetch(postIDs: [String]) -> [String: Post] {
        let descriptor = FetchDescriptor<CachedPost>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let wanted = Set(postIDs)
        return all.reduce(into: [String: Post]()) { acc, cached in
            if wanted.contains(cached.postID) {
                acc[cached.postID] = cached.toPost()
            }
        }
    }

    /// Removes the cached snapshot for a post id, if present.
    func remove(postID: String) {
        if let existing = fetchCached(postID: postID) {
            modelContext.delete(existing)
            try? modelContext.save()
        }
    }

    // MARK: - Internals

    private func fetchCached(postID: String) -> CachedPost? {
        var descriptor = FetchDescriptor<CachedPost>(
            predicate: #Predicate { $0.postID == postID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
