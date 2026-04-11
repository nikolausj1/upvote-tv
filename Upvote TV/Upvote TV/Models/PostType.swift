import Foundation
import SwiftUI

enum PostType: String, Codable, CaseIterable {
    case video
    case image
    case text
    case gallery
    case youtube
    case link
    case unsupported

    var label: String {
        switch self {
        case .video: return "Video"
        case .image: return "Image"
        case .text: return "Text"
        case .gallery: return "Gallery"
        case .youtube: return "YouTube"
        case .link: return "Link"
        case .unsupported: return "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .image: return "photo"
        case .text: return "doc.text"
        case .gallery: return "square.stack"
        case .youtube: return "play.rectangle.fill"
        case .link: return "arrow.up.right"
        case .unsupported: return "arrow.up.right"
        }
    }

    var iconColor: Color {
        switch self {
        case .video: return Color(red: 0.88, green: 0.38, blue: 0.38)   // #e06060
        case .image: return Color(red: 0.38, green: 0.69, blue: 0.88)   // #60b0e0
        case .text: return Color(red: 0.50, green: 0.75, blue: 0.50)    // #80c080
        case .gallery: return Color(red: 0.69, green: 0.50, blue: 0.88) // #b080e0
        case .youtube: return Color(red: 0.88, green: 0.38, blue: 0.38) // #e06060
        case .link: return Color(red: 0.75, green: 0.63, blue: 0.38)    // #c0a060
        case .unsupported: return Color(red: 0.75, green: 0.63, blue: 0.38)
        }
    }

    var hasVisualThumbnail: Bool {
        switch self {
        case .video, .image, .gallery, .youtube: return true
        case .text, .link, .unsupported: return false
        }
    }
}
