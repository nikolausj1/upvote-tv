import SwiftUI

/// Screen A-2 in the PRD. Shown when `queue.json` doesn't exist or contains zero items.
///
/// Polls for the queue file every 10 seconds while visible via a timer callback;
/// the parent view model is the one that actually re-runs `loadPosts`.
struct EmptyQueueView: View {
    let onPoll: () -> Void

    @State private var pollTimer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text("Nothing in your queue yet")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Share a Reddit post or YouTube video from your iPhone to add it here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 600)

            Text("Make sure you've installed the Upvote TV Shortcut on your iPhone.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            Spacer()
        }
        .padding(60)
        .onAppear {
            startPolling()
        }
        .onDisappear {
            stopPolling()
        }
    }

    private func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: AppConfig.emptyQueuePollInterval,
            repeats: true
        ) { _ in
            onPoll()
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}
