import SwiftUI

/// Screen I in the PRD (post-v3.1 naming). Shown when the queue can't be loaded —
/// either `Secrets.plist` is missing, the gist endpoint is unreachable, or the
/// token is invalid.
struct ConnectionErrorView: View {
    let error: ContentProviderError?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: iconName)
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            Text(headline)
                .font(.title2)
                .fontWeight(.semibold)

            Text(bodyCopy)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)

            Text(subCopy)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            #if DEBUG
            debugPanel
            #endif

            Spacer()
        }
        .padding(60)
    }

    private var iconName: String {
        switch error {
        case .configurationMissing: return "key.slash"
        case .rateLimited: return "hourglass"
        default: return "wifi.exclamationmark"
        }
    }

    private var headline: String {
        switch error {
        case .configurationMissing: return "Setup Required"
        case .rateLimited: return "Too Many Requests"
        default: return "Can't Reach Your Queue"
        }
    }

    private var bodyCopy: String {
        switch error {
        case .configurationMissing:
            return "Upvote TV is missing its queue configuration. Add your Gist ID and GitHub token to Secrets.plist and rebuild."
        case .rateLimited:
            return "GitHub is throttling requests. Try again in a minute."
        default:
            return "Couldn't reach the queue. Check your internet connection and that your GitHub token is still valid."
        }
    }

    private var subCopy: String {
        switch error {
        case .configurationMissing:
            return "See docs/Gist-Setup.md in the project for step-by-step instructions."
        default:
            return "The app will retry automatically."
        }
    }

    #if DEBUG
    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 12)

            Text("Debug Info")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            Text("Gist ID: \(SecretsLoader.shared.gistID ?? "(missing)")")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text("Token present: \(SecretsLoader.shared.gistToken?.isEmpty == false ? "yes" : "no")")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if let error {
                Text("Error: \(String(describing: error))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
        .padding(.top, 20)
    }
    #endif
}
