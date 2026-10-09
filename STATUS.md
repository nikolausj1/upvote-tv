---
title: "STATUS - Upvote TV"
created: 2026-07-24
modified: 2026-10-09
version: 1.9
author: Claude Fable 5.1 (claude-fable-5-1)
tags:
---

# Upvote TV - Status

## Project

A personal tvOS + iOS app suite that turns a shared household queue (captured via an iPhone Share Extension, stored in a GitHub Gist) into a polished Apple TV browsing and watching experience for Reddit posts and YouTube videos.

## Stage

Live (all six planned v1 phases are done and shipped; Phase 7, the optional Reddit API integration, is retired because Reddit closed public API access)

## Health

🟡 Recovering, with a working path past the RSS shutdown. Two things changed on 2026-10-09:

**1. The post-RSS resolver exists and works.** Reddit's full post page (`reddit.com/comments/{id}/`) carries everything the RSS feed did plus the NSFW flag, including the `v.redd.it` HLS URL, behind a small JavaScript challenge whose answer is a 16-character constant in the served script, doubled. It was built into `RedditMetadataResolver` as the fallback tier between RSS and OpenGraph (`Shared/RedditPostPage.swift`), with a second `RedditRateLimiter` profile for the page's separate budget (~225 units per ~6-minute window, 2 units a page, so a 100-item queue fits in one window). Verified live against the real queue from a plain client with a tvOS-style User-Agent: 8/8 posts from Python, 4/4 from the Swift resolver, every video with a playable HLS URL, the one moderator-removed post correctly surfaced as a dead card, challenge solved once per session. RSS stays primary until it stops answering on 2026-11-13; nothing changes on the TV before then. The remaining exposure is Reddit hardening the challenge: the solver recognises exactly one script shape and falls through to OpenGraph (titles, no video) on anything else. Also learned the hard way: doubling the form's 64-character `jsc_token` instead of the script constant earns a 403 "blocked by network security" page, which is what the 2026-10-01 note's "token+token" shorthand would have produced.

**2. The zero-metadata mystery is solved: stale build on the phone.** The live gist (98 items, 27 shared since September) carried no `metadata` blocks because the envelope's `version` is 1, and the version-2 writer only landed in git on 2026-08-02. Justin's iPhone was still running the April Share Extension. The resolver code itself resolved the three newest queue posts in ~0.2 s each from the Mac. The Mobile app (with the Share Extension) was rebuilt and installed on Justin's iPhone via devicectl at 01:30, so share-time metadata is live on that phone. The final build with the page resolver (commit `d80d593`) was then installed on both Justin's iPhone and the living-room Apple TV at ~11:40, after the devicectl tunnel wedged for an hour and had to be cleared by restarting the CoreDevice/RemotePairing services (noted in `INSTALL.md` under `Upvote TV/build/ready-to-install/`). **Other household phones still run the old build** and need the same reinstall; until then their shares arrive bare and the TV resolves them, exactly as before.

Yellow rather than green because (a) the Browse list has still not been watched filling in titles on the real device since the August limiter fix, (b) the page path has only been exercised from the Mac, not yet on the Apple TV, and (c) no share has yet been confirmed landing with a metadata block from the reinstalled phone.

Previous state (2026-10-01), kept for context: 🔴 Reddit announced (r/modnews `1wubgvt`) that RSS feeds stop on 2026-11-13 with no replacement, and the OpenGraph page carries no video, so in-app Reddit playback was set to end for anything shared after mid-November. The Data API is no longer a fallback: new public requests closed 2026-10-31, all public access ends March 2027, and the Developer Platform cannot post to `api.github.com` without a gated review and bars off-platform apps.

Earlier (2026-08-31): Reddit resolution silently died on the Apple TV in late August from a poisoned persisted rate-limit reset and a 429 retry loop in `RedditRateLimiter`; both fixed, merged and installed on the living-room Apple TV. Burst re-measurement put the real feed cost at ~33 units, not ~1,200. On 2026-08-28 the queue was audited: 70 alive, 5 confirmed deleted and pruned.

## Waiting on Me

- [ ] **Open Upvote TV on the Apple TV and watch Browse fill in titles for a few minutes** (~5 min) — **this is the gate on Health returning to green**
      - unblocks: confirming the August limiter fix on the real device. The 2026-10-09 build (`d80d593`, 83/83 tests) is installed on the TV and on Justin's iPhone. To exercise the page path before November, share a brand-new post and watch it resolve, or clear one post's cache
- [ ] **Reinstall Upvote TV Mobile on every other household iPhone** (~5 min each, phone in hand)
      - unblocks: share-time metadata from those phones. Justin's phone is done. Confirm by sharing one post and checking the gist item carries a `metadata` block (the envelope `version` will flip to 2 on the next write from a new build)
- [ ] **Share one Reddit post from the reinstalled iPhone and re-read the gist** (~2 min)
      - unblocks: closing the share-time metadata item for good. Expected: a `metadata` block with title, subreddit, author, thumbnail and `mediaURL`
- [ ] **Decide whether to flip the page resolver to primary before 2026-11-13** (~5 min)
      - unblocks: nothing yet; RSS is cheaper (3.5 KB vs 1.1 MB per post) and still works, so the current order (RSS → page → OpenGraph) is right until the feed dies and the fallthrough is automatic. The decision only matters if RSS starts degrading early. Note the page path is the only one that carries the NSFW flag
- [ ] **Decide the queue retention policy: auto-prune items older than N days / watched more than N days ago, or let it grow until manually removed** (~5 min)
      - unblocks: whether a pruning feature is worth building, and keeps the Gist file from growing forever. The queue is at 98 items
- [ ] **Decide whether NSFW-off should also hide YouTube items (they carry no NSFW flag, so they are currently always shown)** (~5 min)
      - unblocks: consistent NSFW behavior across both content sources. Reddit items resolved via the page path now carry the flag; RSS-resolved ones still do not
- [x] ~~Decide the post-RSS Reddit strategy before 2026-11-13~~ — decided 2026-10-09 by building it: option (b)/(e), the full post page behind the JS challenge, as an automatic fallback tier in the shared resolver. Works on the phone and the TV alike, no API, no WebView. Options (a) accept the downgrade, (c) Developer Platform and (d) drop Reddit are off the table unless Reddit hardens the challenge
- [x] ~~Confirm why the live gist has zero `metadata` blocks across 96 items~~ — stale April build on the phone; see Health
- [x] ~~Retire the Reddit Data API application~~ — `docs/Reddit-Data-API-Application.md` carries a "Retired, do not submit" banner; README Phase 7 row marked Retired
- [x] **Merge `fix/reddit-rate-limiting-and-hydration` into `main`** — done 2026-08-31

## Next Up

1. Install the new build on the Apple TV, watch Browse hydrate, and reinstall the Mobile app on the other household phones. Then confirm one share lands with metadata.
2. Commit the 2026-10-09 work (page resolver, limiter profiles, NSFW flag, docs) once Justin has looked it over; the working tree holds it uncommitted alongside the 2026-10-01 doc edits.
3. Probe an NSFW post through the page path before November (possible age-gate interstitial; untested) and confirm the tvOS `URLSession` is not fingerprinted differently from the Mac.
4. Make the two open product decisions (queue retention, NSFW/YouTube).

## Biggest Risk

Reddit hardens the JavaScript challenge in front of the post page. It is a bot gate and is designed to change; the solver recognises exactly one script shape (`(async e=>e+e)("…")`). If that shape changes after RSS ends on 2026-11-13, the resolver falls through to OpenGraph and Reddit items quietly lose in-app video (titles and thumbnails survive). The 30-day cache buys a month of grace for anything already resolved, and share-time resolution on the phones spreads the exposure across one request per share rather than a bursty refresh, but there is no API fallback left. Watch for `isUnavailable`-free posts arriving as `.link` with no `mediaURL` after mid-November; that is the symptom.

---

## Ideas Shelf

- **Resolver diagnostics screen on tvOS** (S) - show both rate-limit budgets, which tier answered each post, and whether the page challenge was solved this session; would have shortened every Reddit investigation so far
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
- **A fix that exists only in git is not deployed. Check the artifact the users actually run.** Share-time metadata was "implemented and unit tested" for two months while every real share arrived without it, because the phone still ran the build from before the feature. The tell was in the data (`version: 1` in the envelope the phone wrote), and `xcrun devicectl device info apps` confirms what is installed. After shipping any change to an on-device component, install it and verify from the data it produces, not from the build log. (2026-10-09)
- **Read the solver, don't paraphrase it.** A note said the challenge answer was "token+token". The script actually doubles a different, shorter constant embedded in the script; doubling the form token earned a hard 403 block page that looked like Reddit had closed the door. When reverse-engineering a client-side check, keep the exact script in the notes (or a fixture) and make the parser match that shape only, so a change is detected as "unknown" rather than answered wrongly. (2026-10-09)
- **Keep one cookie-bearing session per unit of work when a site gates on a one-time challenge.** Solving once and letting the session carry `token_v2`/`loid` meant 1 challenge for 8 posts; a fresh session per request would have paid it every time and looked like a bot. An ephemeral `URLSession` already keeps cookies in memory for its lifetime; the only design decision is to create it once per resolver, not per call. (2026-10-09)
