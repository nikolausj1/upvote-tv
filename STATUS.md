---
title: "STATUS - Upvote TV"
created: 2026-07-24
modified: 2026-08-28
version: 1.5
author: Claude Fable 5 (claude-fable-5)
tags:
---

# Upvote TV - Status

## Project

A personal tvOS + iOS app suite that turns a shared household queue (captured via an iPhone Share Extension, stored in a GitHub Gist) into a polished Apple TV browsing and watching experience for Reddit posts and YouTube videos.

## Stage

Live (all six planned v1 phases are done and shipped; Phase 7's optional Reddit API integration is drafted but not yet submitted)

## Health

🟡 Recovering. Reddit resolution silently died on the Apple TV in late August. Two causes, both in `RedditRateLimiter`: it could persist a poisoned far-future reset time and then refuse every request forever across launches, and a 429 with no usable reset hint left the resume timestamp in the past, turning "wait out the window" into a 250 ms retry loop that pinned the shared budget at zero. A third supposed cause — Reddit quadrupling its rate-limit prices — was a **measurement error**: burst re-measurement gives ~33 units per RSS feed, not ~1,200, so a 59-item queue costs ~2,000 of the 9,000-unit window and fits in one pass. Fixed across four commits on `fix/reddit-rate-limiting-and-hydration` (unmerged, a clean fast-forward ahead of `main`): limiter self-heals poisoned state, always parks in the future after a 429, re-checks the plausibility ceiling in-session; cost constants corrected; block pages and moderator-removed titles no longer cached as titles; thumbnail-failure invalidation age-gated and capped; confirmed-removed posts hidden from Browse and no longer allowed to overwrite good cached metadata. Built, signed, installed and running on the living-room Apple TV. Back to green once the queue visibly re-hydrates.

On 2026-08-28 all 70 remaining queue items were resolved directly against Reddit to audit the queue: 70 alive, 5 confirmed `[deleted]` (`1vx2iev`, `1vna92a`, `1u9jd5u`, `1u8k7vi`, `1u7cn6z`), which were pruned from the gist. The "[ Removed by moderator ]" cards on the TV were **stale cache, not dead posts** — those items resolve alive today and will show real titles once re-resolved.

## Waiting on Me

- [ ] **Watch the Browse list for a few minutes and confirm titles fill in** (~5 min)
      - unblocks: confirming the 2026-08-27 fix worked in the real world. At the corrected ~33 units per feed the whole 70-item queue costs ~2,300 of the 9,000-unit window, so it should hydrate in roughly one pass rather than several — though the budget is shared with everything else on the household IP. Posts still showing raw URLs after a few minutes are worth reporting
- [ ] **Merge `fix/reddit-rate-limiting-and-hydration` into `main`** (~2 min)
      - unblocks: getting the fix off a branch. Deployed and running on the Apple TV, but the branch is unmerged
- [ ] **Submit the Reddit Data API application** (~15 min)
      - unblocks: gallery posts, score, and the NSFW flag for Reddit items, plus a documented rate limit instead of an undocumented shared per-IP budget. A submission-ready draft is at `docs/Reddit-Data-API-Application.md`; it addresses the "lacks necessary details" rejection. Review the numbers, then submit.
- [ ] **Share one Reddit post from an iPhone to confirm share-time metadata writes correctly** (~2 min)
      - unblocks: verifying queue schema v2 against the real gist. The code path is unit tested and both targets build, but no share has run end-to-end on a physical phone yet
- [ ] **Decide the queue retention policy: auto-prune items older than N days / watched more than N days ago, or let it grow until manually removed** (~5 min)
      - unblocks: whether a pruning feature is worth building, and keeps the Gist file from growing forever
- [ ] **Decide whether NSFW-off should also hide YouTube items (they carry no NSFW flag, so they are currently always shown)** (~5 min)
      - unblocks: consistent NSFW behavior across both content sources

## Next Up

1. Submit the Reddit API application, then make the two open product decisions (queue retention, NSFW/YouTube).
2. Watch the first few shares land to confirm metadata is being written into `queue.json` as schema v2.
3. Revisit the queue retention question once the queue passes roughly 150 items, which is where per-refresh cost starts to matter again even with the long cache.

## Biggest Risk

Reddit metadata still depends on undocumented public surfaces: the RSS feed plus a crawler User-Agent for the OpenGraph fallback. Reddit already gated the `.json` endpoint once (June 2026). The 30-day cache and share-time resolution mean an outage would degrade slowly rather than all at once, but a gated RSS feed still ends Reddit resolution until Data API access is approved.

---

## Ideas Shelf

- **Search or filter within the queue** (S) - listed as a v2+ future consideration, no design work started
- **Manual refresh gesture** (S) - small UX addition, listed as a future consideration
- **Auto-prune or flag dead posts** (S) - the resolver detects deleted/removed posts; offer to drop them from the queue instead of just labelling them
- **Watched-state sync via CloudKit** (M) - so a post watched in the living room also shows watched on the bedroom Apple TV
- **Additional source support (Twitter/X, Instagram Reels, TikTok, Bluesky)** (L) - each needs its own metadata resolver and domain whitelist entry

## Lessons

- **Check for rate-limit headers before assuming an API is "blocked".** Reddit's public endpoints looked dead (every request returned 429) but were actually metering a **unit budget** advertised in `x-ratelimit-used` / `-remaining` / `-reset`: about 9000 units per rolling 60-second window per IP, with each request costing a variable amount by response size rather than 1. Reading those headers turned an apparent outage into a solvable pacing problem. Worth checking on any third-party HTTP integration before concluding an endpoint is gated. (promoted to Build Guide v4.1, 2026-08-02)
- **Under a throttle, a short-backoff retry makes things worse.** Retrying after 400 ms spends more of an already-empty budget. The fix is a single shared governor that reads the reset time from the response and parks every caller until the window rolls over. Retry *after* the wait, never instead of it. (promoted to Build Guide v4.1, 2026-08-02)
- **When several endpoints can answer, measure their cost, not just their content.** The lighter RSS feed carried strictly more information than the HTML preview page at roughly a third of the cost, so the richer-looking endpoint became the fallback and the problem mostly dissolved. Rank fallbacks by cost-per-value. (promoted to Build Guide v4.1, 2026-08-02)
- **Ask a paginated endpoint for less.** Adding `?limit=1` to Reddit's comment feed cut the response from 33.5 KB to 3.5 KB and about halved its rate-limit cost, because everything past the first entry was being downloaded, charged for, and discarded. Check whether any feed or list endpoint you only need the head of supports a limit parameter. (promoted to Build Guide v4.1, 2026-08-02)
- **Measure rolling-window rate limits with a burst, not with spaced samples.** Deltas between requests seconds apart are contaminated by older requests ageing out of the window, which inflated our per-request cost estimate by an order of magnitude. Fire N identical requests back-to-back after a fresh window and average. (promoted to Build Guide v4.1, 2026-08-02)
- **Match cache TTL to how fast the data can actually change, not to a habit.** A 24-hour TTL on immutable facts (a post's title, author, publish date) meant re-spending the entire rate-limit budget daily to re-learn things that cannot change. Thirty days plus a stable per-item jitter took steady-state traffic to near zero. The jitter matters: a queue hydrated in one burst otherwise expires in one burst. Derive it from a stable hash, never Swift's `hashValue`, which is seeded per process and reshuffles every launch. (promoted to Build Guide v4.1, 2026-08-02)
- **Stream a slow hydration instead of blocking on it.** When a rate limit makes a full load genuinely slow, waiting for the last item before showing the first turns an unavoidable delay into a blank screen. Emitting progressive snapshots (cached first, then each result as it lands) took a cold start from about 4 minutes of skeleton to about 8 seconds. Watch the empty-state guard: "nothing resolved yet" must not be read as "nothing to show". (promoted to Build Guide v4.1, 2026-08-02)
- **Push per-item work to the moment a human causes it.** Moving metadata resolution into the iOS Share Extension turned one bursty 59-request refresh into single requests spread across whenever someone actually shares something. Keep the enrichment strictly optional and time-capped so the user-facing action can never be delayed or lost by it. (promoted to Build Guide v4.1, 2026-08-02)
- **Persisted backoff state needs a plausibility check on load, or one bad value bricks the feature forever.** A rate limiter that saves "budget exhausted until T" to disk must refuse to adopt a T that the protocol makes impossible (here: more than 120s out for a rolling 60s window). Without that, a single unclamped header, proxy quirk, or clock rollback wedges every future launch — no request is ever issued, so the state that would correct it is never refreshed. Clamp on write *and* validate on read; make the store clearable. (promoted to Build Guide v11.0, 2026-08-28)
- **Cache-invalidation triggers driven by observed failures must be rate-limited.** "Image failed to load → mark stale → re-resolve" is correct for one rotted URL and catastrophic for sixty at once (one offline moment, or signed URLs that all expired together because they were fetched together). Gate such triggers by minimum entry age and a per-cycle cap, or a transient outage converts the whole cache into a thundering herd against the very rate limit the cache exists to protect. (promoted to Build Guide v11.0, 2026-08-28)
- **A surprising measurement is more likely your methodology than the vendor's behaviour.** Spaced-sample deltas suggested Reddit had quadrupled its per-request rate-limit cost, which was used to justify making the limiter 36x more conservative. A burst re-measurement showed the true cost was ~33 units, an order of magnitude *below* even the original figure — every number in the chain had been contaminated by requests ageing out of the rolling window and by other devices sharing the egress IP. This project had already written down "measure with a burst, not spaced samples" and then did it wrong again under time pressure. Before concluding a third party changed something, re-run the measurement the way your own notes say to. (promoted to Build Guide v11.0, 2026-08-28)
- **Re-derive the premise when a fix underperforms, not just the fix.** "A 59-item queue cannot be hydrated inside one rate-limit window" was load-bearing for the concurrency limit, the reserves, the 30-day TTL, and the progressive-hydration design. At the real per-request cost the whole queue costs ~2,000 of 9,000 units and fits in one window, so the premise was false and several of those designs were solving a problem that did not exist. Write the measurement that a premise rests on into the code next to the constant it justifies, so the premise is falsifiable later. (promoted to Build Guide v11.0, 2026-08-28)
- **Any wait-then-retry path must guarantee the wait is in the future.** A 429 whose reset hint was missing or already elapsed left the resume timestamp in the past, so the "park until the window rolls over" branch computed a zero-length wait, cleared the budget reading, and fired again — turning the exact short-backoff retry loop the component existed to prevent into the steady state, and pinning the shared budget at zero. When a timestamp comes from a header, assert its direction before sleeping on it. (promoted to Build Guide v11.0, 2026-08-28)
