import Foundation
import SwiftData

@MainActor
final class WatchedStateManager: ObservableObject {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func isWatched(_ postID: String) -> Bool {
        return fetchState(for: postID)?.isWatched ?? false
    }

    func watchedStateMap(for postIDs: [String]) -> [String: Bool] {
        let descriptor = FetchDescriptor<WatchedState>()
        let allStates = (try? modelContext.fetch(descriptor)) ?? []
        var map: [String: Bool] = [:]
        for state in allStates {
            map[state.postID] = state.isWatched
        }
        return map
    }

    func markWatched(_ postID: String) {
        let now = Date()
        if let existing = fetchState(for: postID) {
            existing.isWatched = true
            existing.watchedAt = existing.watchedAt ?? now
            existing.lastViewedAt = now
            existing.viewCount += 1
        } else {
            let state = WatchedState(postID: postID, isWatched: true, watchedAt: now, lastViewedAt: now, viewCount: 1)
            modelContext.insert(state)
        }
        save()
    }

    func markUnwatched(_ postID: String) {
        if let existing = fetchState(for: postID) {
            existing.isWatched = false
        }
        save()
    }

    func toggleWatched(_ postID: String) -> Bool {
        let currentlyWatched = isWatched(postID)
        if currentlyWatched {
            markUnwatched(postID)
        } else {
            markWatched(postID)
        }
        return !currentlyWatched
    }

    private func fetchState(for postID: String) -> WatchedState? {
        var descriptor = FetchDescriptor<WatchedState>(
            predicate: #Predicate { $0.postID == postID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func save() {
        try? modelContext.save()
    }
}
