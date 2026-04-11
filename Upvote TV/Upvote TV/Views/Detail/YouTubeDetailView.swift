import SwiftUI

struct YouTubeDetailView: View {
    let post: Post
    let onMarkWatched: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showNotFound = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Preview image
                if let url = post.previewImageURL ?? post.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: 960, maxHeight: 540)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        default:
                            imagePlaceholder
                        }
                    }
                    .padding(.bottom, 36)
                } else {
                    imagePlaceholder
                        .padding(.bottom, 36)
                }

                // Title
                Text(post.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 900)

                // YouTube badge + metadata
                HStack(spacing: 16) {
                    Label("YouTube", systemImage: "play.rectangle.fill")
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)

                    Text("r/\(post.subreddit)")
                        .foregroundStyle(.secondary)

                    Text(post.createdAt.relativeDescription)
                        .foregroundStyle(.tertiary)

                    if let score = post.score {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                            Text(score.formattedCompact)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .padding(.top, 16)

                // Open in YouTube button
                Button {
                    openInYouTube()
                } label: {
                    Label("Open in YouTube", systemImage: "play.fill")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.card)
                .padding(.top, 32)

                // "Not found" message
                if showNotFound {
                    Text("YouTube app not found")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                Spacer()
            }
            .padding(.horizontal, 80)
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(white: 0.15))
            .frame(width: 960, height: 540)
            .overlay {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red.opacity(0.6))
            }
    }

    private func openInYouTube() {
        guard let outboundURL = post.outboundURL else { return }

        // Extract video ID and try the YouTube app scheme first
        if let videoID = extractVideoID(from: outboundURL),
           let appURL = URL(string: "youtube://watch?v=\(videoID)") {
            openURL(appURL) { accepted in
                if accepted {
                    onMarkWatched()
                } else {
                    // Fall back to HTTPS URL
                    openHTTPS(outboundURL)
                }
            }
        } else {
            openHTTPS(outboundURL)
        }
    }

    private func openHTTPS(_ url: URL) {
        openURL(url) { accepted in
            if accepted {
                onMarkWatched()
            } else {
                withAnimation { showNotFound = true }
            }
        }
    }

    private func extractVideoID(from url: URL) -> String? {
        // Handle youtube.com/watch?v=ID
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value {
            return videoID
        }
        // Handle youtu.be/ID
        if url.host == "youtu.be" {
            let id = url.lastPathComponent
            return id.isEmpty ? nil : id
        }
        return nil
    }
}
