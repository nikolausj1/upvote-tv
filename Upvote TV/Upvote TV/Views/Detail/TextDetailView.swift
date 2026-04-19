import SwiftUI

struct TextDetailView: View {
    let post: Post
    let onMarkWatched: () -> Void

    @State private var hasMarkedWatched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text(post.title)
                    .font(.title2)
                    .fontWeight(.bold)

                // Metadata row
                HStack(spacing: 16) {
                    if let subreddit = post.subreddit, !subreddit.isEmpty {
                        Text("r/\(subreddit)")
                    }
                    if let author = post.author, !author.isEmpty {
                        Text(post.subreddit == nil ? author : "u/\(author)")
                    }
                    Text((post.sharedAt ?? post.createdAt).relativeDescription)
                }
                .font(.callout)
                .foregroundStyle(.secondary)

                Divider()
                    .padding(.vertical, 4)

                // Body text
                if let body = post.textBody, !body.isEmpty {
                    Text(body)
                        .font(.body)
                        .lineSpacing(6)
                } else {
                    Text("This post has no text content.")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 120)
            .padding(.vertical, 60)
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            try? await Task.sleep(for: .seconds(2))
            if !hasMarkedWatched {
                hasMarkedWatched = true
                onMarkWatched()
            }
        }
    }
}
