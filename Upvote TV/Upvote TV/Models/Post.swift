import Foundation

struct Post: Identifiable, Hashable {
    let id: String
    let title: String
    let subreddit: String
    let author: String
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
}
