import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        BrowseListView(
            provider: MockContentProvider(),
            watchedManager: WatchedStateManager(modelContext: modelContext)
        )
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [WatchedState.self, CachedPost.self, AuthState.self], inMemory: true)
}
