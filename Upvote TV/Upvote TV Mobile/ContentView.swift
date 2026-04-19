import SwiftUI

/// The iOS companion app's only screen. Explains the share-sheet workflow and
/// provides a connection test so you can catch a bad/expired PAT without
/// waiting until you actually try to share something.
struct ContentView: View {
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle
        case running
        case success(count: Int)
        case failure(message: String)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    howToCard

                    connectionTestCard

                    footer
                }
                .padding(20)
            }
            .navigationTitle("Upvote TV")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Share to your TV.")
                .font(.title2)
                .fontWeight(.semibold)
            Text("This app doesn't do anything by itself. It adds an entry in iOS's share sheet — share a Reddit post or YouTube video, and it lands on your Apple TV.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var howToCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("How to use")

            stepRow(number: 1, title: "Open a Reddit post or YouTube video",
                    subtitle: "In Safari, the Reddit app, the YouTube app — anywhere you can tap Share.")
            stepRow(number: 2, title: "Tap Share → Upvote TV",
                    subtitle: "Scroll the share sheet until you see the Upvote TV extension. Tap it.")
            stepRow(number: 3, title: "Open Upvote TV on your Apple TV",
                    subtitle: "The item appears in your queue within a second.")
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var connectionTestCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader("Connection")

            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(statusColor)

            Button(action: runTest) {
                HStack {
                    if testState == .running {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 4)
                    }
                    Text(testState == .running ? "Testing…" : "Test Connection")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .disabled(testState == .running)
        }
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gist ID")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.tertiary)
            Text(SecretsLoader.shared.gistID ?? "(missing — edit Secrets.plist)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private func stepRow(number: Int, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.callout)
                .fontWeight(.semibold)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusDescription: String {
        switch testState {
        case .idle:
            return SecretsLoader.shared.isConfigured
                ? "Tap below to verify your GitHub token and gist."
                : "⚠ Secrets.plist is missing or empty. Add your GistID and GistToken, then rebuild."
        case .running:
            return "Checking…"
        case .success(let count):
            return "✓ Connected. Your queue has \(count) \(count == 1 ? "item" : "items")."
        case .failure(let message):
            return "✗ \(message)"
        }
    }

    private var statusColor: Color {
        switch testState {
        case .idle: return .secondary
        case .running: return .secondary
        case .success: return .green
        case .failure: return .red
        }
    }

    private func runTest() {
        testState = .running
        Task {
            do {
                let client = GistQueueClient()
                let items = try await client.fetch()
                await MainActor.run {
                    testState = .success(count: items.count)
                }
            } catch let error as GistQueueClient.ClientError {
                await MainActor.run {
                    testState = .failure(message: humanize(error))
                }
            } catch {
                await MainActor.run {
                    testState = .failure(message: "Unexpected error.")
                }
            }
        }
    }

    private func humanize(_ error: GistQueueClient.ClientError) -> String {
        switch error {
        case .configurationMissing: return "Secrets.plist is missing GistID or GistToken."
        case .unauthorized: return "Token rejected. It may be invalid or expired."
        case .notFound: return "Gist not found. Check GistID."
        case .rateLimited: return "GitHub is throttling. Try again in a minute."
        case .badResponse: return "Unexpected response from GitHub."
        case .network: return "Network error. Check your internet connection."
        }
    }
}

// MARK: - SectionHeader

private struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.headline)
    }
}

#Preview {
    ContentView()
}
