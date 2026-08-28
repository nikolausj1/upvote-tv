import Foundation

struct Post: Identifiable, Hashable {
    let id: String
    let title: String
    let subreddit: String?
    let author: String?
    let createdAt: Date
    let postType: PostType

    let thumbnailURL: URL?
    let previewImageURL: URL?
    let mediaURL: URL?

    let galleryItems: [GalleryItem]?

    let textBody: String?

    let outboundURL: URL?
    let domain: String?

    let isNSFW: Bool
    let score: Int?

    let sharedAt: Date?
    let resolvedAt: Date?
}

extension Post {
    /// Reddit has confirmed there is nothing behind this post any more — the author deleted
    /// it, or a moderator removed it.
    ///
    /// Deliberately distinct from an *unresolved* post, which also carries `.unsupported`
    /// but renders the raw URL and may be perfectly fine once a resolve succeeds. That one
    /// must stay visible (see the graceful-degradation rule in CLAUDE.md); this one has
    /// nothing to show and no way to ever get it, so the browse list hides it.
    var isUnavailable: Bool {
        postType == .unsupported && title == RedditMetadataResolver.unavailableTitle
    }
}
