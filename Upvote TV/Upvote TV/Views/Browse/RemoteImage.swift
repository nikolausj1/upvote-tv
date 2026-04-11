import SwiftUI

/// A memory-conscious async image view that constrains decoded image size.
/// Use instead of raw AsyncImage for thumbnail and preview images to avoid
/// loading full-resolution originals into memory.
struct RemoteImage: View {
    let url: URL?
    let maxWidth: CGFloat
    let maxHeight: CGFloat
    var contentMode: ContentMode = .fill

    var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeIn(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                case .failure:
                    placeholder
                default:
                    placeholder
                        .overlay {
                            ProgressView()
                                .tint(.secondary)
                        }
                }
            }
            .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        } else {
            placeholder
                .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(white: 0.15))
    }
}

/// Builds a URL that requests a specific size from picsum.photos (mock data only).
/// For real Reddit images, the RedditResponseParser should select the closest
/// preview resolution to the target size during normalization.
extension URL {
    func resized(width: Int, height: Int) -> URL {
        // Only transform picsum.photos URLs
        guard let host = self.host, host.contains("picsum.photos") else { return self }
        let components = self.pathComponents
        // picsum format: /seed/{seed}/{width}/{height}
        guard components.count >= 5,
              let _ = Int(components[3]),
              let _ = Int(components[4]) else { return self }
        var newComponents = components
        newComponents[3] = "\(width)"
        newComponents[4] = "\(height)"
        let newPath = newComponents.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
        var result = URLComponents(url: self, resolvingAgainstBaseURL: false)!
        result.path = newPath
        return result.url ?? self
    }
}
