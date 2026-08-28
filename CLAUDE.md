---
title: "Upvote TV - Project Instructions"
created: 2026-04-10
modified: 2026-08-01
version: 3.5
author: Claude Opus 4.7 (claude-opus-4-7)
tags:
---

# Upvote TV - Project Instructions

## What This Is

A personal-use app suite — a tvOS player and a small iOS companion — that displays a shared household queue of content to watch on the Apple TV. Content is captured from any iPhone in the household via the iOS share sheet (using a native Share Extension) and stored as a JSON file in a secret GitHub Gist. The tvOS app reads that queue, resolves post metadata from public unauthenticated endpoints, and presents it in a polished Apple TV interface.

Supported sources in v1: Reddit posts and YouTube videos. Not a Reddit client. Not for public distribution. See `PRD.md` for full requirements.

## Tech Stack

- **Platforms:** tvOS (main player) + iOS (companion + Share Extension)
- **Language:** Swift (shared codebase via `Shared/` synchronized group)
- **UI Framework:** SwiftUI
- **Video Playback:** AVKit (tvOS only)
- **Local Persistence:** SwiftData (tvOS only)
- **Queue Transport:** GitHub Gist (JSON file, read/write via api.github.com with a fine-grained PAT)
- **Preferences:** Settings.bundle (tvOS system settings)
- **Capture:** iOS Share Extension (`Upvote TV Share`) that uses `GistQueueClient` to PATCH the gist
- **Architecture:** MVVM with a content provider protocol abstraction on tvOS; thin direct-access on iOS

## Project Structure

One Xcode project `Upvote TV.xcodeproj` with three app targets plus tests. Files shared across targets live in `Shared/` (Xcode 16 file-system-synchronized root group included in all three targets).

```
Upvote TV/                          # Xcode workspace root
├── Shared/                         # Cross-target Swift code (tvOS + iOS + Share)
│   ├── AppConfig.swift             # Constants (Gist API base, cache TTL, etc.)
│   ├── QueueItem.swift             # Queue entry model (+ optional resolved metadata)
│   ├── QueueSource.swift           # .reddit | .youtube
│   ├── ResolvedMetadata.swift      # Transport/cache shape produced by the resolvers
│   ├── PostType.swift              # .video | .image | .youtube | .link | …
│   ├── GistQueueClient.swift       # HTTP GET/PATCH against api.github.com/gists/{id}
│   ├── RedditMetadataResolver.swift    # RSS primary, OpenGraph fallback
│   ├── RedditRateLimiter.swift         # Shared per-IP budget governor
│   ├── YouTubeMetadataResolver.swift   # oEmbed
│   ├── SecretsLoader.swift         # Reads Gist ID + PAT from Secrets.plist
│   └── URLClassifier.swift         # URL → (id, source) extraction for both platforms
│
├── Upvote TV/                      # tvOS app target (the player)
│   ├── Models/                     # Post, GalleryItem, WatchedState, CachedPost
│   ├── Providers/                  # ContentProvider, Mock, QueueContentProvider
│   ├── Services/                   # MetadataCache, WatchedStateManager, NSFWFilterService
│   ├── ViewModels/                 # GalleryViewModel
│   ├── Views/                      # Browse/, Detail/, States/
│   ├── Settings.bundle/            # NSFW toggle in tvOS system Settings
│   ├── Assets.xcassets
│   ├── Secrets.plist               # gitignored — real values
│   ├── Secrets.example.plist       # committed template
│   └── Upvote TV.entitlements      # empty (no iCloud)
│
├── Upvote TV Mobile/               # iOS companion app (explainer + connection test)
│   ├── ContentView.swift           # Single SwiftUI screen with "Test Connection"
│   ├── Upvote_TV_MobileApp.swift   # App entry point
│   ├── Secrets.plist               # symlink → ../Upvote TV/Secrets.plist
│   └── Secrets.example.plist       # symlink → ../Upvote TV/Secrets.example.plist
│
├── Upvote TV Share/                # iOS Share Extension (the capture mechanism)
│   ├── ShareViewController.swift   # UIKit entry, hosts SwiftUI via UIHostingController
│   ├── ShareRootView.swift         # SwiftUI state machine: working → success/duplicate/failure
│   ├── Info.plist                  # NSExtensionActivationSupportsWebURLWithMaxCount = 1
│   ├── Secrets.plist               # symlink
│   └── Secrets.example.plist       # symlink
│
├── Upvote TVTests/ · Upvote TVUITests/
└── Upvote TV.xcodeproj/
```

**Key architectural note:** `Shared/` is registered in `project.pbxproj` as a `PBXFileSystemSynchronizedRootGroup` referenced by **all three** targets' `fileSystemSynchronizedGroups`. Any `.swift` file dropped into `Shared/` is automatically compiled into tvOS, iOS Mobile, and the Share Extension. Single source of truth.

Reddit API (v2) code was removed between v2 and v3; there is no `Deferred/` folder. If Reddit API access is ever approved (PRD Phase 7), a new `RedditContentProvider` can be written from scratch against the current protocol.

## Critical Architecture Rules

1. **tvOS UI never talks to GitHub, Reddit, or YouTube directly.** All data flows through the `ContentProvider` protocol.
2. **MockContentProvider remains a first-class provider.** It covers all post types (including direct YouTube items and YouTube-linked Reddit posts) and is used for SwiftUI previews and offline development.
3. **The Share Extension resolves metadata at share time, best effort.** It always writes `id`, `url`, `source`, and `sharedAt`; it additionally writes a `metadata` block (title, subreddit, author, thumbnail, media URL) when it can resolve one within `AppConfig.shareResolveTimeout`.

   This reverses the original v1 rule ("write the minimum possible fields, resolve on tvOS"). The reason is rate limiting: Reddit meters per IP, and the TV's problem is that it wants the entire queue at once, while the phone wants exactly one post at the moment a human deliberately shared it. Moving the request to the phone is the least bursty possible shape.

   **The extension is never load-bearing.** Metadata is optional at every layer: on timeout, network failure, or an older build, the item is written bare and tvOS resolves it exactly as it always did. Capturing the URL is the job; enriching it is a bonus. Never let a resolution failure block or fail a share.
4. **Gist writes are whole-file PATCHes.** GitHub handles atomic replacement. Don't emulate partial updates.
5. **Graceful degradation over filtering.** Show posts even when their metadata can't fully resolve. Items with failed resolution render as a fallback card with the raw URL, not hidden.
6. **Cached content is the safety net.** If metadata refresh fails, the app must still work with cached data. A stale badge is shown per affected item.
7. **Race conditions between devices are accepted in v1.** If two iPhones PATCH the gist within the same round-trip window, the last writer wins and one share may be silently lost. Rare; not fixed in v1. Documented in PRD.
8. **Secrets stay out of git.** `Secrets.plist` is gitignored; `Secrets.example.plist` is the committed template. iOS targets symlink to the tvOS copy so there's one file, one token.
9. **`Shared/` is the only place cross-target Swift code lives.** Don't duplicate `QueueItem`, `GistQueueClient`, etc. into individual target folders. Drop new cross-platform files into `Shared/` and they're automatically compiled into all three targets.

## Metadata Resolution Notes

### Reddit Posts (RSS primary, OpenGraph fallback, current)

**The public `.json` endpoint is dead.** As of ~June 2026 Reddit gated `reddit.com/comments/{id}.json` behind the Responsible Builder Policy — every request returns a "blocked due to a network policy" page regardless of User-Agent. The authenticated OAuth API needs Data API approval (applied, **denied** for "lacks necessary details"; not reapplied yet).

Both surviving endpoints are fetched with the crawler-style User-Agent in `AppConfig.redditPreviewUserAgent`. Reddit substring-matches the `facebookexternalhit` token and serves a lightweight preview instead of a bot-verification wall.

**The RSS feed (`reddit.com/comments/{id}.rss?limit=1`) is the primary source.** Measured against the live 59-item queue it resolved 59/59 with a title and subreddit. `limit=1` matters: it asks for the post plus one comment instead of the whole thread, which measured 3.5 KB instead of 33.5 KB and about half the rate-limit units, with no loss of anything the resolver reads. Everything past the first `<entry>` was being downloaded, paid for, and discarded. The feed carries:

- the bare post title (`<title>`, no `" : r/sub"` suffix to strip),
- the subreddit with correct casing (`<category term="…" label="r/…">`),
- the author (`<author><name>/u/…`) and the real publish date (`<published>`),
- a thumbnail (`<media:thumbnail>` on ~73% of posts, with the preview `<img>` inside the escaped `<content>` block as a second source),
- and the actual media, so `v.redd.it` video still plays in-app via `https://v.redd.it/{id}/HLSPlaylist.m3u8`.

**The OpenGraph HTML page is a fallback only.** It costs roughly 2x more rate-limit budget than the feed (see below) while carrying strictly less information, so it is fetched only when (a) RSS produced no usable title, or (b) RSS produced no thumbnail *and* the rate-limit window has budget to spare (`acquireIfBudgetToSpare`). Titles are essential; thumbnails are a bonus that must never crowd them out.

**Rate limiting is the dominant constraint. This is what broke the queue.** Reddit meters both endpoints on a **~9000-unit budget per rolling 60-second window, per IP**, reported via `x-ratelimit-used` / `-remaining` / `-reset`. Cost is per-response-size, not per-request: measured (as of 2026-08-27, after Reddit repriced both endpoints) ~1,200 units for a feed, ~2,500 for an HTML page — up from ~150-350 / ~230-780 at original measurement. A 59-item queue therefore **cannot** be hydrated inside one window. Fanning out 10 concurrent resolves × 2 requests each exhausted the budget in seconds and every remaining post came back 429 and rendered as a raw-URL fallback card.

`RedditRateLimiter` (a shared actor, one instance per process because the budget is per-IP) is the single choke point. Every request passes `acquire(before:)` and returns its response via `record(_:)`. It discounts requests admitted but not yet answered, holds back a reserve, and on a 429 waits out the window rather than retrying into the wall. **Never add a short-backoff retry here.** Retrying while throttled just spends more budget and deepens the hole.

- **Deleted posts** still have a feed entry, but the title is `[deleted]` / `[removed]` and the media is gone. They resolve to `PostType.unsupported` with an explicit "Post no longer available on Reddit" title, so they read as dead rather than as a video that fails on playback.
- **Reddit's generic branded `og:image`** (`i.redd.it/o0h58lzmax6a1.png`) is served for any post without a real preview. It is filtered out by `isPlaceholderImage`, since it is the same image on every such post and the style guide rules out Reddit branding anyway.
- **Still lost vs. the old JSON path** (restore if/when OAuth is approved): gallery arrays, score, and the `over_18` flag, so **NSFW filtering does not apply to Reddit items**.
- `PostCardRow` shows a thumbnail for any post carrying a preview image, not just inherently-visual types.

**If Reddit Data API access is approved (PRD Phase 7):** write a JSON/OAuth resolver against `oauth.reddit.com` producing the same `normalize → Post` shape. The notes below describe that richer JSON structure.

- **v.redd.it videos:** Audio and video are separate DASH streams. Use the `hls_url` field from `media.reddit_video` for AVKit playback. The `fallback_url` is video-only (no audio).
- **Gallery posts:** Image data is split across `gallery_data.items` (ordering) and `media_metadata` (URLs). URLs in `media_metadata` are HTML-encoded and need decoding.
- **Image resolution:** The `preview.images` array has multiple resolutions. Use one close to 1920px wide for TV (the `source` can be very large).
- **NSFW flag:** Use `over_18` field for filtering (only when NSFW toggle is disabled in Settings).
- **YouTube-linked Reddit posts:** Detect via `domain` containing "youtube.com" or "youtu.be". Classify as `PostType.youtube`. Extract the video ID from `url_overridden_by_dest` and store in `outboundURL`.

### YouTube Videos (via `https://www.youtube.com/oembed`)

Unauthenticated oEmbed endpoint. Returns `title`, `author_name`, `thumbnail_url`, and dimensions. Does NOT return duration. YouTube items always classify as `PostType.youtube`.

### Hydration Tiers

`QueueContentProvider` satisfies each item from the cheapest source that can answer, and only the last one costs a Reddit request:

1. **Share-time metadata** already in `queue.json` (see Architecture Rule 3). Free: it arrived with the queue fetch.
2. **Local `CachedPost`** within its TTL. Free.
3. **A live resolve.** Everything above exists to avoid reaching this.

### Concurrency and Caching

- **Posts are emitted progressively.** `ContentProvider.postsStream(deprioritizing:)` yields the complete best-known list repeatedly: first everything tiers 1 and 2 could answer, then an updated snapshot as each live resolve lands. Waiting for the last post before showing the first turned an unavoidable rate-limit delay into a blank screen. A cold 59-item queue now renders in about 8 seconds instead of roughly 4 minutes.
- An empty snapshot mid-hydration means "nothing resolved yet", not "empty queue". Both the provider and `GalleryViewModel` guard against showing `EmptyQueueView` in that window.
- Up to 4 concurrent metadata fetches per refresh (`AppConfig.resolverConcurrency`). Deliberately low: Reddit's budget, not parallelism, is the limit, and every request in flight is budget `RedditRateLimiter` can only estimate. A wider fan-out just blurs that estimate.
- Per-request timeout: 10 seconds. Per-post budget-wait deadline: 150 seconds (`redditResolveDeadline`).
- **Cached results stay fresh for 30 days**, minus a stable per-post jitter (`AppConfig.cacheTTL(forPostID:)`). Long on purpose: a Reddit post's title, subreddit, author, publish date, and media URL are immutable, so a short TTL just re-spends the budget re-learning facts that cannot change. The jitter exists because a queue hydrated in one burst would otherwise expire in one burst. Use `cacheTTL(forPostID:)`, never the raw `cacheTTL`, for freshness checks.
- The one thing that *can* rot is a signed preview-image URL. `PostCardRow` reports a failed image load, which calls `MetadataCache.markStale` for that single post so the next refresh re-resolves it. That is the targeted alternative to expiring the whole queue on a timer.
- If refetch fails, keep the stale cache and show a stale badge on the affected item.
- **A refresh may not finish the whole queue, and that is fine.** Work is ordered by visibility: watched posts last (they sit at the bottom of the list and are rarely opened), then never-seen posts before stale ones, since a post with no cache entry is the one currently showing as a raw-URL card. Whatever is skipped is picked up on the next refresh; nothing is lost.
- A 429 is retried up to `redditThrottleRetries` times, but each retry waits out the rate-limit window first. Never replace this with a short fixed backoff.
- `RedditRateLimiter` persists its window state to `UserDefaults`, so a cold launch mid-window inherits what the last run learned instead of rediscovering an exhausted budget by eating 429s.

### Public Endpoint Risk

Both endpoints used by v1 (Reddit's RSS/preview surface and `youtube.com/oembed`) are public and unauthenticated. If either is gated, the corresponding resolver breaks and we may need to move to the authenticated API (Phase 7 for Reddit, or a YouTube Data API key). Reddit has already gated `.json` once, so treat continued RSS access as borrowed time.

## YouTube Playback on tvOS

YouTube content cannot be played inside the app. There is no web view on tvOS, and YouTube has no embeddable player for third-party tvOS apps. Behavior:

- YouTube items render as a preview card with an "Open in YouTube" button.
- The button deep-links via `youtube://www.youtube.com/watch?v={id}` (full form with host) and falls back to the HTTPS URL if the scheme fails.
- **Deep-link gotcha, verified empirically on tvOS 26.x:** the YouTube tvOS app ignores `youtube://watch?v={id}` (iOS-style) and `youtube://{id}` (short form) — both launch the app but drop the deep-link, leaving the user on YouTube's last screen. Only the full `youtube://www.youtube.com/watch?v={id}` form actually navigates to the video. Re-test all three if Google ever updates the YouTube tvOS app and this regresses.
- A YouTube item is marked watched only when the user taps "Open in YouTube", not on a timer.

## Build Phases

Follow the implementation phases in PRD.md. Phases 1–3 (tvOS with mock data) and Phase 4 (queue integration) are done. Phase 4.5 pivoted transport to GitHub Gist (v3.1). Phase 5 is the iOS companion app + Share Extension, implemented in v3.2 — see `docs/iOS-App.md`. Phase 6 is polish.

## Commands

```bash
# Build tvOS for Simulator
xcodebuild -scheme "Upvote TV" -destination 'platform=tvOS Simulator,name=Apple TV' build

# Build iOS Mobile for Simulator
xcodebuild -scheme "Upvote TV Mobile" -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tvOS tests
xcodebuild -scheme "Upvote TV" -destination 'platform=tvOS Simulator,name=Apple TV' test
```

## Queue Transport Notes

The queue lives as a single `queue.json` file inside a secret GitHub Gist. All three targets (tvOS, iOS Mobile, iOS Share) read/write it via `api.github.com/gists/{id}` using a fine-grained Personal Access Token.

- **Schema v2** added an optional `metadata` block per item, written by the Share Extension. Every field in it is optional and the block itself is optional, so v1 files (no metadata anywhere) decode without special-casing, and malformed metadata is dropped while the item itself is kept. Losing metadata costs one resolve; losing a queue entry loses somebody's share.
- Configuration lives in `Secrets.plist` in each target's bundle (gitignored). Two keys: `GistID`, `GistToken`.
- **One canonical `Secrets.plist`** lives at `Upvote TV/Upvote TV/Secrets.plist`. The iOS Mobile and Share targets have symlinks pointing to it, so there is one file to rotate at token-renewal time.
- `SecretsLoader.shared.isConfigured` → false causes tvOS to render `ConnectionErrorView` and iOS to show an explanatory failure state in the Share Extension.
- `GistQueueClient` handles GET (fetch items) and PATCH (upsert whole file). Authenticated for both.
- No iCloud entitlement. The `Upvote TV.entitlements` file is intentionally empty. The iCloud route was tried but abandoned in v3.1 because Apple's portal doesn't grant `com.apple.developer.ubiquity-container-identifiers` to tvOS App IDs.
- Token rotation: fine-grained PATs max out at 1-year expiration. Plan for a manual yearly rotation: edit `Secrets.plist` once, all three targets pick it up.

## Layout Direction

The app uses a **single-column full-width list** (not a two-pane split layout). Each row is a soft card with:

- Colored SF Symbol type icon on the left (in a rounded square container)
- Title and metadata in the center
- Optional thumbnail on the right (only for visual post types)
- Watched/unwatched indicator on the far right

Selecting any post opens it full-screen. There is no side preview panel.

### SF Symbol Type Icons

- Video: `play.rectangle.fill` (red tint)
- Image: `photo` (blue tint)
- Gallery: `square.stack` (purple tint)
- Text: `doc.text` (green tint)
- YouTube: `play.rectangle.fill` (red tint)
- Link: `arrow.up.right` (amber tint)

## Style Guidelines

- Dark theme first
- Generous whitespace, large readable typography
- No Reddit branding, logos, or colors
- Use tvOS native focus engine, not custom navigation
- Prefer system SF Symbols for icons
- Keep UI minimal and calm
- Card rows have subtle background fill and border, brighten on focus
- Title is the dominant element in every row, must be readable from 6-10 feet

## Context Menu Actions (Long Press)

- Mark as Watched / Mark as Unwatched
- Remove from Queue (rewrites queue.json and drops CachedPost)
## Oracle Reporting Contract

This project is tracked by Oracle, a portfolio agent at the `_Projects` root that rolls up all project statuses into `_Projects/_Oracle/PORTFOLIO.md`. Parent standards and the Oracle Status Format are defined in `_Projects/CLAUDE.md` (inherited; read it). Your obligations:

1. Keep `STATUS.md` at this project's root current. At the end of any session with meaningful progress, decisions, or new blockers, refresh it before finishing.
2. Follow the Oracle Status Format defined in `_Projects/CLAUDE.md` exactly. Update the front matter `modified` date and bump `version` on every edit.
3. Keep the Ideas Shelf stocked: 2 to 5 self-contained backlog items sized S / M / L that Justin could pick up for fun.
4. Never delete `STATUS.md`. If parking the project, set Stage to Paused and note why.
5. Oracle trusts `STATUS.md` completely. It does not inspect code or git. An inaccurate status means Justin gets a wrong portfolio picture.
6. Edits to `STATUS.md` marked "updated via Oracle at Justin's direction" are legitimate and authoritative: Justin dictated them at the portfolio level. Reconcile them with the backlog at session start; do not revert them.
7. Share what you learn. When this project discovers a reusable technique, fix, or better workflow that other projects could benefit from (environment-level, not project-specific design), record it briefly in an optional `## Lessons` section at the bottom of `STATUS.md`, below the divider. Oracle reviews these every run and promotes vetted ones into the shared Project Build Guide. The master guide at `_Projects/_Templates/Project Build Guide.md` is authoritative; if this folder contains its own older copy, prefer the master and its Changelog.
