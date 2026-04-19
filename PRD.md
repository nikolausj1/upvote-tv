---
title: "PRD: Upvote TV - Personal tvOS Shared Queue Viewer"
created: 2026-04-10
modified: 2026-04-17
version: 3.2
author: Claude Opus 4.7 (claude-opus-4-7)
tags:
---

# PRD: Upvote TV

A personal Apple TV app that turns curated iPhone-shared content into a TV viewing queue for two people.

---

## Revision Notes

**v3.2 (2026-04-18):** Capture mechanism swapped from an iOS Shortcut to a native iOS companion app with a Share Extension. The Shortcut approach turned out to be fragile to debug (misleading error states, UI-only configuration, no real step-through inspection) and slow to iterate on. A proper iOS app reuses the same Swift queue-client code as tvOS, is under version control, and provides native auth+lifecycle handling. GitHub Gist remains the transport.

**v3.1 (2026-04-17):** Queue transport swapped from iCloud Drive to a GitHub Gist. Apple's developer portal does not grant `com.apple.developer.ubiquity-container-identifiers` to tvOS App IDs (verified via both automatic and manual provisioning profile generation), which made file-based iCloud Documents unusable on a real Apple TV. The rest of the v3 architecture (mock/queue/Reddit-API provider abstraction, on-the-fly metadata resolution) is unchanged — only the file-transport layer moved.

**v3.0 (initial v3):** Strategic shift away from Reddit API integration as the primary data source. Reddit's Responsible Builder Policy (rolled out late 2025) now gates all API access behind a manual approval process with unpredictable wait times. Rather than block the project on an external approval queue, v1 pivots to a share-sheet-driven queue model that requires no Reddit authentication and adds YouTube support from day one. Reddit API integration is preserved as a future optional provider (Phase 7) if approval is eventually granted.

---

## Problem Statement

Justin and his wife collect content throughout the day (from Reddit, YouTube, and similar) that they want to watch together on the TV later. Apple TV's only native "queue" mechanisms are platform-specific (YouTube Watch Later, Apple TV+ Up Next, etc.) and don't combine sources or allow a shared household queue. Reddit's tvOS app is discontinued, and browsing via AirPlay or screen mirroring kills the "lean back" TV experience.

The original v2 plan used Reddit upvotes as the implicit curation signal and fetched them via the Reddit API. With Reddit's 2025 Responsible Builder Policy restricting API access, v3 replaces that with a more flexible explicit-curation model: anything shared from an iPhone via the share sheet lands in a shared queue (a GitHub Gist, after the v3.1 pivot) that appears on the Apple TV.

The app should feel like a personal content feed on the living room TV, not like a developer tool.

## Target Users

Justin and his wife. This is a personal-use app, not intended for public distribution. It will be installed through Xcode's developer workflow, not the App Store.

## Goals

1. Capture content from any iPhone in the household via the share sheet into a shared queue.
2. Store the queue as a JSON file in iCloud Drive, accessible to the Apple TV.
3. Display the queue on Apple TV in a polished, minimal interface.
4. Support Reddit and YouTube as primary content sources in v1.
5. Resolve post metadata (titles, thumbnails, media URLs) on the TV side from public endpoints that require no authentication.
6. Track watched state locally on the Apple TV.
7. Keep the architecture flexible so Reddit API can be added later as a supplemental provider if access is approved.

## Non-Goals (v1)

These are explicitly out of scope for v1:

- **Native companion iPhone app.** Capture is handled entirely by an iOS Shortcut, not a custom app or Share Extension.
- **CloudKit.** Queue storage is a plain JSON file in iCloud Drive. No CloudKit container, no custom schemas.
- **Direct Reddit authentication.** No OAuth, no refresh tokens, no Secrets.plist tokens.
- **Cloud-synced watched state.** Watched state is local to each Apple TV.
- **Arbitrary URL support.** The Shortcut rejects any domain outside the Reddit / YouTube whitelist in v1.
- **Browsing Reddit or YouTube broadly.** No subreddits, home feed, search, or channel browsing. The only content is what's in the queue.
- **Social features.** No comments, voting, saving, account management.
- **Server components.** No backend, no proxy, no cloud function.
- **Offline media caching.** Metadata and watched state persist locally. Media loads on demand.
- **Settings screen in-app.** The only user preference (NSFW toggle) lives in tvOS system Settings via Settings.bundle.
- **Manual refresh in-app.** The app refreshes automatically on launch.
- **Post-to-post navigation in detail view.** User always returns to the queue list to pick the next item.

---

## Architecture Overview

### System Diagram

```
+----------------------------+    +----------------------------+
|  iPhone (Justin)           |    |  iPhone (Wife)             |
|                            |    |                            |
|  Safari / Reddit / YT app  |    |  Safari / Reddit / YT app  |
|          |                 |    |          |                 |
|          v  Share Sheet    |    |          v  Share Sheet    |
|  +-----------------------+ |    |  +-----------------------+ |
|  | Upvote TV Share Ext.  | |    |  | Upvote TV Share Ext.  | |
|  | (iOS Share Extension) | |    |  | (iOS Share Extension) | |
|  +----------|------------+ |    |  +----------|------------+ |
+-------------|--------------+    +-------------|--------------+
              |                                 |
              +----------------+----------------+
                               |
                               v  (HTTPS GET+PATCH with PAT)
                    +-------------------------+
                    |  GitHub Gist             |
                    |  queue.json              |
                    +-------------------------+
                               |
                               v  (HTTPS GET with PAT)
                    +-------------------------+
                    |  Apple TV App            |
                    |  reads queue.json        |
                    |  resolves metadata from: |
                    |  - reddit.com/.json      |
                    |  - youtube.com/oembed    |
                    |  caches to SwiftData     |
                    +-------------------------+
```

### ContentProvider Architecture

The UI depends on a `ContentProvider` protocol. Three implementations live in the codebase:

1. **MockContentProvider** (dev and SwiftUI previews). Returns a hand-crafted set of sample posts covering all supported types. Used during Phases 1-3 before any queue integration.

2. **QueueContentProvider** (v1 primary). Reads `queue.json` from a secret GitHub Gist, hydrates each queue item into a full `Post` by calling the appropriate metadata resolver, caches results in SwiftData.

3. **RedditContentProvider** (reserved for Phase 7). Implemented only if Reddit API access is eventually approved. Would fetch 100 most recent upvoted posts directly. Could be used as a supplement to or replacement for `QueueContentProvider`.

### Layer Responsibilities

**UI Layer (SwiftUI):** All screens, focus handling, visual presentation. Consumes the `ContentProvider` protocol. Never talks to Reddit, YouTube, or GitHub directly.

**Content Provider Layer:** Normalizes external data into app-level `Post` models.

**Metadata Resolvers:** Per-source services that take a `QueueItem` (id, url, source) and return a hydrated `Post`. Two resolvers in v1: `RedditMetadataResolver` (uses `reddit.com/comments/{id}.json`) and `YouTubeMetadataResolver` (uses YouTube oEmbed). Both unauthenticated.

**Gist Queue Client:** HTTP client wrapping `api.github.com/gists/{id}`. `fetch()` retrieves the queue JSON; `upsert(items:)` PATCHes the gist with a full replacement. Both authenticated with a fine-grained Personal Access Token. Used by `QueueContentProvider` for reads, and by the context-menu "Remove from Queue" action for writes.

**Persistence (SwiftData):** Stores cached `Post` snapshots, watched state, and metadata-cache freshness timestamps.

**Media Loading:** AVKit for video, URLSession for images. Unchanged from v2.

### Why This Matters

The queue model inverts the original data-flow assumption. Instead of authenticating to a Reddit API and pulling down a user's history, the app receives an already-curated queue written by a Share Extension on iPhone. This has three advantages:

1. **No OAuth dance.** A single long-lived fine-grained Personal Access Token on the GitHub side — no refresh chain, no approval queue. (Token rotation is yearly, on a user-predictable schedule.)
2. **Multi-source from day one.** The same queue mechanism works for Reddit, YouTube, and any future source we decide to whitelist.
3. **Shared curation.** Any iPhone in the household with the Upvote TV iOS app installed contributes to the same queue. The living room TV becomes a shared household surface.

---

## Prerequisites (Before Writing Any Code)

### 1. Apple Developer Account

Sign up at developer.apple.com. A free account works for personal development, but a paid account ($99/year) is needed to install apps on a physical Apple TV.

### 2. Xcode Installation

Install Xcode from the Mac App Store. Ensure tvOS SDK and Simulator are included.

### 3. GitHub Gist Setup

- Create a secret Gist at gist.github.com containing a file named `queue.json` seeded with `{"version":1,"items":[]}`.
- Copy the gist's ID (the hex segment at the end of its URL). It's used by both the Apple TV app and the iPhone Shortcut.
- See `docs/Gist-Setup.md` for step-by-step screenshots.

### 4. Personal Access Token

- At github.com/settings/personal-access-tokens/new, generate a **fine-grained** PAT scoped to **Gists: read + write** only. 1-year expiration is the max GitHub allows.
- The token is embedded in a single `Secrets.plist` (gitignored) that is symlinked into all three app targets (tvOS, iOS app, iOS Share Extension).
- Token rotation is a manual yearly task.

### 5. Xcode Configuration

No iCloud capability needed on any target. The tvOS entitlements file is empty. Xcode auto-signing with a paid Apple Developer Program account handles iOS + tvOS app provisioning.

### 6. iOS Companion App Installation

The iOS app lives as two Xcode targets (`Upvote TV Mobile` and `Upvote TV Share`). For the household maintainer, install via Xcode → Run on the paired iPhone. For other family members, distribute via TestFlight internal testers (free, no App Store review required for up to 100 testers on your team). See `docs/iOS-App.md` for details.

---

## Capture Mechanism (iOS Companion App + Share Extension)

### Overview

The iOS app `Upvote TV Mobile` ships with a Share Extension target `Upvote TV Share`. The extension registers with iOS's share sheet for URL content types, meaning it appears whenever the user shares a URL from Safari, Reddit, YouTube, or any other app. When invoked, it classifies the URL via `URLClassifier`, appends a `QueueItem` to the shared GitHub Gist via `GistQueueClient`, and auto-dismisses on success.

The Mobile app itself is a thin container: a single screen explaining the share-sheet workflow and a "Test Connection" button that verifies the PAT still works against the Gist. All real work lives in the extension.

### Input

The Share Extension is activated when the user shares a single URL from any iOS app. `Info.plist` declares `NSExtensionActivationSupportsWebURLWithMaxCount = 1` — iOS will only show the extension for URL content and with exactly one URL.

### Validation and Normalization

**Reddit domains:**
- `reddit.com`, `www.reddit.com`, `old.reddit.com`, `new.reddit.com`, `np.reddit.com`: all normalize host to `www.reddit.com`.
- `redd.it/{id}`: rewrite to `https://www.reddit.com/comments/{id}`.
- `i.redd.it/*`, `v.redd.it/*`: reject. These are media hosts, not post URLs.
- Post URL path structure: `/r/{sub}/comments/{id}/{slug}/...`. The ID is the only segment needed.

**YouTube domains:**
- `youtube.com/watch?v={id}`: extract the `v` query parameter.
- `youtu.be/{id}`: extract the path segment.
- `youtube.com/shorts/{id}`: extract the path segment.
- `m.youtube.com`, `music.youtube.com`: normalize host to `www.youtube.com`.

**All other domains:** reject with a user-facing toast ("Only Reddit and YouTube are supported in Upvote TV").

### Behavior Sequence

1. User taps Share → Upvote TV in any iOS app; iOS passes the URL into the extension.
2. `URLClassifier.classify(url)` extracts the post/video ID and `QueueSource`. If the URL is neither Reddit nor YouTube, show "Only Reddit posts and YouTube videos can be added" and stop.
3. `GistQueueClient.fetch()` GETs the current queue from the gist.
4. Deduplicate — if an item with matching `id + source` already exists, show "Already Queued" and auto-dismiss.
5. Prepend the new `QueueItem` (newest `sharedAt` first) and `GistQueueClient.upsert()` PATCHes the gist atomically.
6. Show the green check "Added" state and auto-dismiss after ~1.2 seconds.

### Error Handling (surface-level, shared with the tvOS app's `GistQueueClient.ClientError`)

- `configurationMissing`: "Secrets.plist is missing GistID or GistToken."
- `unauthorized`: "Token rejected. It may have expired."
- `notFound`: "Gist not found. Check the Gist ID."
- `rateLimited`: "GitHub is throttling. Try again in a minute."
- `network`: "Network error. Check your internet connection."
- Any unhandled: "Couldn't reach the queue."

### Race Conditions (Known Limitation)

If both phones trigger the Share Extension within the same second, both GET the same gist state, both prepend their item, both PATCH. Last writer wins and one share is silently lost. This is acknowledged as rare (requires near-simultaneous taps on both devices within the PATCH round-trip) and acceptable for v1. A proper fix would require optimistic concurrency via gist ETag / If-Match, which is a v2+ consideration.

---

## Queue File Specification

### Path

A single file named `queue.json` inside a secret GitHub Gist owned by the household maintainer. The gist ID is stable and shared across all clients (iPhones running the Shortcut, the Apple TV). Accessed via:

- Read: `GET https://api.github.com/gists/{gist_id}`
- Write: `PATCH https://api.github.com/gists/{gist_id}` with `{"files":{"queue.json":{"content":"<full JSON string>"}}}`

Both require `Authorization: Bearer <fine-grained PAT>`.

### Schema

```json
{
  "version": 1,
  "items": [
    {
      "id": "1abc2de",
      "url": "https://www.reddit.com/r/videos/comments/1abc2de/",
      "source": "reddit",
      "sharedAt": "2026-04-17T14:23:00Z"
    },
    {
      "id": "dQw4w9WgXcQ",
      "url": "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      "source": "youtube",
      "sharedAt": "2026-04-17T14:30:00Z"
    }
  ]
}
```

### Field Definitions

- `version`: integer. Schema version. v1 is `1`. Used for future migrations.
- `items`: array, ordered newest-first by `sharedAt`.
- `items[].id`: Reddit post ID (short form, e.g., `1abc2de`, no `t3_` prefix) or YouTube video ID.
- `items[].url`: canonical URL. For Reddit, `https://www.reddit.com/comments/{id}` is the minimal form. For YouTube, `https://www.youtube.com/watch?v={id}`.
- `items[].source`: either `reddit` or `youtube`.
- `items[].sharedAt`: ISO8601 UTC timestamp when the Shortcut added the item.

### Deliberately Absent Fields

- No `title`, `thumbnail`, or other metadata. These are resolved by the tvOS app on the fly. Keeping the Shortcut minimal avoids brittle metadata extraction in Shortcuts and keeps the file small.
- No `watched` state. Watched state lives in SwiftData on the Apple TV.

### File Growth

No automatic size limit in v1. Items persist in the queue forever unless explicitly removed via the tvOS "Remove from Queue" action. In practice, the list will grow over time. If it becomes a problem (dozens of MB, slow loads), future versions can introduce a "clear items older than N days" behavior.

---

## Metadata Resolution (tvOS Side)

When the app launches, it reads the queue and hydrates each item into a full `Post` model. Hydration happens in parallel and respects a 24-hour cache.

### Reddit Resolver

- Endpoint: `https://www.reddit.com/comments/{id}.json`
- Unauthenticated. Standard public web endpoint used by reddit.com for SEO and old.reddit.com.
- Response: Reddit's standard post listing JSON (same structure as the API, just served from the web host instead of `oauth.reddit.com`).
- Parse using the normalizer logic originally planned for `RedditContentProvider`.
- Handle the same post-type variations as v2:
  - **Video (v.redd.it):** extract `media.reddit_video.hls_url` for AVKit playback. Fallback to `fallback_url` (video-only) with a flag that audio may be missing.
  - **Image:** use `preview.images[0].resolutions` closest to 1920px wide.
  - **Gallery:** combine `gallery_data.items` (ordering) with `media_metadata` (URLs, HTML-decoded).
  - **Text (selftext):** use the `selftext` field.
  - **YouTube link (Reddit post linking to YouTube):** detect domain, classify as `PostType.youtube`, extract video ID from `url_overridden_by_dest`.
  - **Link (other external):** use `url_overridden_by_dest` and `domain`.

### YouTube Resolver

- Endpoint: `https://www.youtube.com/oembed?url={videoUrl}&format=json`
- Unauthenticated. Public oEmbed endpoint.
- Response fields: `title`, `author_name`, `thumbnail_url`, `thumbnail_width`, `thumbnail_height`.
- oEmbed does not return video duration. Display without duration or fetch separately if a future enhancement adds this.
- Every YouTube queue item classifies as `PostType.youtube`, regardless of whether it's a full YouTube video, Short, or Live.

### Caching

- Successful resolutions cached in SwiftData with a `resolvedAt` timestamp.
- On next launch, items with `resolvedAt` less than 24 hours old are used directly without refetching.
- Items with stale or missing cache are refetched in the background while the list renders with cached data.
- If a refetch fails, the cached data is still shown, with a small "Last updated N hours ago" badge on that item.

### Concurrency

- Up to 10 concurrent resolution requests.
- Per-request timeout: 10 seconds.
- An item that fails resolution (404, network error, parse error) still appears in the list but renders as a minimal fallback card ("Unable to load," with the raw URL visible).

### Public JSON Endpoint Risk

The Reddit `/comments/{id}.json` endpoint is currently public and unauthenticated. The Responsible Builder Policy primarily governs the OAuth API at `oauth.reddit.com`, not the web host. This is the assumption v1 is built on. If Reddit gates the web JSON endpoint in the future, the Reddit resolver would need to fall back to HTML parsing or be replaced with `RedditContentProvider`. Worth monitoring.

---

## Data Models

### QueueItem (new, internal representation of a queue.json entry)

```
QueueItem {
    id: String              // Reddit post ID or YouTube video ID
    url: String             // Canonical URL from the Shortcut
    source: QueueSource     // .reddit or .youtube
    sharedAt: Date          // When the Shortcut added this
}
```

### QueueSource (new enum)

```
QueueSource {
    case reddit
    case youtube
}
```

### Post (updated)

Mostly unchanged from v2, with one new optional field to preserve the queue's shared-at timestamp for sort order:

```
Post {
    id: String
    title: String
    subreddit: String?              // Reddit-only, nil for YouTube items
    author: String?                 // Reddit author or YouTube author_name
    createdAt: Date                 // Reddit post creation time or YouTube upload date if available
    sharedAt: Date?                 // From QueueItem; nil for non-queue sources like future RedditContentProvider
    postType: PostType
    
    thumbnailURL: URL?
    previewImageURL: URL?
    mediaURL: URL?
    galleryItems: [GalleryItem]?
    textBody: String?
    outboundURL: URL?
    domain: String?
    
    isNSFW: Bool
    score: Int?
}
```

### PostType (unchanged)

```
PostType {
    case video
    case image
    case text
    case gallery
    case youtube
    case link
    case unsupported
}
```

### GalleryItem (unchanged)

### WatchedState (unchanged, SwiftData)

### CachedPost (updated, SwiftData)

Mirror of `Post`, with `resolvedAt: Date` added for cache-freshness tracking.

### ~~AuthState~~ (removed)

v2's `AuthState` model is gone. No auth to persist in v1.

---

## Screen-by-Screen Requirements

Screens largely unchanged from v2, with a few updates described below.

### Screen A: Browse List (Main Screen)

Unchanged layout and row design. One addition to the context menu:

**Context Menu (Long Press on any row):**
- Mark as Watched / Mark as Unwatched (toggles based on current state).
- **Remove from Queue** (new in v3). Immediately removes the item from the queue, updates the UI, rewrites `queue.json`, and drops the cached post from SwiftData.

No confirmation dialog for Remove. Re-adding is trivial via the Shortcut, and confirmation friction hurts the remote-control UX.

### Screen A-1: "You're Caught Up" State (unchanged)

### Screen A-2: Empty Queue State (new in v3)

Shown when `queue.json` does not exist or has zero items.

- Heading: "Nothing in your queue yet"
- Subheading: "Share a Reddit post or YouTube video from your iPhone to add it here."
- Brief instruction: "Make sure you've installed the Upvote TV Shortcut on your iPhone."
- The screen polls for the queue file every 10 seconds while visible, so a fresh share from iPhone appears without needing to relaunch.
- No navigation controls. Back button exits the app.

### Screen B: Video Detail View (unchanged)

### Screen C: Image Detail View (unchanged)

### Screen D: Text Detail View (unchanged)

### Screen E: Gallery Detail View (unchanged)

### Screen F-1: YouTube Detail View (unchanged in behavior)

Now also used for YouTube items that came directly from the queue, not just YouTube-domain Reddit posts. Same preview card and "Open in YouTube" button. Same deep-link behavior (`youtube://watch?v={id}` with HTTPS fallback).

### Screen F-2: Link / Fallback Detail View (unchanged)

### Screen G: Media Error State (unchanged)

### Screen H: Loading State (unchanged)

### Screen I: Connection Error State

Shown when the queue can't be loaded — `Secrets.plist` is missing, the gist endpoint is unreachable, the token is invalid, or GitHub is rate-limiting.

- Heading varies by error:
  - `configurationMissing`: "Setup Required"
  - `rateLimited`: "Too Many Requests"
  - Otherwise: "Can't Reach Your Queue"
- Body explains the cause and next action (for config errors, points at `docs/Gist-Setup.md`; for network errors, advises a connection check).
- Debug builds additionally show the gist ID, whether a token is present, and the underlying error code.

### Screen J: Stale Data Banner (unchanged in concept, updated in scope)

Shown when one or more queue items have stale cached metadata because their refresh attempt failed. Per-item badge rather than a global banner.

---

## Watched State Rules

Unchanged from v2. Restated for completeness:

| Post Type | When Marked Watched |
|-----------|-------------------|
| Video | Playback reaches 50% of duration |
| Image | After 2 seconds in detail view |
| Text | After 2 seconds in detail view |
| Gallery | After 2 seconds open OR any interaction within |
| YouTube | When user taps "Open in YouTube" (not on card view) |
| Link / Fallback | After 2 seconds in detail view |
| Media Error | Never marked watched |

Visual treatment (unwatched vs. watched) unchanged.

---

## Queue Removal Flow

**Trigger:** Long-press on a list row, select "Remove from Queue."

**Behavior:**
1. Item removed from in-memory `posts` array. UI updates immediately (animated fade-out).
2. `queue.json` is re-read from iCloud, item stripped by matching `id` + `source`, written back atomically.
3. Cached `Post` snapshot removed from SwiftData.
4. No undo in v1.

**Concurrency note:** Between the read and write of `queue.json`, another device could write. This is the same race condition as the Shortcut writes. Accepted risk.

---

## NSFW Handling

- Controlled via Settings.bundle (tvOS system Settings > Apps > Upvote TV).
- Default on first launch: NSFW enabled.
- Filtering applies to Reddit items only (uses `over_18` from Reddit metadata). YouTube oEmbed does not expose an NSFW flag, so YouTube items are never filtered.
- When NSFW is disabled, matching items are hidden from the queue and detail flow.

---

## Startup and Refresh Behavior

1. App launch shows the shell immediately with skeleton rows.
2. Fetch `queue.json` from the GitHub Gist via `GistQueueClient.fetch()`.
3. For each queue item, check for a cached `Post` with `resolvedAt` < 24 hours. Use cache if available.
4. Render list immediately with whatever cached data is available. Items without cache render as skeleton placeholders.
5. In the background, fetch fresh metadata for all items with stale or missing cache, up to 10 concurrent requests.
6. As each fetch completes, update the corresponding row in place.
7. If fetch fails, keep any existing cached data and add a stale badge.
8. If the gist responds but contains no items, show the Empty Queue state and re-fetch every 10 seconds.
9. If `Secrets.plist` is missing/empty or the gist endpoint returns 401/403/404/network-error, show the Connection Error state.

No manual refresh in v1.

---

## Visual Design Direction (unchanged)

---

## tvOS-Specific Technical Notes

**iCloud Container Access:** tvOS accesses iCloud through the app's ubiquity container, addressed via `NSFileManager.default.url(forUbiquityContainerIdentifier:)`. The document picker is not available on tvOS, so all file access is programmatic. The Shortcut on iPhone writes to the same container.

**Memory:** Unchanged from v2. Prefer preview-resolution images over full-resolution originals.

**Focus Engine:** Unchanged from v2.

**AVKit:** Unchanged from v2. HLS URLs from Reddit v.redd.it work natively.

**Settings.bundle:** Unchanged from v2.

**Network:** All network access is unauthenticated. No OAuth tokens, no headers beyond standard User-Agent.

---

## Performance Expectations

- App shell visible within 1 second of launch.
- Cached items render within 500ms of shell appearance.
- Uncached items render within 3 seconds (allowing for network fetch).
- iCloud sync latency from iPhone share to Apple TV visibility: typically 5-30 seconds, depending on network and iCloud conditions. Not under the app's control.
- Focus movement between list items feels instant.
- Video playback starts within 2-3 seconds of selection.
- Watched state persists immediately.

---

## Acceptance Criteria

The MVP is complete when all of the following are true:

1. App launches into a polished full-width soft card list with skeleton loading state.
2. App reads `queue.json` from the iCloud ubiquity container.
3. For each queue item, the app resolves metadata from `reddit.com/comments/{id}.json` or `youtube.com/oembed`.
4. Resolved metadata is cached in SwiftData with a 24-hour freshness window.
5. List sorts unwatched first, watched below, newest-by-sharedAt first within each group.
6. Default focus goes to the top item, or the "You're Caught Up" row if all items are watched.
7. Each card row shows a colored type icon, title, metadata, optional thumbnail, and watched indicator.
8. Selecting a row opens a full-screen detail view appropriate to the post type.
9. YouTube items (both queue-added and Reddit-linked) show a preview card with an "Open in YouTube" button.
10. Video posts autoplay with audio, show Replay at end, mark watched at 85% playback.
11. Image posts display full-screen with no overlay, mark watched after 2 seconds.
12. Text posts show scrollable title plus body, mark watched after 2 seconds.
13. Gallery posts support in-post image navigation with a position indicator.
14. Link and unsupported posts show a polished fallback information card.
15. Back / Menu always returns to the queue list at the same scroll position and focused row.
16. Watched state persists across app launches.
17. Long-press on a list row shows context menu with Mark Watched/Unwatched and Remove from Queue options.
18. Remove from Queue rewrites `queue.json` atomically and updates UI immediately.
19. Items with failed metadata refresh display a stale badge but remain usable with cached data.
20. Missing queue file shows the Empty Queue state and polls for the file every 10 seconds.
21. iCloud container inaccessible shows the Setup Required state.
22. Per-post media load failures show the Media Error state.
23. NSFW visibility is controlled through tvOS system Settings and applies only to Reddit items.
24. Debug builds expose metadata resolution diagnostics without affecting normal UX.
25. MockContentProvider works fully, enabling development without iCloud setup.
26. The iOS Shortcut validates domain whitelist, deduplicates by id+source, writes `queue.json` atomically, and shows user feedback on success and failure.
27. Two iPhones with the Shortcut installed can contribute to the same queue.
28. App feels minimal, premium, and Apple TV native.

---

## Implementation Phases

### Phase 1: Project Setup and Mock Data

- Create tvOS Xcode project with SwiftUI.
- Define all data models: Post, PostType, GalleryItem, WatchedState, CachedPost, QueueItem, QueueSource.
- Build MockContentProvider with realistic sample data covering video, image, gallery, text, YouTube (both direct and Reddit-linked), and link types.
- Set up SwiftData persistence for watched state and cached posts.
- Create Settings.bundle for NSFW toggle.
- Add `.gitignore` excluding any local config files.

### Phase 2: Browse Screen with Mock Data

- Build the single-column soft-card list layout.
- Implement focus handling and default-focus logic.
- Implement sort logic (unwatched first, newest-by-sharedAt first within each group).
- Implement watched/unwatched visual treatment.
- Build the "You're Caught Up" synthetic row.
- Build the Empty Queue state.
- Build the skeleton loading state.
- Build the long-press context menu including Remove from Queue (operating on mock data for now).

### Phase 3: Detail Views with Mock Data

- Video detail view with AVKit (use a sample HLS stream).
- Image detail view.
- Text detail view.
- Gallery detail view with in-post navigation.
- YouTube detail view with Open in YouTube deep link.
- Link / fallback detail view.
- Media error state.
- Watched-state auto-marking logic for each type.
- Back navigation preserving list position.

### Phase 4: Queue Integration

- Configure iCloud capability and ubiquity container in Xcode.
- Build QueueFileReader and QueueFileWriter for `queue.json`.
- Build RedditMetadataResolver using `reddit.com/comments/{id}.json`.
- Build YouTubeMetadataResolver using `youtube.com/oembed`.
- Build MetadataCache in SwiftData with 24-hour freshness.
- Build QueueContentProvider that orchestrates queue read + per-item resolution + caching.
- Wire QueueContentProvider to UI.
- Build the Setup Required state.
- Build the stale-metadata badge.
- Build refresh-on-launch flow.
- Test Reddit post-type variations (video, image, gallery, text, YouTube-linked, link).

### Phase 5: iOS Shortcut

- Build the Shortcut using iOS Shortcuts app.
- Implement domain whitelist and normalization.
- Implement JSON read, insert with dedup, atomic write.
- Implement user-facing success and error toasts.
- Distribute via iCloud share link (or export as `.shortcut` file).
- Install on both phones, verify shared queue behavior.

### Phase 6: Polish and Edge Cases

- NSFW filtering tied to Settings.bundle toggle.
- Debug diagnostic overlay for metadata resolution in dev builds.
- Performance tuning (image sizing, concurrent fetch limits, cache eviction).
- Visual polish pass (typography, spacing, focus animations).
- Verify all error states and fallback paths.
- Test two-phone contribution scenario.

### Phase 7: Reddit API Provider (Optional, Deferred)

If Reddit API access is approved under the Responsible Builder Policy:

- Build AuthService with token rotation and persistence.
- Build RedditAPIClient for the `/user/{username}/upvoted` endpoint.
- Implement RedditContentProvider.
- Decide: replace QueueContentProvider, run alongside it as a supplement, or keep both and expose a settings toggle.
- Generate OAuth setup helper script.

This phase is not required for v1 and has no fixed timeline. If Reddit never approves access, v1 is still complete and usable.

---

## Open Questions

| Question | Owner | Blocking? |
|----------|-------|-----------|
| Will the tvOS app reliably see files written by a Shortcut on iPhone within seconds, or are there delays where the user sees an empty queue even after sharing? | Engineering (test Phase 4/5) | Yes |
| Does `reddit.com/comments/{id}.json` remain reliably public in 2026, or has the Responsible Builder Policy creep affected web endpoints? | Engineering (test early in Phase 4) | Possibly |
| Does YouTube oEmbed work for all variants (standard videos, Shorts, age-restricted, live)? | Engineering (test Phase 4) | No |
| How should Settings.bundle-disabled NSFW interact with YouTube items that don't have an NSFW flag? Keep them visible (current plan) or hide YouTube entirely when NSFW is off? | Product (Justin) | No |
| Should the queue auto-prune items older than N days or watched more than N days ago, or grow forever until manually removed? | Product (Justin) | No |
| If both phones write the queue at the same moment, is the rare dropped-share acceptable, or does it justify building a Share Extension earlier? | Product (Justin) | No |

---

## Future Considerations (v2+)

Intentionally deferred but worth designing around:

- **Native iPhone Share Extension.** Replaces the Shortcut with a proper app if the Shortcut proves too slow or unreliable. Unlocks richer feedback UI and eliminates the multi-phone race condition.
- **CloudKit migration.** If iCloud Drive JSON becomes insufficient (multi-user conflicts, atomicity, schema evolution), migrate to CloudKit.
- **Reddit API as supplemental source.** Per Phase 7 above.
- **Additional source support.** Twitter/X video, Instagram Reels, TikTok, Bluesky, etc. Each requires its own metadata resolver and domain whitelist entry.
- **Watched-state sync.** CloudKit-backed watched state, so a post watched in the living room is also marked watched in the bedroom Apple TV.
- **Search or filter within queue.**
- **Manual refresh gesture.**
- **Autoplay / playlist mode for videos.**
- **Per-person queues** (one queue for Justin, one for wife, one shared).
- **Scheduled automation.** A companion scheduled task that auto-curates certain sources (e.g., weekly top of a subreddit) into the queue.
