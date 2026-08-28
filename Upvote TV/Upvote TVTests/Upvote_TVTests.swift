//
//  Upvote_TVTests.swift
//  Upvote TVTests
//
//  Created by Justin Nikolaus on 4/10/26.
//

import Testing
import Foundation
@testable import Upvote_TV

// MARK: - Fixtures

/// A real `reddit.com/comments/{id}.rss` post entry, trimmed to the fields the resolver
/// reads. Captured from the live feed so the escaping matches what Reddit actually emits —
/// note the doubly-escaped `&amp;amp;` inside the HTML `<content>` block.
private let sampleEntry = """
<author><name>/u/Smartastic</name><uri>https://www.reddit.com/user/Smartastic</uri></author>\
<category term="JeffArcuri" label="r/JeffArcuri"/>\
<content type="html">&lt;table&gt; &lt;tr&gt;&lt;td&gt; \
&lt;a href=&quot;https://www.reddit.com/r/JeffArcuri/comments/1v3ko5f/make_it_sloppy/&quot;&gt; \
&lt;img src=&quot;https://external-preview.redd.it/YjdhbGt3N2cydGVo.png?width=640&amp;amp;crop=smart&quot; \
alt=&quot;Make it sloppy&quot; /&gt; &lt;/a&gt; &lt;/td&gt;&lt;td&gt; &amp;#32; submitted by &amp;#32; \
&lt;span&gt;&lt;a href=&quot;https://v.redd.it/2qdxn2ag2teh1&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt; \
&lt;/td&gt;&lt;/tr&gt;&lt;/table&gt;</content>\
<id>t3_1v3ko5f</id>\
<media:thumbnail url="https://external-preview.redd.it/YjdhbGt3N2cydGVo.png?width=640&amp;crop=smart" />\
<link href="https://www.reddit.com/r/JeffArcuri/comments/1v3ko5f/make_it_sloppy/" />\
<updated>2026-07-22T16:11:42+00:00</updated>\
<published>2026-07-22T16:11:42+00:00</published>\
<title>Make it sloppy</title></entry>
"""

private func makeResponse(status: Int, headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://www.reddit.com/comments/abc.rss")!,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!
}

// MARK: - RSS parsing

struct RedditRSSParsingTests {

    @Test func extractsBarePostTitle() {
        #expect(RedditMetadataResolver.tagTitle(in: sampleEntry) == "Make it sloppy")
    }

    @Test func extractsSubredditWithOriginalCasing() {
        #expect(RedditMetadataResolver.rssSubreddit(in: sampleEntry) == "JeffArcuri")
    }

    @Test func extractsAuthorWithoutUserPrefix() {
        #expect(RedditMetadataResolver.rssAuthor(in: sampleEntry) == "Smartastic")
    }

    @Test func extractsPublishedDate() throws {
        let date = try #require(RedditMetadataResolver.rssPublished(in: sampleEntry))
        // 2026-07-22T16:11:42+00:00
        let expected = ISO8601DateFormatter().date(from: "2026-07-22T16:11:42Z")!
        #expect(abs(date.timeIntervalSince(expected)) < 1)
    }

    @Test func extractsCanonicalPermalink() {
        let url = RedditMetadataResolver.rssCanonical(in: sampleEntry)
        #expect(url?.absoluteString == "https://www.reddit.com/r/JeffArcuri/comments/1v3ko5f/make_it_sloppy/")
    }

    @Test func mediaThumbnailIsDecodedOnce() {
        // The `url` attribute is singly escaped, so `&amp;` becomes a usable `&`.
        #expect(RedditMetadataResolver.metaThumbnail(in: sampleEntry)
                == "https://external-preview.redd.it/YjdhbGt3N2cydGVo.png?width=640&crop=smart")
    }

    @Test func contentImageSurvivesDoubleEscaping() {
        // `<content>` is escaped markup containing an already-escaped URL, so finding the
        // <img> and then using its src takes two decode passes. A single pass leaves
        // `&amp;` in the query string and the image fails to load.
        #expect(RedditMetadataResolver.contentImage(in: sampleEntry)
                == "https://external-preview.redd.it/YjdhbGt3N2cydGVo.png?width=640&crop=smart")
    }

    @Test func detectsRedditHostedVideo() {
        #expect(RedditMetadataResolver.firstMatch(
            in: sampleEntry, pattern: "v\\.redd\\.it/([A-Za-z0-9]+)", group: 1) == "2qdxn2ag2teh1")
    }

    @Test func acceptsARealFeedByBodyOrContentType() {
        #expect(RedditMetadataResolver.looksLikeAtomFeed(
            body: "<?xml version=\"1.0\"?><feed><entry>…", contentType: nil))
        #expect(RedditMetadataResolver.looksLikeAtomFeed(
            body: "<feed xmlns=\"…\">", contentType: "text/html"))
        #expect(RedditMetadataResolver.looksLikeAtomFeed(
            body: "<html><title>Reddit</title></html>", contentType: "application/atom+xml; charset=UTF-8"))
    }

    @Test func rejectsABlockPageMasqueradingAsTheFeed() {
        // A 200 with an HTML interstitial instead of the feed — no "<feed" up top, no XML
        // content-type. Trusting this would read the block page's <title> as the post's.
        #expect(!RedditMetadataResolver.looksLikeAtomFeed(
            body: "<html><head><title>Reddit - Dive into anything</title></head></html>",
            contentType: "text/html"))
    }
}

// MARK: - Unavailable posts

struct RedditUnavailablePostTests {

    @Test(arguments: ["[deleted]", "[removed]", "  [Deleted]  ", "[REMOVED]",
                       "[ Removed by moderator ]", "[ Removed by Reddit ]"])
    func recognizesGonePosts(_ title: String) {
        #expect(RedditMetadataResolver.isUnavailableTitle(title))
    }

    @Test(arguments: ["Make it sloppy", "[deleted] scenes from the cutting room", "", "deleted",
                       "This post was removed from the front page for brigading"])
    func leavesRealTitlesAlone(_ title: String) {
        #expect(!RedditMetadataResolver.isUnavailableTitle(title))
    }

    @Test func nilTitleIsNotTreatedAsUnavailable() {
        #expect(!RedditMetadataResolver.isUnavailableTitle(nil))
    }
}

// MARK: - Placeholder images

struct RedditPlaceholderImageTests {

    @Test func rejectsRedditsGenericBrandedCard() {
        // Reddit serves this identical image as og:image for every post lacking a preview.
        #expect(RedditMetadataResolver.isPlaceholderImage(
            URL(string: "https://i.redd.it/o0h58lzmax6a1.png")!))
    }

    @Test func rejectsStaticBrandAssets() {
        #expect(RedditMetadataResolver.isPlaceholderImage(
            URL(string: "https://www.redditstatic.com/icon.png")!))
    }

    @Test func acceptsGenuinePreviewImages() {
        #expect(!RedditMetadataResolver.isPlaceholderImage(
            URL(string: "https://external-preview.redd.it/YjdhbGt3N2cydGVo.png?width=640")!))
        #expect(!RedditMetadataResolver.isPlaceholderImage(
            URL(string: "https://i.redd.it/abc123xyz.jpg")!))
    }
}

// MARK: - Entity decoding

struct EntityDecodingTests {

    @Test func decodesOneLevelPerPass() {
        // `&amp;` must be replaced last, or `&amp;lt;` collapses two levels at once and
        // the escaped-markup-inside-XML parsing in `contentImage` breaks.
        #expect(RedditMetadataResolver.decodeEntities("&amp;lt;b&amp;gt;") == "&lt;b&gt;")
        #expect(RedditMetadataResolver.decodeEntities("&lt;b&gt;") == "<b>")
    }

    @Test func decodesNumericEntities() {
        #expect(RedditMetadataResolver.decodeEntities("caf&#233;") == "café")
        #expect(RedditMetadataResolver.decodeEntities("&#x2764;") == "❤")
    }

    @Test func leavesPlainTextUntouched() {
        #expect(RedditMetadataResolver.decodeEntities("no entities here") == "no entities here")
    }

    @Test func splitsPageTitleFromSubreddit() throws {
        let parsed = try #require(
            RedditMetadataResolver.splitTitleAndSubreddit("Ted Lasso - Season 4 Trailer : r/television"))
        #expect(parsed.title == "Ted Lasso - Season 4 Trailer")
        #expect(parsed.subreddit == "television")
    }

    @Test func leavesTitlesWithoutSubredditSuffixAlone() {
        #expect(RedditMetadataResolver.splitTitleAndSubreddit("Just a title") == nil)
    }
}

// MARK: - End-to-end resolve (stubbed network)

/// Serves canned responses so the resolver's full path can be exercised without touching
/// Reddit — and without spending the rate-limit budget the real endpoints meter.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        var status: Int = 200
        var body: String = ""
        var headers: [String: String] = [:]
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _stubs: [String: Stub] = [:]
    /// Every URL requested so far, so tests can assert what was *not* fetched.
    nonisolated(unsafe) private static var _requested: [String] = []

    static func setStubs(_ stubs: [String: Stub]) {
        lock.lock(); defer { lock.unlock() }
        _stubs = stubs
        _requested = []
    }

    static var requestedURLs: [String] {
        lock.lock(); defer { lock.unlock() }
        return _requested
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.lock()
        Self._requested.append(url.absoluteString)
        let stub = Self._stubs[url.absoluteString]
        Self.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.status,
                                       httpVersion: "HTTP/1.1", headerFields: stub.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func makeStubbedResolver() -> RedditMetadataResolver {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    // A fresh limiter per resolver so tests never inherit the shared budget state.
    return RedditMetadataResolver(session: URLSession(configuration: config),
                                  limiter: RedditRateLimiter())
}

private func feed(wrapping entry: String) -> String {
    "<?xml version=\"1.0\"?><feed><entry>\(entry)"
}

private func queueItem(id: String) -> QueueItem {
    QueueItem(id: id,
              url: URL(string: "https://www.reddit.com/comments/\(id)")!,
              source: .reddit,
              sharedAt: Date(timeIntervalSince1970: 1_780_000_000))
}

/// Serialized: `StubURLProtocol`'s stub table is process-wide, so these tests would
/// otherwise overwrite each other's canned responses when run in parallel.
@Suite(.serialized)
struct RedditResolveEndToEndTests {

    @Test func resolvesVideoPostFromRSSWithoutFetchingTheHTMLPage() async throws {
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/1v3ko5f.rss?limit=1":
                .init(body: feed(wrapping: sampleEntry),
                      headers: ["x-ratelimit-remaining": "8000", "x-ratelimit-reset": "50"])
        ])
        let post = try await makeStubbedResolver().resolve(queueItem(id: "1v3ko5f"))

        #expect(post.title == "Make it sloppy")
        #expect(post.subreddit == "JeffArcuri")
        #expect(post.author == "Smartastic")
        #expect(post.postType == .video)
        #expect(post.mediaURL?.absoluteString == "https://v.redd.it/2qdxn2ag2teh1/HLSPlaylist.m3u8")
        #expect(post.thumbnailURL != nil)
        // The whole point of the RSS-first path: the expensive HTML page is never touched
        // when the feed already answered.
        #expect(!StubURLProtocol.requestedURLs.contains { $0.hasSuffix("/comments/1v3ko5f/") })
    }

    @Test func deletedPostBecomesAnExplicitDeadCard() async throws {
        let goneEntry = """
        <author><name>/u/someone</name></author>\
        <category term="PoursTea" label="r/PoursTea"/>\
        <content type="html">&lt;span&gt;&lt;a href=&quot;https://v.redd.it/deadvid123&quot;&gt;[link]&lt;/a&gt;&lt;/span&gt;</content>\
        <link href="https://www.reddit.com/r/PoursTea/comments/1u8k7vi/x/" />\
        <published>2026-06-18T05:00:00+00:00</published>\
        <title>[deleted]</title></entry>
        """
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/1u8k7vi.rss?limit=1":
                .init(body: feed(wrapping: goneEntry),
                      headers: ["x-ratelimit-remaining": "8000", "x-ratelimit-reset": "50"])
        ])
        let post = try await makeStubbedResolver().resolve(queueItem(id: "1u8k7vi"))

        // A deleted post still has a v.redd.it link in its feed entry, but the video is
        // gone — surfacing it as a playable video would just fail at playback time.
        #expect(post.title == RedditMetadataResolver.unavailableTitle)
        #expect(post.postType == .unsupported)
        #expect(post.mediaURL == nil)
        #expect(post.subreddit == "PoursTea")
    }

    @Test func fallsBackToTheHTMLPageWhenTheFeedIsUnavailable() async throws {
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/1v8xunl.rss?limit=1":
                .init(status: 404, body: "nope"),
            "https://www.reddit.com/comments/1v8xunl/":
                .init(body: """
                <html><head><title>Ted Lasso - Season 4 Official Trailer : r/television</title>
                <meta property="og:image" content="https://external-preview.redd.it/ted.png"/>
                <meta property="og:url" content="https://www.reddit.com/r/television/comments/1v8xunl/x/"/>
                </head></html>
                """)
        ])
        let post = try await makeStubbedResolver().resolve(queueItem(id: "1v8xunl"))

        #expect(post.title == "Ted Lasso - Season 4 Official Trailer")
        #expect(post.subreddit == "television")
        #expect(post.thumbnailURL?.absoluteString == "https://external-preview.redd.it/ted.png")
    }

    @Test func throwsOnlyWhenBothEndpointsFail() async {
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/deadbeef.rss?limit=1": .init(status: 404, body: ""),
            "https://www.reddit.com/comments/deadbeef/": .init(status: 404, body: "")
        ])
        await #expect(throws: MetadataResolveError.self) {
            try await makeStubbedResolver().resolve(queueItem(id: "deadbeef"))
        }
    }

    @Test func blockPageOnTheRSSEndpointIsNeverReadAsATitle() async {
        // Reddit can serve an HTML block/interstitial page with a 200 status on the RSS
        // URL. Before the body check, its bare <title> would have been cached as the post's
        // title for 30 days; now it must be treated as a failed fetch, same as a 4xx.
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/blocked1.rss?limit=1":
                .init(body: "<html><head><title>Reddit - Dive into anything</title></head><body></body></html>",
                      headers: ["Content-Type": "text/html"])
        ])
        await #expect(throws: MetadataResolveError.self) {
            try await makeStubbedResolver().resolve(queueItem(id: "blocked1"))
        }
    }

    @Test func recoversFromA429ByWaitingOutTheWindow() async throws {
        // The window is reported as already over, so the retry can proceed immediately —
        // this asserts the retry happens at all, which is what stopped posts from
        // permanently falling back to raw-URL cards when a refresh started mid-window.
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/1v3ko5f.rss?limit=1":
                .init(status: 429, body: "", headers: ["retry-after": "0"])
        ])
        let resolver = makeStubbedResolver()
        _ = try? await resolver.resolve(queueItem(id: "1v3ko5f"))
        let rssAttempts = StubURLProtocol.requestedURLs.filter { $0.contains(".rss") }.count
        #expect(rssAttempts > 1)
    }
}

// MARK: - Share-time resolution

@Suite(.serialized)
struct ShareTimeResolverTests {

    private func makeResolver(timeout: TimeInterval) -> ShareTimeResolver {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        return ShareTimeResolver(
            reddit: RedditMetadataResolver(session: session, limiter: RedditRateLimiter()),
            youtube: YouTubeMetadataResolver(session: session),
            timeout: timeout
        )
    }

    @Test func enrichesTheItemWhenResolutionSucceeds() async {
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/1v3ko5f.rss?limit=1":
                .init(body: feed(wrapping: sampleEntry),
                      headers: ["x-ratelimit-remaining": "8000", "x-ratelimit-reset": "50"])
        ])
        let metadata = await makeResolver(timeout: 10).resolve(queueItem(id: "1v3ko5f"))
        #expect(metadata?.title == "Make it sloppy")
        #expect(metadata?.postType == .video)
    }

    @Test func returnsNilRatherThanFailingTheShare() async {
        // The share must survive a dead network. nil just means the TV resolves it later.
        StubURLProtocol.setStubs([:])
        let metadata = await makeResolver(timeout: 10).resolve(queueItem(id: "1v3ko5f"))
        #expect(metadata == nil)
    }

    @Test func givesUpOnTimeRatherThanHoldingTheShareSheetOpen() async {
        StubURLProtocol.setStubs([
            "https://www.reddit.com/comments/1v3ko5f.rss?limit=1":
                .init(status: 429, body: "", headers: ["x-ratelimit-reset": "60"])
        ])
        // A 429 makes the limiter want to wait out a 60-second window. The share sheet is a
        // foreground moment, so the timeout must win well before that.
        let started = Date()
        let metadata = await makeResolver(timeout: 1).resolve(queueItem(id: "1v3ko5f"))
        #expect(metadata == nil)
        #expect(Date().timeIntervalSince(started) < 5)
    }
}

// MARK: - Cache TTL

struct CacheTTLTests {

    @Test func ttlIsLongEnoughToSurviveDailyUse() {
        // A short TTL re-spends the rate-limit budget re-learning immutable facts.
        #expect(AppConfig.cacheTTL > 7 * 24 * 60 * 60)
    }

    @Test func jitterIsStableForAGivenPost() {
        // Must not use Swift's per-process-seeded hashValue: an item's deadline has to
        // survive relaunches, or every launch reshuffles every expiry.
        let first = AppConfig.cacheTTL(forPostID: "1v3ko5f")
        let second = AppConfig.cacheTTL(forPostID: "1v3ko5f")
        #expect(first == second)
    }

    @Test func jitterSpreadsExpiryAcrossPosts() {
        let ids = ["1v3ko5f", "1u8k7vi", "1v8xunl", "1tbqp6y", "1umyxe3", "1tgau6s"]
        let ttls = Set(ids.map { AppConfig.cacheTTL(forPostID: $0) })
        // A queue hydrated in one burst must not expire in one burst.
        #expect(ttls.count > 1)
    }

    @Test func jitterStaysInsideItsWindow() {
        for id in ["a", "bb", "1v3ko5f", "zzzzzzzz", ""] {
            let ttl = AppConfig.cacheTTL(forPostID: id)
            #expect(ttl <= AppConfig.cacheTTL)
            #expect(ttl >= AppConfig.cacheTTL - AppConfig.cacheTTLJitter)
        }
    }
}

// MARK: - Queue schema v2

struct QueueSchemaTests {

    private func makeClient() -> GistQueueClient {
        GistQueueClient(gistID: "test", token: "test")
    }

    @Test func roundTripsShareTimeMetadata() throws {
        let metadata = ResolvedMetadata(
            title: "Make it sloppy",
            subreddit: "JeffArcuri",
            author: "Smartastic",
            publishedAt: Date(timeIntervalSince1970: 1_784_909_502),
            postType: .video,
            thumbnailURL: URL(string: "https://external-preview.redd.it/x.png?width=640&crop=smart"),
            mediaURL: URL(string: "https://v.redd.it/2qdxn2ag2teh1/HLSPlaylist.m3u8"),
            outboundURL: URL(string: "https://www.reddit.com/r/JeffArcuri/comments/1v3ko5f/x/"),
            domain: "reddit.com",
            resolvedAt: Date(timeIntervalSince1970: 1_785_000_000)
        )
        let item = QueueItem(id: "1v3ko5f",
                             url: URL(string: "https://www.reddit.com/comments/1v3ko5f")!,
                             source: .reddit,
                             sharedAt: Date(timeIntervalSince1970: 1_785_000_100),
                             metadata: metadata)

        let decoded = try makeClient().roundTripForTesting([item])
        let restored = try #require(decoded.first?.metadata)

        #expect(decoded.first?.id == "1v3ko5f")
        #expect(restored.title == "Make it sloppy")
        #expect(restored.subreddit == "JeffArcuri")
        #expect(restored.author == "Smartastic")
        #expect(restored.postType == .video)
        #expect(restored.mediaURL == metadata.mediaURL)
        #expect(restored.thumbnailURL == metadata.thumbnailURL)
        #expect(abs(restored.resolvedAt.timeIntervalSince(metadata.resolvedAt)) < 1)
    }

    @Test func decodesV1FilesThatHaveNoMetadata() throws {
        // Every item already in the gist was written by a v1 build. They must keep working.
        let v1 = """
        {"version": 1, "items": [
          {"id": "1v3ko5f", "url": "https://www.reddit.com/comments/1v3ko5f",
           "source": "reddit", "sharedAt": "2026-07-22T16:11:42Z"}
        ]}
        """
        let items = try makeClient().decodeForTesting(Data(v1.utf8))
        #expect(items.count == 1)
        #expect(items.first?.id == "1v3ko5f")
        // No metadata means the TV resolves it, exactly as before.
        #expect(items.first?.metadata == nil)
    }

    @Test func dropsMalformedMetadataButKeepsTheItem() throws {
        // Losing metadata costs one resolve; losing the queue entry loses the share.
        let broken = """
        {"version": 2, "items": [
          {"id": "1v3ko5f", "url": "https://www.reddit.com/comments/1v3ko5f",
           "source": "reddit", "sharedAt": "2026-07-22T16:11:42Z",
           "metadata": {"title": "x", "postType": "not-a-real-type", "resolvedAt": "2026-07-22T16:11:42Z"}}
        ]}
        """
        let items = try makeClient().decodeForTesting(Data(broken.utf8))
        #expect(items.count == 1)
        #expect(items.first?.metadata == nil)
    }
}

// MARK: - Rate limiter

struct RedditRateLimiterTests {

    @Test func admitsWhenBudgetIsUnknown() async {
        let limiter = RedditRateLimiter()
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
    }

    @Test func admitsWhileBudgetIsHealthy() async {
        let limiter = RedditRateLimiter()
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        await limiter.record(makeResponse(status: 200, headers: [
            "x-ratelimit-remaining": "8000", "x-ratelimit-reset": "50"
        ]))
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
    }

    @Test func refusesRatherThanWaitPastTheDeadline() async {
        let limiter = RedditRateLimiter()
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        // Budget exhausted and the window will not reset for another 45 seconds.
        await limiter.record(makeResponse(status: 200, headers: [
            "x-ratelimit-remaining": "10", "x-ratelimit-reset": "45"
        ]))
        // A caller that can only wait 1 second must be turned away immediately, not parked.
        let started = Date()
        let admitted = await limiter.acquire(before: Date().addingTimeInterval(1))
        #expect(!admitted)
        #expect(Date().timeIntervalSince(started) < 1)
    }

    @Test func treats429AsExhaustionRatherThanRetrying() async {
        let limiter = RedditRateLimiter()
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        await limiter.record(makeResponse(status: 429, headers: [
            "x-ratelimit-remaining": "0", "retry-after": "30"
        ]))
        let diagnostics = await limiter.diagnostics
        #expect(diagnostics.remaining == 0)
        // Retrying straight into the wall is what deepens the hole, so the gate must hold.
        let admitted = await limiter.acquire(before: Date().addingTimeInterval(0.5))
        #expect(!admitted)
    }

    @Test func reservesHeadroomForInFlightRequests() async {
        let limiter = RedditRateLimiter()
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        // 4200 units left and nothing in flight — enough for the 2500 reserve on paper,
        // but each admitted request is charged an estimated 1200 until its response lands
        // (repriced 2026-08-27; see RedditRateLimiter).
        await limiter.record(makeResponse(status: 200, headers: [
            "x-ratelimit-remaining": "4200", "x-ratelimit-reset": "40"
        ]))
        // Nothing outstanding: 4200 clears the reserve.
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        // One outstanding: projected 4200 - 1200 = 3000, still clear.
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        // Two outstanding: projected 4200 - 2400 = 1800, under the reserve — hold the line
        // rather than let a burst spend budget Reddit has not reported back yet.
        let admitted = await limiter.acquire(before: Date().addingTimeInterval(0.5))
        #expect(!admitted)
    }

    @Test func optionalWorkYieldsBudgetToEssentialWork() async {
        let limiter = RedditRateLimiter()
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        await limiter.record(makeResponse(status: 200, headers: [
            "x-ratelimit-remaining": "3000", "x-ratelimit-reset": "40"
        ]))
        // 3000 units clears the 2500 reserve for a title fetch but sits under the 4500
        // opportunistic cushion, so a thumbnail top-up must stand down while essential
        // resolves continue.
        let opportunistic = await limiter.acquireIfBudgetToSpare()
        #expect(!opportunistic)
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
    }

    @Test func carriesAnOpenWindowAcrossLaunches() async {
        // A cold launch mid-window should inherit what the last run learned instead of
        // rediscovering an exhausted budget by eating 429s.
        let resetsAt = Date().addingTimeInterval(40)
        let limiter = RedditRateLimiter(persistence: .init(
            load: { (remaining: 100, resetsAt: resetsAt) },
            save: { _, _ in }
        ))
        let admitted = await limiter.acquire(before: Date().addingTimeInterval(0.5))
        #expect(!admitted)
    }

    @Test func ignoresAWindowThatHasAlreadyRolledOver() async {
        // Stored state older than the 60-second window tells us nothing.
        let limiter = RedditRateLimiter(persistence: .init(
            load: { (remaining: 0, resetsAt: Date().addingTimeInterval(-120)) },
            save: { _, _ in }
        ))
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
    }

    @Test func ignoresAPersistedWindowFarInTheFuture() async {
        // A rolling 60s window can never legitimately reset an hour from now. Adopting a
        // reading like this (e.g. from an unclamped reset offset written before this fix)
        // would refuse every request until real time caught up to it — this is the
        // poisoned-state bug that broke resolution outright.
        let limiter = RedditRateLimiter(persistence: .init(
            load: { (remaining: 0, resetsAt: Date().addingTimeInterval(3600)) },
            save: { _, _ in }
        ))
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
    }

    @Test func clampsAReportedResetOffsetToTheWindowCeiling() async throws {
        // Reddit (or a malformed response) reporting an absurd x-ratelimit-reset must not be
        // taken at face value — same failure mode as a poisoned persisted reading.
        final class Box: @unchecked Sendable { var saved: (Double, Date)? }
        let box = Box()
        let limiter = RedditRateLimiter(persistence: .init(
            load: { nil },
            save: { remaining, resetsAt in box.saved = (remaining, resetsAt) }
        ))
        _ = await limiter.acquire(before: Date().addingTimeInterval(5))
        await limiter.record(makeResponse(status: 200, headers: [
            "x-ratelimit-remaining": "10", "x-ratelimit-reset": "999999"
        ]))
        let diagnostics = await limiter.diagnostics
        let resetsAt = try #require(diagnostics.windowResetsAt)
        #expect(resetsAt <= Date().addingTimeInterval(120.5))
        #expect(box.saved?.1 ?? Date.distantFuture <= Date().addingTimeInterval(120.5))
    }

    @Test func savesWindowStateWhenItLearnsSomething() async {
        final class Box: @unchecked Sendable { var saved: (Double, Date)? }
        let box = Box()
        let limiter = RedditRateLimiter(persistence: .init(
            load: { nil },
            save: { remaining, resetsAt in box.saved = (remaining, resetsAt) }
        ))
        _ = await limiter.acquire(before: Date().addingTimeInterval(5))
        await limiter.record(makeResponse(status: 200, headers: [
            "x-ratelimit-remaining": "4200", "x-ratelimit-reset": "30"
        ]))
        #expect(box.saved?.0 == 4200)
    }

    @Test func releasesSlotWhenRequestFailsWithoutResponse() async {
        let limiter = RedditRateLimiter()
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        #expect(await limiter.diagnostics.outstanding == 1)
        // A dropped connection has no response to learn from, but the slot must come back
        // or `outstanding` leaks and the gate closes permanently.
        await limiter.record(nil)
        #expect(await limiter.diagnostics.outstanding == 0)
    }
}
