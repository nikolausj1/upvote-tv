import SwiftUI

struct GalleryDetailView: View {
    let post: Post
    let onMarkWatched: () -> Void

    @State private var currentIndex = 0
    @State private var hasMarkedWatched = false

    private var items: [GalleryItem] {
        (post.galleryItems ?? []).sorted { $0.position < $1.position }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if items.isEmpty {
                MediaErrorView(post: post)
            } else {
                galleryContent
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(2))
            markWatchedIfNeeded()
        }
    }

    private var galleryContent: some View {
        ZStack(alignment: .bottom) {
            // Image
            TabView(selection: $currentIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    AsyncImage(url: item.imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure:
                            imagePlaceholder
                        default:
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
            .onChange(of: currentIndex) { _, _ in
                markWatchedIfNeeded()
            }

            // Position indicator
            positionIndicator
                .padding(.bottom, 48)
        }
    }

    private var positionIndicator: some View {
        Text("\(currentIndex + 1) / \(items.count)")
            .font(.callout)
            .fontWeight(.medium)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var imagePlaceholder: some View {
        Rectangle()
            .fill(Color(white: 0.15))
            .overlay {
                Image(systemName: "photo")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)
            }
    }

    private func markWatchedIfNeeded() {
        guard !hasMarkedWatched else { return }
        hasMarkedWatched = true
        onMarkWatched()
    }
}
