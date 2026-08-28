import Foundation

/// Process-wide governor for Reddit's unauthenticated rate limit.
///
/// **Why this exists.** Reddit meters the preview and RSS endpoints with a *unit budget*,
/// not a request count. Every response carries `x-ratelimit-used` / `-remaining` / `-reset`,
/// the budget is ~9000 units per rolling 60-second window per IP, and each request costs a
/// variable amount — measured on the endpoints this app uses: RSS ~1200 units, the heavier
/// HTML preview page ~2500 (re-measured 2026-08-27 after Reddit repriced both; previously
/// ~150-350 / ~230-780). A queue of 50+ posts simply cannot be hydrated inside one window,
/// so firing every resolve at once burns the budget in a few seconds and every remaining
/// post comes back 429 and renders as a raw-URL fallback card.
///
/// **How it works.** Every Reddit request passes through `acquire(before:)` and hands its
/// response back via `record(_:)`. The governor tracks the reported budget, discounts the
/// requests it has admitted but not yet heard back from, and parks callers until the window
/// resets once the projected budget drops under `reserve`. A 429 is treated as budget
/// exhaustion, not as a reason to retry — retrying into the wall is what deepens the hole.
///
/// This is an actor with a single shared instance because the budget is per-IP: throttling
/// each resolver independently would still let ten concurrent resolves overshoot together.
actor RedditRateLimiter {
    static let shared = RedditRateLimiter(persistence: .standard)

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

    /// Conservative per-request cost estimate for in-flight requests. Sized to the RSS feed
    /// — the common, essential request — rather than the heavier OG fallback page; the
    /// opportunistic path below carries its own larger reserve to cover that heavier cost.
    /// Re-measured 2026-08-27 after Reddit repriced both endpoints (previously 800, when
    /// the feed cost ~150-350 and the HTML page ~230-780; now ~1200 and ~2500 respectively).
    private static let assumedRequestCost: Double = 1200
    /// Units held back so an unlucky burst still lands inside the budget. Re-measured
    /// 2026-08-27 alongside `assumedRequestCost` (was 1200) — large enough that even an
    /// unaccounted heavier OG-page request landing through this gate doesn't overshoot.
    private static let reserve: Double = 2500
    /// The much larger cushion optional work must clear. Enrichment that only improves a
    /// card (a thumbnail) must never crowd out the fetches that make it render at all.
    /// Must comfortably clear the ~2500-unit OG page cost the opportunistic fetch actually
    /// spends (was 3500, sized against the old ~780-unit ceiling).
    private static let opportunisticReserve: Double = 4500
    /// Used when Reddit 429s without telling us when the window resets.
    private static let blindCooldown: TimeInterval = 20

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

        static let standard = Persistence(
            load: {
                let defaults = UserDefaults.standard
                guard let resetsAt = defaults.object(forKey: Keys.resetsAt) as? Date,
                      defaults.object(forKey: Keys.remaining) != nil else { return nil }
                return (defaults.double(forKey: Keys.remaining), resetsAt)
            },
            save: { remaining, resetsAt in
                let defaults = UserDefaults.standard
                defaults.set(remaining, forKey: Keys.remaining)
                defaults.set(resetsAt, forKey: Keys.resetsAt)
            },
            clear: {
                let defaults = UserDefaults.standard
                defaults.removeObject(forKey: Keys.remaining)
                defaults.removeObject(forKey: Keys.resetsAt)
            }
        )

        private enum Keys {
            static let remaining = "RedditRateLimiter.remaining"
            static let resetsAt = "RedditRateLimiter.resetsAt"
        }
    }

    init(persistence: Persistence? = nil) {
        self.persistence = persistence
        // A stored window has to fall inside a plausible rolling-60s range. Already rolled
        // over (in the past) tells us nothing; more than 120s out is not a real window at
        // all — it's a poisoned reading (e.g. a reset offset that was never clamped) that
        // would otherwise refuse every request forever. Either way, don't adopt it, and
        // don't leave it sitting in UserDefaults to be reread next launch.
        if let stored = persistence?.load() {
            let now = Date()
            if stored.resetsAt > now && stored.resetsAt <= now.addingTimeInterval(120) {
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

            if hasHeadroom(clearing: Self.reserve) {
                outstanding += 1
                return true
            }

            // Out of budget: wait for the window to roll over rather than retry into a 429.
            let resumeAt = windowResetsAt ?? Date().addingTimeInterval(Self.blindCooldown)
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
        guard hasHeadroom(clearing: Self.opportunisticReserve) else { return false }
        outstanding += 1
        return true
    }

    /// Feeds a response's rate-limit headers back into the governor. Must be called exactly
    /// once for every successful `acquire`, including when the request threw or returned no
    /// response — otherwise `outstanding` leaks and the gate slowly closes for good.
    func record(_ response: HTTPURLResponse?) {
        outstanding = max(0, outstanding - 1)

        guard let response else { return }

        // Clamp to the same 120s ceiling as the 429 retry-after below: a rolling 60s window
        // can never legitimately report a reset further out than that, and adopting a bad
        // value here (a malformed header, a proxy quirk) would otherwise refuse every
        // request until real time catches up to it.
        if let resetValue = header(response, "x-ratelimit-reset"), let seconds = Double(resetValue), seconds > 0 {
            windowResetsAt = Date().addingTimeInterval(min(seconds, 120))
        }

        if response.statusCode == 429 {
            // Reddit has cut us off. Treat the budget as spent and wait out the window;
            // prefer an explicit Retry-After if one is present.
            remaining = 0
            if let retryValue = header(response, "retry-after"), let seconds = Double(retryValue) {
                windowResetsAt = Date().addingTimeInterval(min(seconds, 120))
            } else if windowResetsAt == nil {
                windowResetsAt = Date().addingTimeInterval(Self.blindCooldown)
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
        let projected = remaining - (Double(outstanding) * Self.assumedRequestCost)
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
