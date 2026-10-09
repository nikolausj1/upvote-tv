import Foundation

/// Process-wide governor for Reddit's unauthenticated rate limits.
///
/// **Why this exists.** Reddit meters its public surfaces with *unit budgets*, not request
/// counts. Every response carries `x-ratelimit-used` / `-remaining` / `-reset`, and each
/// request costs a variable amount by response size. Two budgets matter to this app, and
/// they are metered separately (both measured by burst against the live queue):
///
/// - **Feed / preview** (`Profile.feed`): the RSS feed and the OpenGraph preview page share
///   a ~9000-unit, rolling 60-second, per-IP window. ~33 units for a `?limit=1` feed, ~190
///   for the OG page including its 301 hop (burst-measured 2026-08-27).
/// - **Post page** (`Profile.page`): the full `reddit.com/comments/{id}/` page sits behind
///   a ~225-unit window that resets roughly every 6 minutes. 2 units per page
///   (burst-measured 2026-10-09: `x-ratelimit-used` climbed 1, 3, 5, … across eight
///   back-to-back fetches, `-reset` counted down from 372s).
///
/// Firing every resolve at once burns a budget in seconds, and every remaining post comes
/// back 429 and renders as a raw-URL fallback card.
///
/// **How it works.** Every Reddit request passes through `acquire(before:)` and hands its
/// response back via `record(_:)`. The governor tracks the reported budget, discounts the
/// requests it has admitted but not yet heard back from, and parks callers until the window
/// resets once the projected budget drops under the profile's `reserve`. A 429 is treated as
/// budget exhaustion, not as a reason to retry — retrying into the wall is what deepens the
/// hole.
///
/// This is an actor with one shared instance *per budget* because each budget is per-IP:
/// throttling each resolver independently would still let ten concurrent resolves overshoot
/// together.
actor RedditRateLimiter {
    /// Governor for the feed / OpenGraph budget.
    static let shared = RedditRateLimiter(profile: .feed, persistence: .standard(profile: .feed))
    /// Governor for the full post-page budget, which Reddit meters separately.
    static let page = RedditRateLimiter(profile: .page, persistence: .standard(profile: .page))

    /// The shape of one of Reddit's budgets. Constants that used to be hard-coded for the
    /// feed window now live here so the same governor can run the post-page budget, whose
    /// window is six minutes long and whose units are two orders of magnitude scarcer.
    struct Profile: Sendable, Equatable {
        /// Short name used to key persisted state, so the two budgets never read each
        /// other's readings back.
        var name: String
        /// How long the rolling window is believed to last. Only used to bound what a
        /// plausible `x-ratelimit-reset` can be: anything beyond twice this is poison.
        var windowLength: TimeInterval
        /// Conservative per-request cost charged to in-flight requests until their
        /// response lands.
        var assumedRequestCost: Double
        /// Units held back so an unlucky burst still lands inside the budget.
        var reserve: Double
        /// The much larger cushion optional work must clear. Enrichment that only improves
        /// a card (a thumbnail) must never crowd out the fetches that make it render at all.
        var opportunisticReserve: Double
        /// Used when Reddit 429s without telling us when the window resets.
        var blindCooldown: TimeInterval

        /// Ceiling on any reset hint we will believe. A rolling window can never
        /// legitimately report a reset further out than this.
        var maxPlausibleReset: TimeInterval { windowLength * 2 }

        /// RSS feed + OpenGraph preview page: ~9000 units per rolling 60s.
        ///
        /// Cost: measured 2026-08-27 by burst, 8 back-to-back requests inside a single
        /// window gave consecutive `x-ratelimit-used` deltas of 29-38 units for a feed, so
        /// ~33 real, 50 to be safe. Every earlier figure in this file's history (800, then
        /// 1200, and the ~150-350 in the docs) came from samples spaced seconds apart,
        /// which is not a measurement: older requests age out of the rolling window
        /// between samples and other devices on the same IP land in the gaps, so the
        /// deltas describe the household's traffic, not ours. Only deltas between
        /// back-to-back requests in one window mean anything.
        ///
        /// Reserve: four concurrent OG-page fetches (~200 each, the expensive path) is 800,
        /// so 1000 clears a worst-case full-concurrency burst with room over.
        static let feed = Profile(
            name: "feed", windowLength: 60, assumedRequestCost: 50,
            reserve: 1000, opportunisticReserve: 3000, blindCooldown: 20
        )

        /// Full post page: ~225 units per ~6-minute window, 2 units a page.
        ///
        /// Reserve: `resolverConcurrency` (4) pages in flight at 3 assumed units is 12, so
        /// 20 clears a full burst. The opportunistic cushion is irrelevant here (nothing
        /// optional uses this budget) but kept proportionate.
        static let page = Profile(
            name: "page", windowLength: 400, assumedRequestCost: 3,
            reserve: 20, opportunisticReserve: 60, blindCooldown: 60
        )
    }

    let profile: Profile

    /// Units Reddit last told us were left in the current window.
    private var remaining: Double?
    /// When the current window rolls over, derived from `x-ratelimit-reset`.
    private var windowResetsAt: Date?
    /// Where window state is carried across launches, if anywhere.
    private let persistence: Persistence?
    /// Requests admitted but not yet accounted for by a response. Their cost is not in
    /// `remaining` yet, so it has to be estimated or concurrent callers all see a stale
    /// budget and pile through the gate together.
    private var outstanding: Int = 0

    // MARK: - Persistence

    /// Carries the window state across launches. Without it, every cold start begins
    /// blind: if the app was killed mid-window, or another app on the same IP spent the
    /// budget, the first few requests discover that by eating 429s. Since the window is
    /// only 60 seconds, anything older than that is discarded as useless.
    struct Persistence: Sendable {
        var load: @Sendable () -> (remaining: Double, resetsAt: Date)?
        var save: @Sendable (Double, Date) -> Void
        /// Removes any stored reading. Called when the in-memory window is dropped, so a
        /// stale or poisoned value never outlives the state it was cached alongside.
        var clear: @Sendable () -> Void = {}

        /// `UserDefaults`-backed storage, keyed per budget so the feed and page governors
        /// never adopt each other's readings. The feed profile keeps the original
        /// (unsuffixed) keys so an upgrade inherits whatever the previous build learned.
        static func standard(profile: Profile) -> Persistence {
            let suffix = profile == .feed ? "" : ".\(profile.name)"
            let remainingKey = "RedditRateLimiter.remaining" + suffix
            let resetsAtKey = "RedditRateLimiter.resetsAt" + suffix
            return Persistence(
                load: {
                    let defaults = UserDefaults.standard
                    guard let resetsAt = defaults.object(forKey: resetsAtKey) as? Date,
                          defaults.object(forKey: remainingKey) != nil else { return nil }
                    return (defaults.double(forKey: remainingKey), resetsAt)
                },
                save: { remaining, resetsAt in
                    let defaults = UserDefaults.standard
                    defaults.set(remaining, forKey: remainingKey)
                    defaults.set(resetsAt, forKey: resetsAtKey)
                },
                clear: {
                    let defaults = UserDefaults.standard
                    defaults.removeObject(forKey: remainingKey)
                    defaults.removeObject(forKey: resetsAtKey)
                }
            )
        }

        /// The feed budget's storage. Kept for callers that predate profiles.
        static let standard = Persistence.standard(profile: .feed)
    }

    init(profile: Profile = .feed, persistence: Persistence? = nil) {
        self.profile = profile
        self.persistence = persistence
        // A stored window has to fall inside a plausible range for this budget. Already
        // rolled over (in the past) tells us nothing; more than twice the window out is not
        // a real window at all — it's a poisoned reading (e.g. a reset offset that was never
        // clamped) that would otherwise refuse every request forever. Either way, don't
        // adopt it, and don't leave it sitting in UserDefaults to be reread next launch.
        if let stored = persistence?.load() {
            let now = Date()
            if stored.resetsAt > now && stored.resetsAt <= now.addingTimeInterval(profile.maxPlausibleReset) {
                remaining = stored.remaining
                windowResetsAt = stored.resetsAt
            } else {
                persistence?.clear()
            }
        }
    }

    // MARK: - Gate

    /// Blocks until it is safe to issue another Reddit request.
    ///
    /// Returns `false` if waiting would run past `deadline` — the caller should give up and
    /// let the post fall back to cache rather than hold the refresh open indefinitely.
    func acquire(before deadline: Date) async -> Bool {
        while true {
            if Date() >= deadline { return false }

            if hasHeadroom(clearing: profile.reserve) {
                outstanding += 1
                return true
            }

            // Out of budget: wait for the window to roll over rather than retry into a 429.
            // Re-check the plausibility ceiling `init` and `record` both enforce — a clock
            // moved backwards mid-session can push an already-adopted reset beyond anything
            // this rolling window could produce, and nothing else would ever revisit it.
            if let stored = windowResetsAt, stored > Date().addingTimeInterval(profile.maxPlausibleReset) {
                windowResetsAt = nil
                persistence?.clear()
            }
            let resumeAt = windowResetsAt ?? Date().addingTimeInterval(profile.blindCooldown)
            guard resumeAt <= deadline else { return false }

            // +0.5s of slack so we don't race the window boundary and eat another 429.
            let nap = max(0.25, resumeAt.timeIntervalSinceNow + 0.5)
            try? await Task.sleep(for: .seconds(nap))
            if Task.isCancelled { return false }

            // Window has rolled over — drop the stale reading and re-evaluate. Other tasks
            // may have woken and done this already, which is harmless. Clear the persisted
            // copy too, so a crash before the next `record()` can't hand a cold launch an
            // exhausted reading from a window that is already gone.
            if Date() >= resumeAt {
                remaining = nil
                windowResetsAt = nil
                persistence?.clear()
            }
        }
    }

    /// Non-blocking variant for optional enrichment: admits a request only if there is
    /// budget genuinely to spare right now, and never waits. Returns `false` the moment
    /// the window is tight, so callers should treat the extra data as a bonus.
    func acquireIfBudgetToSpare() -> Bool {
        guard hasHeadroom(clearing: profile.opportunisticReserve) else { return false }
        outstanding += 1
        return true
    }

    /// Feeds a response's rate-limit headers back into the governor. Must be called exactly
    /// once for every successful `acquire`, including when the request threw or returned no
    /// response — otherwise `outstanding` leaks and the gate slowly closes for good.
    func record(_ response: HTTPURLResponse?) {
        outstanding = max(0, outstanding - 1)

        guard let response else { return }

        // Clamp to the same ceiling as the 429 retry-after below: this rolling window can
        // never legitimately report a reset further out than twice its length, and adopting
        // a bad value here (a malformed header, a proxy quirk) would otherwise refuse every
        // request until real time catches up to it.
        let ceiling = profile.maxPlausibleReset
        if let resetValue = header(response, "x-ratelimit-reset"), let seconds = Double(resetValue), seconds > 0 {
            windowResetsAt = Date().addingTimeInterval(min(seconds, ceiling))
        }

        if response.statusCode == 429 {
            // Reddit has cut us off. Treat the budget as spent and wait out the window;
            // prefer an explicit Retry-After if one is present.
            remaining = 0
            if let retryValue = header(response, "retry-after"), let seconds = Double(retryValue), seconds > 0 {
                windowResetsAt = Date().addingTimeInterval(min(seconds, ceiling))
            } else if (windowResetsAt ?? .distantPast) <= Date() {
                // A 429 with no usable hint must still park us somewhere in the future.
                // Leaving a past timestamp here is worse than having none: `acquire` reads
                // it as "the window already rolled over", naps its 0.25s floor, clears the
                // budget reading, and fires straight back into the wall — the short-backoff
                // retry loop this whole type exists to prevent.
                windowResetsAt = Date().addingTimeInterval(profile.blindCooldown)
            }
            persist()
            return
        }

        if let remainingValue = header(response, "x-ratelimit-remaining"), let value = Double(remainingValue) {
            remaining = value
        }
        persist()
    }

    private func persist() {
        guard let persistence, let remaining, let windowResetsAt else { return }
        persistence.save(remaining, windowResetsAt)
    }

    // MARK: - Internals

    /// A `nil` budget means we have no reading yet (fresh window or first request ever);
    /// let a request through so the response can teach us where we stand.
    private func hasHeadroom(clearing reserve: Double) -> Bool {
        guard let remaining else { return true }
        let projected = remaining - (Double(outstanding) * profile.assumedRequestCost)
        return projected > reserve
    }

    private func header(_ response: HTTPURLResponse, _ name: String) -> String? {
        response.value(forHTTPHeaderField: name)
    }

    // MARK: - Diagnostics / testing

    /// Current view of the budget. Exposed for tests and debugging, not used by the UI.
    var diagnostics: Diagnostics {
        Diagnostics(remaining: remaining, outstanding: outstanding, windowResetsAt: windowResetsAt)
    }

    struct Diagnostics: Sendable, Equatable {
        let remaining: Double?
        let outstanding: Int
        let windowResetsAt: Date?
    }
}
