import SwiftUI
import SwiftData

struct DebugOverlayView: View {
    let viewModel: GalleryViewModel

    @State private var isExpanded = false

    var body: some View {
        #if DEBUG
        VStack {
            HStack {
                Spacer()
                debugButton
            }

            if isExpanded {
                HStack {
                    Spacer()
                    debugPanel
                }
            }

            Spacer()
        }
        .padding(20)
        #endif
    }

    #if DEBUG
    private var debugButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(8)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Debug Diagnostics")
                .font(.caption)
                .fontWeight(.bold)

            Divider()

            row("Posts loaded", "\(viewModel.posts.count)")
            row("Visible (after NSFW)", "\(viewModel.filteredPosts.count)")
            row("Unwatched", "\(viewModel.filteredPosts.filter { !viewModel.isWatched($0.id) }.count)")
            row("Watched", "\(viewModel.filteredPosts.filter { viewModel.isWatched($0.id) }.count)")
            row("NSFW hidden", "\(viewModel.posts.count - viewModel.filteredPosts.count)")
            row("NSFW setting", NSFWFilterService.isNSFWEnabled ? "Show" : "Hide")

            Divider()

            row("Showing cached", viewModel.isShowingCachedContent ? "Yes" : "No")
            row("Load error", viewModel.loadError.map { String(describing: $0) } ?? "None")
            row("Focused post", viewModel.focusedPostID ?? "None")

            Divider()

            row("Build", "DEBUG")
            row("Provider", String(describing: type(of: viewModel).self))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(16)
        .frame(width: 360)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .lineLimit(1)
        }
    }
    #endif
}
