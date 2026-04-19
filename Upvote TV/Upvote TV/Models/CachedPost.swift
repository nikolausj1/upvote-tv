import Foundation
import SwiftData

@Model
final class CachedPost {
    var postID: String
    var title: String
    var subreddit: String?
    var author: String?
    var createdAt: Date
    var postTypeRaw: String

    var thumbnailURLString: String?
    var previewImageURLString: String?
    var mediaURLString: String?

    var galleryItemsData: Data?

    var textBody: String?

    var outboundURLString: String?
    var domain: String?

    var isNSFW: Bool
    var score: Int?

    var sharedAt: Date?
    var resolvedAt: Date?
    var cachedAt: Date

    init(from post: Post, cachedAt: Date = Date()) {
        self.postID = post.id
        self.title = post.title
        self.subreddit = post.subreddit
        self.author = post.author
        self.createdAt = post.createdAt
        self.postTypeRaw = post.postType.rawValue
        self.thumbnailURLString = post.thumbnailURL?.absoluteString
        self.previewImageURLString = post.previewImageURL?.absoluteString
        self.mediaURLString = post.mediaURL?.absoluteString
        if let items = post.galleryItems {
            self.galleryItemsData = try? JSONEncoder().encode(items)
        }
        self.textBody = post.textBody
        self.outboundURLString = post.outboundURL?.absoluteString
        self.domain = post.domain
        self.isNSFW = post.isNSFW
        self.score = post.score
        self.sharedAt = post.sharedAt
        self.resolvedAt = post.resolvedAt
        self.cachedAt = cachedAt
    }

    func toPost() -> Post {
        var galleryItems: [GalleryItem]?
        if let data = galleryItemsData {
            galleryItems = try? JSONDecoder().decode([GalleryItem].self, from: data)
        }

        return Post(
            id: postID,
            title: title,
            subreddit: subreddit,
            author: author,
            createdAt: createdAt,
            postType: PostType(rawValue: postTypeRaw) ?? .unsupported,
            thumbnailURL: thumbnailURLString.flatMap { URL(string: $0) },
            previewImageURL: previewImageURLString.flatMap { URL(string: $0) },
            mediaURL: mediaURLString.flatMap { URL(string: $0) },
            galleryItems: galleryItems,
            textBody: textBody,
            outboundURL: outboundURLString.flatMap { URL(string: $0) },
            domain: domain,
            isNSFW: isNSFW,
            score: score,
            sharedAt: sharedAt,
            resolvedAt: resolvedAt
        )
    }
}
