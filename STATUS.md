---
title: "STATUS - Upvote TV"
created: 2026-07-24
modified: 2026-08-27
version: 1.4
author: Claude Fable 5 (claude-fable-5)
tags:
---

# Upvote TV - Status

## Project

A personal tvOS + iOS app suite that turns a shared household queue (captured via an iPhone Share Extension, stored in a GitHub Gist) into a polished Apple TV browsing and watching experience for Reddit posts and YouTube videos.

## Stage

Live (all six planned v1 phases are done and shipped; Phase 7's optional Reddit API integration is drafted but not yet submitted)

## Health

🟡 Recovering. Reddit resolution silently died on the Apple TV in late August: the rate limiter could persist a poisoned far-future reset time and then refuse every request forever, and Reddit quadrupled per-request rate-limit costs (~1,200 units/feed vs ~300 at tuning time), so mass cache invalidation from rotting thumbnail URLs collapsed refreshes into 429s. A fix landed 2026-08-27 (uncommitted on `fix/reddit-rate-limiting-and-hydration`): the limiter clamps and self-heals poisoned state on launch, block pages and moderator-removed titles are detected instead of cached as titles, thumbnail-failure invalidation is age-gated and capped, and cost constants were re-measured. All three targets build; unit tests pass. Needs a deploy to the Apple TV to take effect.

## Waiting on Me

- [ ] **Deploy the 2026-08-27 resolver/limiter fix to the Apple TV** (~10 min)
      - unblocks: Reddit posts resolving again. Commit the working tree on `fix/reddit-rate-limiting-and-hydration`, build to the Apple TV, and relaunch; the new build discards the jammed rate-limiter state automatically
- [ ] **Submit the Reddit Data API application** (~15 min)
      - unblocks: gallery posts, score, and the NSFW flag for Reddit items, plus a documented rate limit instead of an undocumented shared per-IP budget. A submission-ready draft is at `docs/Reddit-Data-API-Application.md`; it addresses the "lacks necessary details" rejection. Review the numbers, then submit.
- [ ] **Share one Reddit post from an iPhone to confirm share-time metadata writes correctly** (~2 min)
      - unblocks: verifying queue schema v2 against the real gist. The code path is unit tested and both targets build, but no share has run end-to-end on a physical phone yet
- [ ] **Remove the 3 posts that no longer exist on Reddit from the queue** (~2 min)
      - unblocks: they render honestly as "Post no longer available on Reddit" but are dead weight. Post IDs: `1u9jd5u`, `1u8k7vi`, `1u7cn6z`
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
- **Persisted backoff state needs a plausibility check on load, or one bad value bricks the feature forever.** A rate limiter that saves "budget exhausted until T" to disk must refuse to adopt a T that the protocol makes impossible (here: more than 120s out for a rolling 60s window). Without that, a single unclamped header, proxy quirk, or clock rollback wedges every future launch — no request is ever issued, so the state that would correct it is never refreshed. Clamp on write *and* validate on read; make the store clearable.
- **Cache-invalidation triggers driven by observed failures must be rate-limited.** "Image failed to load → mark stale → re-resolve" is correct for one rotted URL and catastrophic for sixty at once (one offline moment, or signed URLs that all expired together because they were fetched together). Gate such triggers by minimum entry age and a per-cycle cap, or a transient outage converts the whole cache into a thundering herd against the very rate limit the cache exists to protect.
- **Third-party rate-limit prices are not constants — re-measure when behavior degrades.** Reddit roughly quadrupled per-request unit costs between early and late August 2026 with no announcement; every tuned constant (assumed cost, reserves, concurrency) silently became wrong. Encode measured costs as named constants with the measurement date in a comment, and treat "the queue stopped hydrating" as a cue to re-measure before debugging code.
