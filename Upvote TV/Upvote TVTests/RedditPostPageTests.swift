import Testing
import Foundation
@testable import Upvote_TV

// MARK: - Fixtures

/// The `<shreddit-post>` element from a real `reddit.com/comments/1wybtdf/` page, captured
/// 2026-10-09 and trimmed to the attributes the parser reads plus a few it must ignore.
/// Note the boolean attributes with no value (`hide-awards-button`, `is-embeddable`) and the
/// six-digit fractional timestamp with a colon-less offset — both are what Reddit emits.
private let samplePostTag = """
<shreddit-post class="block xs:mt-xs" permalink="/r/sports/comments/1wybtdf/after_a_couple_hours_of_highquality_tennis_daniil/" \
content-href="https://v.redd.it/u7jjlh675oth1" view-context="CommentsPage" comment-count="1097" hide-awards-button \
moderation-verdict="" is-embeddable created-timestamp="2026-10-05T15:41:09.265000+0000" domain="v.redd.it" id="t3_1wybtdf" \
post-title="After a couple hours of high-quality tennis, Daniil Medvedev hits a ball in anger &amp; is defaulted" \
post-language="en" post-type="video" score="9989" subreddit-prefixed-name="r/sports" author-id="t2_8lemz" \
author="Large_banana_hammock" icon="https://styles.redditmedia.com/t5_1xcht7/styles/profileIcon_snoo.png" subreddit-name="sports">
"""

private let samplePlayerTag = """
<shreddit-player src="https://v.redd.it/u7jjlh675oth1/HLSPlaylist.m3u8?f=hd%2CsubsAll%2ChlsSpecOrder&amp;v=1&amp;a=1794126759%2COGRl" \
class="block h-full" autoplay post-type="video" \
poster="https://external-preview.redd.it/after-a-couple-hours-v0-aWluMDlz.png?width=640&amp;crop=smart&amp;auto=webp&amp;s=7fb0">
"""

private func page(post: String = samplePostTag, player: String? = samplePlayerTag, extra: String = "") -> String {
    """
    <!DOCTYPE html><html><head><title>Reddit - The heart of the internet</title></head><body>
    <img src="https://preview.redd.it/snoovatar/avatars/a66728db-headshot.png?width=64">
    \(post)\(player ?? "")\(extra)
    </body></html>
    """
}

/// The interstitial Reddit serves ahead of the page, verbatim in shape (2026-10-09).
private func challengePage(token: String = "2824be10929bdc604753c70a67a1c331d66f98903221ff8a069792aa6071a447",
                           constant: String = "71187860cc48ed10",
                           postID: String = "1wybtdf") -> String {
    """
    <!DOCTYPE html><html><head><title>Reddit</title></head><body>
    <form hidden method="GET" action="/comments/\(postID)/">
      <input type="hidden" name="solution" />
      <input type="hidden" name="js_challenge" value="1"/>
      <input type="hidden" name="jsc_token" value="\(token)"/>
      <input type="hidden" name="jsc_orig_r" value=""/>
    </form>
    <script>
      document.addEventListener("DOMContentLoaded",async function(){var e=document.forms[0],n=(e.onsubmit=function(t){return !0},await(async e=>e+e)("\(constant)"));e.elements.namedItem("solution").value=n,e.requestSubmit()},{once:!0});
    </script></body></html>
    """
}

private let blockPage = """
<html><body><h1>You've been blocked by network security.</h1>
<p>If you think you've been blocked by mistake, file a ticket below and we'll look into it.</p></body></html>
"""

private func pageItem(id: String) -> QueueItem {
    QueueItem(id: id,
              url: URL(string: "https://www.reddit.com/comments/\(id)")!,
              source: .reddit,
              sharedAt: Date(timeIntervalSince1970: 1_780_000_000))
}

private func makePageResolver() -> RedditMetadataResolver {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return RedditMetadataResolver(session: URLSession(configuration: config),
                                  limiter: RedditRateLimiter(profile: .feed),
                                  pageLimiter: RedditRateLimiter(profile: .page))
}

private func limiterResponse(status: Int, headers: [String: String]) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://www.reddit.com/comments/abc/")!,
                    statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
}

// MARK: - Page parsing

struct RedditPostPageParsingTests {

    @Test func readsTheCardFieldsOffTheShredditPostElement() throws {
        let parsed = try #require(RedditPostPage.parse(page()))
        #expect(parsed.postType == "video")
        // Entities in attribute values are decoded once.
        #expect(parsed.title == "After a couple hours of high-quality tennis, Daniil Medvedev hits a ball in anger & is defaulted")
        #expect(parsed.subreddit == "sports")
        #expect(parsed.author == "Large_banana_hammock")
        #expect(parsed.domain == "v.redd.it")
        #expect(parsed.contentHref?.absoluteString == "https://v.redd.it/u7jjlh675oth1")
        #expect(parsed.permalink?.absoluteString == "https://www.reddit.com/r/sports/comments/1wybtdf/after_a_couple_hours_of_highquality_tennis_daniil/")
        #expect(parsed.isNSFW == false)
        #expect(parsed.isUnavailable == false)
    }

    @Test func parsesRedditsSixDigitColonlessTimestamp() throws {
        let parsed = try #require(RedditPostPage.parse(page()))
        let expected = ISO8601DateFormatter().date(from: "2026-10-05T15:41:09Z")!
        let published = try #require(parsed.published)
        #expect(abs(published.timeIntervalSince(expected) - 0.265) < 0.01)
    }

    @Test func reducesTheSignedPlaylistToItsStableForm() throws {
        let parsed = try #require(RedditPostPage.parse(page()))
        // The player's src carries an expiring signature; the bare playlist is what the RSS
        // path has always cached, so both paths produce the same media URL for a post.
        #expect(parsed.hlsURL?.absoluteString == "https://v.redd.it/u7jjlh675oth1/HLSPlaylist.m3u8")
    }

    @Test func fallsBackToContentHrefWhenThePlayerIsMissing() throws {
        let parsed = try #require(RedditPostPage.parse(page(player: nil)))
        #expect(parsed.hlsURL?.absoluteString == "https://v.redd.it/u7jjlh675oth1/HLSPlaylist.m3u8")
    }

    @Test func prefersThePlayerPosterAndSkipsAvatars() throws {
        let parsed = try #require(RedditPostPage.parse(page()))
        #expect(parsed.previewImage?.host == "external-preview.redd.it")
        // Without a player, the avatar on preview.redd.it must not be mistaken for the post's image.
        let noPlayer = try #require(RedditPostPage.parse(page(player: nil)))
        #expect(noPlayer.previewImage == nil)
    }

    @Test func fallsBackToTheSubredditPrefixedNameWhenTheBareNameIsAbsent() throws {
        let tag = samplePostTag.replacingOccurrences(of: " subreddit-name=\"sports\"", with: "")
        let parsed = try #require(RedditPostPage.parse(page(post: tag)))
        #expect(parsed.subreddit == "sports")
    }

    @Test func readsTheNSFWBooleanAttribute() throws {
        let tag = samplePostTag.replacingOccurrences(of: " is-embeddable", with: " is-embeddable nsfw")
        let parsed = try #require(RedditPostPage.parse(page(post: tag)))
        #expect(parsed.isNSFW == true)
    }

    @Test func recognisesAModeratorRemovedPost() throws {
        // Captured from queue post 1wsq8kp on 2026-10-09: Reddit keeps the element but
        // replaces the title and points content-href back at the permalink.
        let tag = samplePostTag
            .replacingOccurrences(of: "post-title=\"After a couple hours of high-quality tennis, Daniil Medvedev hits a ball in anger &amp; is defaulted\"",
                                  with: "post-title=\"[ Removed by moderator ]\"")
            .replacingOccurrences(of: "content-href=\"https://v.redd.it/u7jjlh675oth1\"",
                                  with: "content-href=\"https://www.reddit.com/r/funny/comments/1wsq8kp/removed_by_moderator/\"")
        let parsed = try #require(RedditPostPage.parse(page(post: tag)))
        #expect(parsed.isUnavailable)
    }

    @Test func refusesAnythingWithoutAShredditPost() {
        #expect(RedditPostPage.parse(blockPage) == nil)
        #expect(RedditPostPage.parse(challengePage()) == nil)
        #expect(RedditPostPage.parse("<html><head><title>Reddit - Dive into anything</title></head></html>") == nil)
    }

    @Test func attributeParserHandlesBooleanAndValuedAttributesInAnyOrder() {
        let attrs = RedditPostPage.attributes(in: " a=\"1\" flag b=\"two &amp; three\" another-flag")
        #expect(attrs["a"] == "1")
        #expect(attrs["flag"] == "")
        #expect(attrs["b"] == "two & three")
        #expect(attrs["another-flag"] == "")
    }

    @Test func stableHLSURLAcceptsOnlyRedditVideoHosts() {
        #expect(RedditPostPage.stableHLSURL(URL(string: "https://v.redd.it/abc123/HLSPlaylist.m3u8?a=1")!)?.absoluteString
                == "https://v.redd.it/abc123/HLSPlaylist.m3u8")
        #expect(RedditPostPage.stableHLSURL(URL(string: "https://v.redd.it/abc123")!)?.absoluteString
                == "https://v.redd.it/abc123/HLSPlaylist.m3u8")
        #expect(RedditPostPage.stableHLSURL(URL(string: "https://i.redd.it/abc123.png")!) == nil)
        #expect(RedditPostPage.stableHLSURL(URL(string: "https://v.redd.it/")!) == nil)
    }
}

// MARK: - Challenge

struct RedditChallengeTests {

    @Test func recognisesTheServedSolverAndDoublesTheConstant() throws {
        let challenge = try #require(RedditPostPage.Challenge.challenge(in: challengePage()))
        #expect(challenge.token == "2824be10929bdc604753c70a67a1c331d66f98903221ff8a069792aa6071a447")
        #expect(challenge.constant == "71187860cc48ed10")
        // The constant in the script is the thing doubled — not the form token. Submitting
        // token+token is what got this project a network-security block page.
        #expect(challenge.solution == "71187860cc48ed1071187860cc48ed10")
    }

    @Test func buildsTheSameURLTheBrowserWouldSubmit() throws {
        let challenge = try #require(RedditPostPage.Challenge.challenge(in: challengePage()))
        let url = try #require(challenge.solvedURL(for: URL(string: "https://www.reddit.com/comments/1wybtdf/")!))
        #expect(url.absoluteString == "https://www.reddit.com/comments/1wybtdf/?solution=71187860cc48ed1071187860cc48ed10&js_challenge=1&jsc_token=2824be10929bdc604753c70a67a1c331d66f98903221ff8a069792aa6071a447&jsc_orig_r=")
    }

    @Test func refusesAnUnfamiliarSolverRatherThanGuessing() {
        // Same form, different arithmetic: must not be answered with e+e.
        let hardened = challengePage().replacingOccurrences(of: "(async e=>e+e)", with: "(async e=>e.split(\"\").reverse().join(\"\"))")
        #expect(RedditPostPage.Challenge.challenge(in: hardened) == nil)
        #expect(RedditPostPage.Challenge.challenge(in: blockPage) == nil)
        #expect(RedditPostPage.Challenge.challenge(in: page()) == nil)
    }
}

// MARK: - End to end (stubbed network)

/// Each test uses its own post ID: `StubURLProtocol`'s table is process-wide and suites run
/// in parallel, so IDs are the isolation boundary.
struct RedditPageResolveTests {

    private func feedURL(_ id: String) -> String { "https://www.reddit.com/comments/\(id).rss?limit=1" }
    private func pageURL(_ id: String) -> String { "https://www.reddit.com/comments/\(id)/" }

    private func solvedURL(_ id: String) -> String {
        RedditPostPage.Challenge.challenge(in: challengePage(postID: id))!
            .solvedURL(for: URL(string: pageURL(id))!)!.absoluteString
    }

    @Test func resolvesAVideoFromThePageWhenTheFeedIsGone() async throws {
        // 2026-11-13: the feed URL stops being a feed. Reddit may 404 it, or serve HTML.
        let id = "pg01feed"
        StubURLProtocol.setStubs([
            feedURL(id): .init(status: 404, body: "nope"),
            pageURL(id): .init(body: challengePage(postID: id)),
            solvedURL(id): .init(body: page(), headers: ["x-ratelimit-remaining": "223", "x-ratelimit-reset": "370"])
        ])
        let meta = try await makePageResolver().resolve(pageItem(id: id))

        #expect(meta.title == "After a couple hours of high-quality tennis, Daniil Medvedev hits a ball in anger & is defaulted")
        #expect(meta.subreddit == "sports")
        #expect(meta.author == "Large_banana_hammock")
        #expect(meta.postType == .video)
        #expect(meta.mediaURL?.absoluteString == "https://v.redd.it/u7jjlh675oth1/HLSPlaylist.m3u8")
        #expect(meta.thumbnailURL != nil)
        #expect(meta.isNSFW == false)
        #expect(meta.publishedAt != nil)
        #expect(meta.outboundURL?.absoluteString.hasSuffix("/comments/1wybtdf/after_a_couple_hours_of_highquality_tennis_daniil/") == true)

        // Exactly one challenge round-trip, and no OpenGraph fetch: the page had everything.
        let requested = StubURLProtocol.requestedURLs
        #expect(requested.filter { $0 == pageURL(id) }.count == 1)
        #expect(requested.filter { $0 == solvedURL(id) }.count == 1)
    }

    @Test func skipsTheChallengeWhenTheSessionAlreadyHasCookies() async throws {
        // A second post in the same session is served straight — no interstitial.
        let id = "pg02cook"
        StubURLProtocol.setStubs([
            feedURL(id): .init(status: 404, body: ""),
            pageURL(id): .init(body: page())
        ])
        let meta = try await makePageResolver().resolve(pageItem(id: id))
        #expect(meta.postType == .video)
        #expect(StubURLProtocol.requestedURLs.filter { $0.contains(id) && $0.contains("js_challenge") }.isEmpty)
    }

    @Test func aRemovedPostOnThePageBecomesAnExplicitDeadCard() async throws {
        let tag = samplePostTag
            .replacingOccurrences(of: "post-title=\"After a couple hours of high-quality tennis, Daniil Medvedev hits a ball in anger &amp; is defaulted\"",
                                  with: "post-title=\"[ Removed by moderator ]\"")
        let id = "pg03gone"
        StubURLProtocol.setStubs([
            feedURL(id): .init(status: 404, body: ""),
            pageURL(id): .init(body: page(post: tag))   // the player tag is still there — must be ignored
        ])
        let meta = try await makePageResolver().resolve(pageItem(id: id))
        #expect(meta.title == RedditMetadataResolver.unavailableTitle)
        #expect(meta.postType == .unsupported)
        #expect(meta.mediaURL == nil)
        #expect(meta.subreddit == "sports")
    }

    @Test func fallsThroughToOpenGraphWhenThePageIsBlocked() async throws {
        // The page URL doubles as the OpenGraph URL (different UA), so the stub answers both
        // with the same body: an unfurl shell with no shreddit-post and no challenge.
        let id = "pg04ogfb"
        StubURLProtocol.setStubs([
            feedURL(id): .init(status: 404, body: ""),
            pageURL(id): .init(body: """
                <html><head><title>Ted Lasso - Season 4 Official Trailer : r/television</title>
                <meta property="og:image" content="https://external-preview.redd.it/ted.png"/>
                <meta property="og:url" content="https://www.reddit.com/r/television/comments/\(id)/x/"/>
                </head></html>
                """)
        ])
        let meta = try await makePageResolver().resolve(pageItem(id: id))
        #expect(meta.title == "Ted Lasso - Season 4 Official Trailer")
        #expect(meta.subreddit == "television")
        #expect(meta.mediaURL == nil)
    }

    @Test func anUnsolvableChallengeIsAMissNotAWrongAnswer() async {
        let id = "pg05hard"
        let hardened = challengePage(postID: id).replacingOccurrences(of: "(async e=>e+e)", with: "(async e=>e+\"x\")")
        StubURLProtocol.setStubs([
            feedURL(id): .init(status: 404, body: ""),
            pageURL(id): .init(body: hardened)
        ])
        await #expect(throws: MetadataResolveError.self) {
            try await makePageResolver().resolve(pageItem(id: id))
        }
        // Never submitted a guess.
        #expect(StubURLProtocol.requestedURLs.filter { $0.contains(id) && $0.contains("js_challenge") }.isEmpty)
    }

    @Test func theFeedStillWinsWhileItLasts() async throws {
        let id = "pg06feed"
        StubURLProtocol.setStubs([
            feedURL(id): .init(body: """
                <?xml version="1.0"?><feed><entry><category term="sports" label="r/sports"/>\
                <content type="html">&lt;a href=&quot;https://v.redd.it/u7jjlh675oth1&quot;&gt;[link]&lt;/a&gt;</content>\
                <media:thumbnail url="https://external-preview.redd.it/x.png" />\
                <title>From the feed</title></entry>
                """, headers: ["x-ratelimit-remaining": "8000", "x-ratelimit-reset": "50"]),
            pageURL(id): .init(body: challengePage(postID: id))
        ])
        let meta = try await makePageResolver().resolve(pageItem(id: id))
        #expect(meta.title == "From the feed")
        #expect(meta.isNSFW == nil)   // the feed never says
        #expect(!StubURLProtocol.requestedURLs.contains(pageURL(id)))
    }
}

// MARK: - Page budget profile

struct RedditPageBudgetTests {

    @Test func pageProfileBelievesASixMinuteReset() async {
        let limiter = RedditRateLimiter(profile: .page)
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        await limiter.record(limiterResponse(status: 200, headers: [
            "x-ratelimit-remaining": "224", "x-ratelimit-reset": "372"
        ]))
        let diagnostics = await limiter.diagnostics
        let reset = diagnostics.windowResetsAt?.timeIntervalSinceNow ?? 0
        // The feed profile would have clamped this to 120s and woken up into a 429.
        #expect(reset > 360 && reset <= 372)
    }

    @Test func pageProfileReservesInPageUnitsNotFeedUnits() async {
        let limiter = RedditRateLimiter(profile: .page)
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        // 25 units left: comfortably above the 20-unit reserve for the first request, but
        // each in-flight page is assumed to cost 3, so the second must hold.
        await limiter.record(limiterResponse(status: 200, headers: [
            "x-ratelimit-remaining": "25", "x-ratelimit-reset": "300"
        ]))
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        let admitted = await limiter.acquire(before: Date().addingTimeInterval(0.5))
        #expect(!admitted)
    }

    @Test func feedProfileStillClampsToItsOwnWindow() async {
        let limiter = RedditRateLimiter(profile: .feed)
        #expect(await limiter.acquire(before: Date().addingTimeInterval(5)))
        await limiter.record(limiterResponse(status: 200, headers: [
            "x-ratelimit-remaining": "8000", "x-ratelimit-reset": "372"
        ]))
        let reset = await limiter.diagnostics.windowResetsAt?.timeIntervalSinceNow ?? 0
        #expect(reset <= 120)
    }

    @Test func budgetsPersistUnderSeparateKeys() {
        let feed = RedditRateLimiter.Persistence.standard(profile: .feed)
        let pageStore = RedditRateLimiter.Persistence.standard(profile: .page)
        let soon = Date().addingTimeInterval(60)
        feed.save(4000, soon)
        pageStore.save(200, soon.addingTimeInterval(300))
        #expect(feed.load()?.remaining == 4000)
        #expect(pageStore.load()?.remaining == 200)
        feed.clear()
        pageStore.clear()
        #expect(feed.load() == nil)
        #expect(pageStore.load() == nil)
    }
}
