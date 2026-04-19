import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        BrowseListView(
            provider: QueueContentProvider(modelContext: modelContext),
            watchedManager: WatchedStateManager(modelContext: modelContext)
        )
    }
}

#Preview {
    // Previews use the mock provider; the real app uses QueueContentProvider.
    PreviewHarness()
        .modelContainer(for: [WatchedState.self, CachedPost.self], inMemory: true)
}

private struct PreviewHarness: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        BrowseListView(
            provider: MockContentProvider(),
            watchedManager: WatchedStateManager(modelContext: modelContext)
        )
    }
}
