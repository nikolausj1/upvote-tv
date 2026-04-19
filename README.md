---
title: "Upvote TV"
created: 2026-04-10
modified: 2026-04-18
version: 3.2
author: Claude Opus 4.7 (claude-opus-4-7)
tags:
---

# Upvote TV

A personal Apple TV app that turns a shared iPhone-curated queue into a cozy couch viewing experience.

![tvOS](https://img.shields.io/badge/platform-tvOS_18-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Why

Throughout the day I collect content I want to watch later with my wife on the TV. Reddit posts, YouTube videos, occasional oddities. Apple TV doesn't have a good way to unify a cross-source queue, and browsing Reddit or YouTube on the TV with the remote kills the lean-back experience.

Upvote TV fixes that. Anything shared from either of our iPhones via the share sheet lands in a shared queue. The Apple TV app reads that queue, resolves titles and thumbnails from public endpoints, and presents everything as a polished Apple TV native interface.

No Reddit account login, no OAuth, no developer approval queue. Just share and watch.

## How It Works

```
iPhone (anyone in the household)
  ↓ Share Sheet → Upvote TV Share Extension
  ↓
GitHub Gist / queue.json
  ↓
Apple TV App
  ↓ resolves metadata from:
  ↓   reddit.com/comments/{id}.json
  ↓   youtube.com/oembed
  ↓
Polished card list, full-screen detail views
```

Three Xcode targets make this go: the tvOS app (the player), a small iOS companion app, and an iOS Share Extension that registers with the share sheet. A `Shared/` Swift folder holds the queue-client code used by all three.

## What It Looks Like

A single-column list of soft cards. Each card shows the post type, title, metadata, and an optional thumbnail. Selecting a card opens the content full-screen.

```
┌─────────────────────────────────────────────────────────────┐
│  NEW                                                        │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 🟦  Aurora borealis from my backyard   [thumb]    ●   │ │
│  │     r/space · shared 2 hours ago                       │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ 🟥  How the James Webb sees further   [thumb]     ●   │ │
│  │     YouTube · Veritasium · shared 4 hours ago          │ │
│  ├────────────────────────────────────────────────────────┤ │
│  │ 🟩  10 years as a software engineer               ●   │ │
│  │     r/cscareerquestions · shared 9 hours ago           │ │
│  └────────────────────────────────────────────────────────┘ │
│  WATCHED                                                    │
│  ┌────────────────────────────────────────────────────────┐ │
│  │ 🟥  Golden retriever opens the fridge  [thumb]    ✓   │ │
│  │     r/funny · shared 1 day ago                         │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Two sources in v1:** Reddit posts and YouTube videos. Each with a dedicated full-screen detail view.
- **Six post types** for Reddit content: video, image, gallery, text, YouTube-linked, and link. Plus direct YouTube queue items.
- **Shared household queue:** Any iPhone with the Upvote TV iOS app installed contributes to the same queue via the native Share Extension.
- **Watched state tracking:** Viewed posts move to a "Watched" section; unwatched posts stay on top.
- **Smart watched rules:** Video marks at 50% playback, images/text/galleries after 2 seconds, YouTube only when you tap "Open in YouTube".
- **Remove from queue:** Long-press any item to drop it from the queue.
- **NSFW filtering:** Toggle via tvOS system Settings. Applies to Reddit items.
- **Offline resilience:** 24-hour metadata cache keeps the app usable when the network is unreliable, with a per-item stale badge.
- **Dark, minimal UI:** Designed for a TV viewing distance with large typography and generous whitespace.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Platform | tvOS 18 |
| Language | Swift |
| UI | SwiftUI |
| Video | AVKit |
| Persistence | SwiftData |
| Cloud Sync | iCloud Drive (ubiquity container) |
| Capture | iOS Shortcut |
| Preferences | Settings.bundle |
| Architecture | MVVM + ContentProvider protocol |

## Project Structure

```
UpvoteTV/
├── Models/              # Post, PostType, GalleryItem, QueueItem, SwiftData models
├── Providers/           # ContentProvider protocol, Mock + Queue implementations
├── Services/            # Queue file I/O, metadata resolvers, cache, watched state
├── ViewModels/          # GalleryViewModel, DetailViewModel
├── Views/
│   ├── Browse/          # Card list, PostCardRow, TypeIconView
│   ├── Detail/          # Video, Image, Text, Gallery, YouTube, Link views
│   └── States/          # Loading skeleton, Setup Required, Empty Queue, Stale badge
├── Settings.bundle/     # NSFW toggle
├── Resources/           # Assets
└── Deferred/            # v2 Reddit API code, kept for optional Phase 7
```

## Architecture

The UI never talks to iCloud, Reddit, or YouTube directly. All data flows through a `ContentProvider` protocol:

```swift
protocol ContentProvider {
    func fetchPosts() async throws -> [Post]
}
```

- **MockContentProvider** returns sample data for development and SwiftUI previews.
- **QueueContentProvider** (v1 primary) reads `queue.json` from a GitHub Gist, then hydrates each queue item into a full `Post` using the appropriate metadata resolver (Reddit or YouTube). Results are cached in SwiftData for 24 hours.
- **RedditContentProvider** is not currently implemented. It would be added back in Phase 7 if Reddit API access is ever approved under the Responsible Builder Policy.

The app doesn't know or care which provider it's using.

## Building

```bash
# Build tvOS for Simulator
xcodebuild -scheme "Upvote TV" \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  build

# Build iOS companion for Simulator
xcodebuild -scheme "Upvote TV Mobile" \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Run tests
xcodebuild -scheme "Upvote TV" \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  test
```

### First-time setup

1. Follow `docs/Gist-Setup.md` to create a secret Gist and a fine-grained GitHub PAT.
2. Copy `Upvote TV/Upvote TV/Secrets.example.plist` to `Upvote TV/Upvote TV/Secrets.plist`.
3. Paste your Gist ID and PAT into `Secrets.plist`. The file is gitignored. Both iOS targets symlink to this file, so one edit suffices for all three app targets.
4. Build & run. Without a valid `Secrets.plist` tvOS shows the Connection Error state.
5. For the iPhone share-sheet flow, see `docs/iOS-App.md` — you'll build `Upvote TV Mobile` and install it on your iPhone via Xcode (or distribute via TestFlight for other household members).

### Testing the Queue Flow

To test the tvOS side without the iOS app, hand-edit the Gist on github.com:

1. Open your secret gist → Edit.
2. Replace the content of `queue.json` with a test payload (see below).
3. Save.
4. Launch Upvote TV. The list should populate within a second or two.

Sample queue.json:

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

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Data models, providers, SwiftData setup (v2 models, migration pending) | Done |
| 2 | Browse list UI with mock data | Done |
| 3 | All detail views (video, image, text, gallery, YouTube, link) | Done |
| v2 → v3 Migration | Update models, move Reddit code to /Deferred, add Queue types | Not started |
| 4 | iCloud queue integration + metadata resolvers | Not started |
| 5 | iOS Shortcut (domain whitelist, normalization, atomic writes) | Not started |
| 6 | Polish and edge cases (NSFW, debug overlay, cache eviction) | Not started |
| 7 | Reddit API (optional, requires Responsible Builder Policy approval) | Deferred |

The original plan used the Reddit API as the primary data source. Reddit's 2025 Responsible Builder Policy introduced an unpredictable manual approval queue, so v3 of the PRD pivoted to the iPhone share-sheet model. Reddit API remains a possible future enhancement.

## License

MIT. Do whatever you want with it.

## Credits

Built by [Justin Nikolaus](https://github.com/nikolausj1) with [Claude Code](https://claude.ai/claude-code).
