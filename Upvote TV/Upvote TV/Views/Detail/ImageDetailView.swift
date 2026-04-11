import SwiftUI

struct ImageDetailView: View {
    let post: Post
    let onMarkWatched: () -> Void

    @State private var hasMarkedWatched = false
    @State private var loadFailed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if loadFailed {
                MediaErrorView(post: post)
            } else {
                imageContent
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            if !hasMarkedWatched {
                hasMarkedWatched = true
                onMarkWatched()
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        let url = post.mediaURL ?? post.previewImageURL

        if let url {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .ignoresSafeArea()
                case .failure:
                    MediaErrorView(post: post)
                        .onAppear { loadFailed = true }
                default:
                    ProgressView()
                        .tint(.white)
                }
            }
        } else {
            MediaErrorView(post: post)
                .onAppear { loadFailed = true }
        }
    }
}
