import UIKit
import SwiftUI
import UniformTypeIdentifiers

/// The Share Extension entry point.
///
/// When the user taps Share → Upvote TV in any app, iOS instantiates this
/// view controller, passes in the `NSExtensionContext` containing the shared
/// URL(s), and shows a compact modal.
///
/// URL extraction is performed **asynchronously** inside the SwiftUI `.task`
/// (see `ShareRootView`) rather than synchronously in `viewDidLoad`. Blocking
/// the main thread here with a DispatchSemaphore deadlocks against
/// `NSItemProvider.loadItem`, which can dispatch its completion to main for
/// certain providers (observed with the Reddit iOS app's `public.url`
/// attachment).
class ShareViewController: UIViewController {
    private var hostingController: UIHostingController<ShareRootView>?

    override func viewDidLoad() {
        super.viewDidLoad()

        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let rootView = ShareRootView(
            inputItems: items,
            onComplete: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.cancelRequest(withError: NSError(
                    domain: "com.justinnikolaus.UpvoteTV.Share",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Cancelled"]
                ))
            }
        )

        let host = UIHostingController(rootView: rootView)
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [UIView.AutoresizingMask.flexibleWidth, UIView.AutoresizingMask.flexibleHeight]
        host.view.backgroundColor = UIColor.systemBackground
        view.addSubview(host.view)
        host.didMove(toParent: self)
        self.hostingController = host
    }
}

/// Async URL extraction from extension input items.
///
/// Supports three input shapes, in priority order:
/// 1. `public.url` attachment (Safari, YouTube app, etc.)
/// 2. `public.plain-text` / `public.text` attachment with an embedded URL
///    (Reddit app typically shares "Title - https://…" this way)
/// 3. The item's `attributedContentText`, scanned with `NSDataDetector`
enum ShareInputResolver {
    static func extractURL(from items: [NSExtensionItem]) async -> URL? {
        // Pass 1: public.url
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = await loadURL(from: provider) {
                        return url
                    }
                }
            }
        }

        // Pass 2: text attachments with an embedded URL
        for item in items {
            for provider in item.attachments ?? [] {
                for textType in [UTType.plainText.identifier, UTType.text.identifier] {
                    if provider.hasItemConformingToTypeIdentifier(textType) {
                        if let text = await loadString(from: provider, typeIdentifier: textType),
                           let url = firstURL(in: text) {
                            return url
                        }
                    }
                }
            }
        }

        // Pass 3: attributedContentText fallback
        for item in items {
            if let text = item.attributedContentText?.string,
               let url = firstURL(in: text) {
                return url
            }
        }

        return nil
    }

    /// Resolves a Reddit shortlink of the form `reddit.com/r/<sub>/s/<id>` to
    /// its canonical `/comments/<id>` URL by following redirects. Returns the
    /// original URL unchanged if it isn't a shortlink or the request fails.
    /// The Reddit iOS app shares posts using the `/s/` shortlink format.
    static func resolveRedditShortlinkIfNeeded(_ url: URL) async -> URL {
        guard let host = url.host?.lowercased(),
              host == "reddit.com" || host.hasSuffix(".reddit.com") else {
            return url
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        // pattern: ["r", <sub>, "s", <shortID>]
        guard parts.count >= 4, parts[0] == "r", parts[2] == "s" else {
            return url
        }

        var request = URLRequest(url: url, timeoutInterval: 8.0)
        request.httpMethod = "GET"
        // Reddit returns the real post URL in Location, but only if the request
        // doesn't look like a mobile-app browser that gets served an interstitial.
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let final = response.url, final != url {
                return final
            }
        } catch {
            // fall through — return original
        }
        return url
    }

    static func diagnostics(for items: [NSExtensionItem]) -> String {
        var lines: [String] = []
        for (itemIdx, item) in items.enumerated() {
            if let text = item.attributedContentText?.string, !text.isEmpty {
                lines.append("item[\(itemIdx)].text=\"\(text.prefix(80))\"")
            }
            for (provIdx, provider) in (item.attachments ?? []).enumerated() {
                let types = provider.registeredTypeIdentifiers.joined(separator: ", ")
                lines.append("attach[\(itemIdx).\(provIdx)]: \(types)")
            }
        }
        return lines.isEmpty ? "no attachments" : lines.joined(separator: "\n")
    }

    // MARK: - Private

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        // Prefer the typed API — handles NSURL decoding for us.
        if provider.canLoadObject(ofClass: URL.self) {
            if let url: URL = await withCheckedContinuation({ continuation in
                _ = provider.loadObject(ofClass: URL.self) { value, _ in
                    continuation.resume(returning: value)
                }
            }) {
                return url
            }
        }
        // Fall back to loadItem, which may return URL, NSURL, String, or Data.
        let value: NSSecureCoding? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { value, _ in
                continuation.resume(returning: value)
            }
        }
        if let url = value as? URL { return url }
        if let str = value as? String, let url = URL(string: str) { return url }
        if let data = value as? Data, let str = String(data: data, encoding: .utf8), let url = URL(string: str) { return url }
        return nil
    }

    private static func loadString(from provider: NSItemProvider, typeIdentifier: String) async -> String? {
        let value: NSSecureCoding? = await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { value, _ in
                continuation.resume(returning: value)
            }
        }
        if let str = value as? String { return str }
        if let data = value as? Data, let str = String(data: data, encoding: .utf8) { return str }
        if let url = value as? URL { return url.absoluteString }
        return nil
    }

    private static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                return url
            }
        }
        return nil
    }
}
