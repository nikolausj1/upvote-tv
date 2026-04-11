import SwiftUI

struct PostCardRow: View {
    let post: Post
    let isWatched: Bool

    var body: some View {
        HStack(spacing: 20) {
            // Type icon
            TypeIconView(postType: post.postType, dimmed: isWatched)

            // Title + metadata
            VStack(alignment: .leading, spacing: 6) {
                Text(post.title)
                    .font(.system(size: 29, weight: isWatched ? .regular : .medium))
                    .foregroundStyle(isWatched ? Color(white: 0.47) : Color(white: 0.93))
                    .lineLimit(2)

                metadataRow
            }

            Spacer(minLength: 8)

            // Thumbnail (visual types only)
            if post.postType.hasVisualThumbnail {
                thumbnail
            }

            // Watched indicator
            watchedIndicator
        }
    }

    // MARK: - Metadata

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let score = post.score {
                Text(score.formattedCompact)
                    .foregroundStyle(.white)

                Text("·")
                    .foregroundStyle(.tertiary)
            }

            Text("r/\(post.subreddit)")
                .foregroundStyle(.tertiary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text(post.createdAt.relativeDescription)
                .foregroundStyle(.tertiary)

            if let domain = post.domain,
               (post.postType == .link || post.postType == .youtube || post.postType == .unsupported) {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(domain)
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }

    // MARK: - Thumbnail

    private var thumbnail: some View {
        ZStack {
            Group {
                let url = (post.thumbnailURL ?? post.previewImageURL)?.resized(width: 192, height: 128)
                if let url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            thumbnailPlaceholder
                        }
                    }
                } else {
                    thumbnailPlaceholder
                }
            }

            if post.postType == .youtube || post.postType == .video {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(post.postType == .youtube ? Color.red.opacity(0.85) : Color.black.opacity(0.5))
                    )
            }
        }
        .frame(width: 96, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .opacity(isWatched ? 0.5 : 1.0)
    }

    private var thumbnailPlaceholder: some View {
        Rectangle()
            .fill(Color(red: 0.08, green: 0.08, blue: 0.09))
    }

    // MARK: - Watched Indicator

    @ViewBuilder
    private var watchedIndicator: some View {
        if isWatched {
            Image(systemName: "checkmark")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(Color.white.opacity(0.2))
                .frame(width: 20)
        } else {
            Circle()
                .fill(.blue)
                .frame(width: 8, height: 8)
                .frame(width: 20)
        }
    }
}
