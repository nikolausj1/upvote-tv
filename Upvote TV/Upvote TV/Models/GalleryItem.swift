import Foundation

struct GalleryItem: Identifiable, Codable, Hashable {
    let id: String
    let imageURL: URL
    let width: Int
    let height: Int
    let position: Int
}
