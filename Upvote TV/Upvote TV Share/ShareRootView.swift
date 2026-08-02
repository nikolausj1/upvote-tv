import SwiftUI

/// SwiftUI content for the Share Extension modal.
///
/// States the user sees in sequence on a typical successful share:
/// 1. Working (spinner + "Adding to Upvote TV…")
/// 2. Success (green check, auto-dismisses after ~1.2s)
///
/// On failure, we stop on an error state with a Done button so the user can
/// retry from the source app.
struct ShareRootView: View {
    let inputItems: [NSExtensionItem]
    let onComplete: () -> Void
    let onCancel: () -> Void

    @State private var state: ShareState = .working
    @State private var errorMessage: String? = nil
    @State private var classifiedItem: QueueItem? = nil

    /// Explicit init so the caller in UIKit-land can create one; the default
    /// memberwise init becomes private once we add `@State private var` fields.
    init(inputItems: [NSExtensionItem], onComplete: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.inputItems = inputItems
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    private enum ShareState {
        case working
        case success
        case duplicateNotice
        case failure
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            icon
            title
            subtitle
            Spacer()
            dismissButton
        }
        .padding(24)
        .task {
            await runShare()
        }
    }

    // MARK: - UI

    private var icon: some View {
        Group {
            switch state {
            case .working:
                ProgressView().controlSize(.large)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            case .duplicateNotice:
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
            case .failure:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var title: some View {
        Text(titleText)
            .font(.title3)
            .fontWeight(.semibold)
            .multilineTextAlignment(.center)
    }

    private var subtitle: some View {
        Group {
            switch state {
            case .working:
                EmptyView()
            case .success:
                if let item = classifiedItem {
                    Text(item.source == .reddit ? "Reddit post added to your queue" : "YouTube video added to your queue")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            case .duplicateNotice:
                Text("That item is already in your queue.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .failure:
                if let message = errorMessage {
                    ScrollView {
                        Text(message)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                    }
                }
            }
        }
    }

    private var titleText: String {
        switch state {
        case .working: return "Adding to Upvote TV…"
        case .success: return "Added"
        case .duplicateNotice: return "Already Queued"
        case .failure: return "Couldn't add"
        }
    }

    @ViewBuilder
    private var dismissButton: some View {
        switch state {
        case .working:
            EmptyView()
        case .success, .duplicateNotice, .failure:
            Button("Done") {
                onComplete()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Flow

    private func runShare() async {
        guard let url = await ShareInputResolver.extractURL(from: inputItems) else {
            fail("No URL was shared.\n\n\(ShareInputResolver.diagnostics(for: inputItems))")
            return
        }

        guard SecretsLoader.shared.isConfigured else {
            fail("Upvote TV is not configured. Open the Upvote TV app on this phone to set it up.")
            return
        }

        // Reddit's iOS app shares as a /r/<sub>/s/<id> shortlink; resolve it
        // to the canonical /comments/<id> URL before classifying.
        let resolvedURL = await ShareInputResolver.resolveRedditShortlinkIfNeeded(url)

        guard var item = URLClassifier.classify(resolvedURL) else {
            fail("Only Reddit posts and YouTube videos can be added.\n\n\(resolvedURL.absoluteString)")
            return
        }
        classifiedItem = item

        let client = GistQueueClient()

        let existing: [QueueItem]
        do {
            existing = try await client.fetch()
        } catch let error as GistQueueClient.ClientError {
            fail(humanize(error))
            return
        } catch {
            fail("Couldn't reach the queue.")
            return
        }

        // Dedup: matching id + source
        if existing.contains(where: { $0.id == item.id && $0.source == item.source }) {
            state = .duplicateNotice
            scheduleAutoDismiss()
            return
        }

        // Resolve metadata here, on the phone, rather than leaving it to the TV.
        //
        // Reddit meters on a per-IP unit budget (see `RedditRateLimiter`), and the TV's
        // problem is that it wants the whole queue at once. Resolving at share time spends
        // exactly one request, at the moment a human deliberately shared something, which
        // is the least bursty possible shape. Best effort only: on failure we write the
        // item without metadata and the TV resolves it later exactly as before, so a
        // flaky phone network can never cost you a share.
        item.metadata = await ShareTimeResolver().resolve(item)

        // Prepend so newest sharedAt is first (tvOS sorts by sharedAt anyway, but
        // writing in order is easier to debug in the Gist).
        let updated = [item] + existing

        do {
            try await client.upsert(updated)
        } catch let error as GistQueueClient.ClientError {
            fail(humanize(error))
            return
        } catch {
            fail("Couldn't save to the queue.")
            return
        }

        state = .success
        scheduleAutoDismiss()
    }

    private func scheduleAutoDismiss() {
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            onComplete()
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        state = .failure
    }

    private func humanize(_ error: GistQueueClient.ClientError) -> String {
        switch error {
        case .configurationMissing:
            return "Secrets.plist is missing GistID or GistToken."
        case .unauthorized:
            return "Token rejected. It may have expired."
        case .notFound:
            return "Gist not found. Check the Gist ID."
        case .rateLimited:
            return "GitHub is throttling. Try again in a minute."
        case .badResponse:
            return "Unexpected response from GitHub."
        case .network:
            return "Network error. Check your internet connection."
        }
    }
}
