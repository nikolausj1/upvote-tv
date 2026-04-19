import Foundation

/// Loads Gist API configuration from a bundled `Secrets.plist`.
///
/// `Secrets.plist` is gitignored. A committed `Secrets.example.plist` documents
/// the expected keys. At build time, copy the example to `Secrets.plist` and fill
/// in your values; Xcode embeds both in the app bundle but only `Secrets.plist`
/// is read at runtime.
///
/// Expected plist schema:
///   GistID:    String (e.g. "abc123def456")
///   GistToken: String (GitHub fine-grained PAT with gists: read+write)
final class SecretsLoader {
    static let shared = SecretsLoader()

    let gistID: String?
    let gistToken: String?

    private init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            self.gistID = nil
            self.gistToken = nil
            return
        }
        self.gistID = (plist["GistID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.gistToken = (plist["GistToken"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when both values are present and non-empty.
    var isConfigured: Bool {
        guard let id = gistID, !id.isEmpty,
              let token = gistToken, !token.isEmpty else { return false }
        return true
    }
}
