import SwiftUI
import SwiftData

struct BrowseListView: View {
    @StateObject private var viewModel: GalleryViewModel
    @FocusState private var focusedID: String?
    @State private var selectedPost: Post?

    private static let caughtUpID = "__caught_up__"

    init(provider: ContentProvider, watchedManager: WatchedStateManager) {
        _viewModel = StateObject(wrappedValue: GalleryViewModel(provider: provider, watchedManager: watchedManager))
    }

    var body: some View {
        ZStack {
            Group {
                if viewModel.isLoading {
                    BrowseSkeletonView()
                } else if viewModel.posts.isEmpty, let error = viewModel.loadError {
                    AuthErrorView(error: error)
                } else {
                    browseList
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)

            DebugOverlayView(viewModel: viewModel)
        }
        .task {
            await viewModel.loadPosts()
            if viewModel.allWatched {
                focusedID = Self.caughtUpID
            } else {
                focusedID = viewModel.sortedPosts.first?.id
            }
        }
        .background(Color.black)
        .fullScreenCover(item: $selectedPost) { post in
            detailView(for: post)
        }
    }

    // MARK: - Browse List

    private var browseList: some View {
        VStack(spacing: 0) {
            if viewModel.isShowingCachedContent {
                StaleBanner(cachedDate: viewModel.cachedContentDate)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    // Caught-up row
                    if viewModel.allWatched {
                        caughtUpCard
                    }

                    // New section
                    if !viewModel.unwatchedPosts.isEmpty {
                        sectionHeader("New")
                        ForEach(viewModel.unwatchedPosts) { post in
                            postCard(for: post)
                        }
                    }

                    // Watched section
                    if !viewModel.watchedPosts.isEmpty {
                        sectionHeader("Watched")
                        ForEach(viewModel.watchedPosts) { post in
                            postCard(for: post)
                        }
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.top, 16)
            .padding(.bottom, 2)
    }

    // MARK: - Caught Up

    private var caughtUpCard: some View {
        Button {
            // No action
        } label: {
            CaughtUpCardRow()
        }
        .buttonStyle(PostCardStyle(isWatched: false))
        .focused($focusedID, equals: Self.caughtUpID)
    }

    // MARK: - Post Card

    private func postCard(for post: Post) -> some View {
        let watched = viewModel.isWatched(post.id)
        return Button {
            selectedPost = post
        } label: {
            PostCardRow(post: post, isWatched: watched)
        }
        .buttonStyle(PostCardStyle(isWatched: watched))
        .id(post.id)
        .focused($focusedID, equals: post.id)
        .contextMenu {
            if watched {
                Button {
                    viewModel.markUnwatched(post.id)
                } label: {
                    Label("Mark as Unwatched", systemImage: "eye.slash")
                }
            } else {
                Button {
                    viewModel.markWatched(post.id)
                } label: {
                    Label("Mark as Watched", systemImage: "eye.fill")
                }
            }
        }
    }

    // MARK: - Detail Routing

    @ViewBuilder
    private func detailView(for post: Post) -> some View {
        switch post.postType {
        case .video:
            VideoDetailView(post: post) { viewModel.markWatched(post.id) }
        case .image:
            ImageDetailView(post: post) { viewModel.markWatched(post.id) }
        case .text:
            TextDetailView(post: post) { viewModel.markWatched(post.id) }
        case .gallery:
            GalleryDetailView(post: post) { viewModel.markWatched(post.id) }
        case .youtube:
            YouTubeDetailView(post: post) { viewModel.markWatched(post.id) }
        case .link, .unsupported:
            LinkDetailView(post: post) { viewModel.markWatched(post.id) }
        }
    }
}

// MARK: - Card Button Style

struct PostCardStyle: ButtonStyle {
    let isWatched: Bool
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 26)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(cardFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(borderColor, lineWidth: 1)
                    )
            )
            .scaleEffect(isFocused ? 1.008 : 1.0)
            .shadow(color: isFocused ? Color.black.opacity(0.3) : .clear, radius: 12, y: 4)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var cardFill: Color {
        if isFocused {
            return Color.white.opacity(0.06)
        }
        return Color.white.opacity(isWatched ? 0.01 : 0.02)
    }

    private var borderColor: Color {
        if isFocused {
            return Color.white.opacity(0.08)
        }
        return Color.white.opacity(isWatched ? 0.02 : 0.03)
    }
}
