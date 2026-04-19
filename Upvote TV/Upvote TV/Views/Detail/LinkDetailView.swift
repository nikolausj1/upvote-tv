import SwiftUI

struct LinkDetailView: View {
    let post: Post
    let onMarkWatched: () -> Void

    @State private var hasMarkedWatched = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Thumbnail if available
                if let url = post.previewImageURL ?? post.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: 800, maxHeight: 400)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        default:
                            EmptyView()
                        }
                    }
                    .padding(.bottom, 40)
                }

                // Title
                Text(post.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
                    .frame(maxWidth: 900)

                // Domain
                if let domain = post.domain {
                    Label(domain, systemImage: "globe")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .padding(.top, 16)
                }

                // Metadata
                HStack(spacing: 16) {
                    if let subreddit = post.subreddit, !subreddit.isEmpty {
                        Text("r/\(subreddit)")
                    }
                    if let author = post.author, !author.isEmpty {
                        Text(post.subreddit == nil ? author : "u/\(author)")
                    }
                    if let score = post.score {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                            Text(score.formattedCompact)
                        }
                    }
                }
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 16)

                // Text excerpt if available
                if let body = post.textBody, !body.isEmpty {
                    Text(String(body.prefix(300)))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 800)
                        .padding(.top, 24)
                }

                Spacer()
            }
            .padding(.horizontal, 80)
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            if !hasMarkedWatched {
                hasMarkedWatched = true
                onMarkWatched()
            }
        }
    }
}
