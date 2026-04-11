import SwiftUI

struct AuthErrorView: View {
    let error: ContentProviderError?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.shield")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)

            Text("Check the project README for setup instructions.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)

            #if DEBUG
            debugInfo
            #endif

            Spacer()
        }
        .padding(60)
    }

    private var title: String {
        switch error {
        case .authenticationRequired:
            return "Setup Required"
        case .authenticationExpired:
            return "Authentication Expired"
        default:
            return "Unable to Load Posts"
        }
    }

    private var subtitle: String {
        switch error {
        case .authenticationRequired:
            return "Reddit credentials haven't been configured yet. You'll need to set up a Secrets.plist with your API credentials."
        case .authenticationExpired:
            return "Your authentication has expired. You'll need to generate a new refresh token."
        case .networkError:
            return "A network error occurred. Check your internet connection and try restarting the app."
        case .rateLimited:
            return "Too many requests to Reddit. Please wait a moment and restart the app."
        default:
            return "Something went wrong while loading your posts. Try restarting the app."
        }
    }

    #if DEBUG
    private var debugInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .padding(.vertical, 12)

            Text("Debug Info")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            if let error {
                Text("Error: \(String(describing: error))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: 600)
        .padding(.top, 20)
    }
    #endif
}
