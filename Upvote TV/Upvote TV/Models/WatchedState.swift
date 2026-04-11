import Foundation
import SwiftData

@Model
final class WatchedState {
    #Unique<WatchedState>([\.postID])

    var postID: String
    var isWatched: Bool
    var watchedAt: Date?
    var lastViewedAt: Date?
    var viewCount: Int

    init(postID: String, isWatched: Bool = false, watchedAt: Date? = nil, lastViewedAt: Date? = nil, viewCount: Int = 0) {
        self.postID = postID
        self.isWatched = isWatched
        self.watchedAt = watchedAt
        self.lastViewedAt = lastViewedAt
        self.viewCount = viewCount
    }
}
