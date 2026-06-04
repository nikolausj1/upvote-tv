---
title: "Upvote TV - Project Instructions"
created: 2026-04-10
modified: 2026-04-17
version: 3.0
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
│   ├── QueueItem.swift             # Queue entry model
│   ├── QueueSource.swift           # .reddit | .youtube
│   ├── GistQueueClient.swift       # HTTP GET/PATCH against api.github.com/gists/{id}
│   ├── SecretsLoader.swift         # Reads Gist ID + PAT from Secrets.plist
│   └── URLClassifier.swift         # URL → (id, source) extraction for both platforms
│
├── Upvote TV/                      # tvOS app target (the player)
│   ├── Models/                     # Post, PostType, GalleryItem, WatchedState, CachedPost
│   ├── Providers/                  # ContentProvider, Mock, QueueContentProvider
│   ├── Services/                   # RedditMetadataResolver, YouTubeMetadataResolver, MetadataCache, WatchedStateManager
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
3. **The Share Extension writes the minimum possible fields.** Only `id`, `url`, `source`, and `sharedAt`. Titles, thumbnails, and media URLs are resolved on the tvOS side, not written by the extension.
4. **Gist writes are whole-file PATCHes.** GitHub handles atomic replacement. Don't emulate partial updates.
5. **Graceful degradation over filtering.** Show posts even when their metadata can't fully resolve. Items with failed resolution render as a fallback card with the raw URL, not hidden.
6. **Cached content is the safety net.** If metadata refresh fails, the app must still work with cached data. A stale badge is shown per affected item.
7. **Race conditions between devices are accepted in v1.** If two iPhones PATCH the gist within the same round-trip window, the last writer wins and one share may be silently lost. Rare; not fixed in v1. Documented in PRD.
8. **Secrets stay out of git.** `Secrets.plist` is gitignored; `Secrets.example.plist` is the committed template. iOS targets symlink to the tvOS copy so there's one file, one token.
9. **`Shared/` is the only place cross-target Swift code lives.** Don't duplicate `QueueItem`, `GistQueueClient`, etc. into individual target folders. Drop new cross-platform files into `Shared/` and they're automatically compiled into all three targets.

## Metadata Resolution Notes

### Reddit Posts (OpenGraph preview workaround — current)

**The public `.json` endpoint is dead.** As of ~June 2026 Reddit gated `reddit.com/comments/{id}.json` behind the Responsible Builder Policy — every request returns a "blocked due to a network policy" page regardless of User-Agent. The authenticated OAuth API needs Data API approval (applied, **denied** for "lacks necessary details"; not reapplied yet).

**Current resolver** (`RedditMetadataResolver`) fetches the post's **HTML page** with a crawler-style User-Agent (`AppConfig.redditPreviewUserAgent`) and parses OpenGraph tags — the same link-preview surface iMessage/Slack/Discord use. Reddit substring-matches the `facebookexternalhit` token in the UA and serves a lightweight preview page (otherwise it returns a bot-verification wall).

- **What we get:** post title + subreddit (from the page `<title>`, format `"{title} : r/{sub}"`), a thumbnail (`og:image` → `share.redd.it/preview/post/{id}`), and the canonical URL (`og:url`).
- **Everything resolves as `PostType.link`** (a preview card). tvOS has no browser or Reddit app to open posts in, so richer types add no value on this path.
- **Lost vs. the old JSON path** (restore if/when OAuth is approved): in-app `v.redd.it` HLS video playback, gallery arrays, score, author, and the `over_18` flag — so **NSFW filtering does not apply to Reddit items** on this path.
- `PostCardRow` shows a thumbnail for any post carrying a preview image, not just inherently-visual types, so these `.link` cards render their `og:image`.

**If Reddit Data API access is approved (PRD Phase 7):** write a JSON/OAuth resolver against `oauth.reddit.com` producing the same `normalize → Post` shape. The notes below describe that richer JSON structure.

- **v.redd.it videos:** Audio and video are separate DASH streams. Use the `hls_url` field from `media.reddit_video` for AVKit playback. The `fallback_url` is video-only (no audio).
- **Gallery posts:** Image data is split across `gallery_data.items` (ordering) and `media_metadata` (URLs). URLs in `media_metadata` are HTML-encoded and need decoding.
- **Image resolution:** The `preview.images` array has multiple resolutions. Use one close to 1920px wide for TV (the `source` can be very large).
- **NSFW flag:** Use `over_18` field for filtering (only when NSFW toggle is disabled in Settings).
- **YouTube-linked Reddit posts:** Detect via `domain` containing "youtube.com" or "youtu.be". Classify as `PostType.youtube`. Extract the video ID from `url_overridden_by_dest` and store in `outboundURL`.

### YouTube Videos (via `https://www.youtube.com/oembed`)

Unauthenticated oEmbed endpoint. Returns `title`, `author_name`, `thumbnail_url`, and dimensions. Does NOT return duration. YouTube items always classify as `PostType.youtube`.

### Concurrency and Caching

- Up to 10 concurrent metadata fetches per refresh.
- Per-request timeout: 10 seconds.
- Cached results stay fresh for 24 hours. Stale items refetch in the background while the list renders with the stale data.
- If refetch fails, keep the stale cache and show a stale badge on the affected item.

### Public Endpoint Risk

Both endpoints used by v1 (`reddit.com/.json` and `youtube.com/oembed`) are currently public and unauthenticated. If either is gated in the future, the corresponding resolver breaks and we may need to move to the authenticated API (Phase 7 for Reddit, or a YouTube Data API key).

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
