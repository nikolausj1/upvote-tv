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

            // Thumbnail (visual types, or any post that resolved a preview image)
            if showsThumbnail {
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

            Text(sourceLabel)
                .foregroundStyle(.tertiary)

            Text("·")
                .foregroundStyle(.tertiary)

            Text((post.sharedAt ?? post.createdAt).relativeDescription)
                .foregroundStyle(.tertiary)

            if let domain = post.domain,
               (post.postType == .link || post.postType == .unsupported) {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(domain)
                    .foregroundStyle(.tertiary)
            }

            if isStale {
                staleBadge
            }
        }
        .font(.caption2)
        .lineLimit(1)
    }

    private var isStale: Bool {
        guard let resolvedAt = post.resolvedAt else {
            // Never successfully resolved — fallback cards are effectively stale.
            return post.postType == .unsupported && post.score == nil
        }
        return Date().timeIntervalSince(resolvedAt) > AppConfig.cacheTTL
    }

    private var staleBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock.arrow.circlepath")
            Text("Stale")
        }
        .font(.system(size: 14, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.18), in: Capsule())
        .foregroundStyle(.orange)
    }

    private var sourceLabel: String {
        if let subreddit = post.subreddit, !subreddit.isEmpty {
            return "r/\(subreddit)"
        }
        if post.postType == .youtube {
            if let author = post.author, !author.isEmpty {
                return "YouTube · \(author)"
            }
            return "YouTube"
        }
        return post.domain ?? ""
    }

    // MARK: - Thumbnail

    /// Show the thumbnail for inherently visual types, and also for link/preview cards
    /// (e.g. OpenGraph-resolved Reddit posts) that carry a resolved preview image.
    private var showsThumbnail: Bool {
        post.postType.hasVisualThumbnail || post.thumbnailURL != nil || post.previewImageURL != nil
    }

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
