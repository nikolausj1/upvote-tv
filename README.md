# Upvote TV

A personal Apple TV app that turns your upvoted Reddit posts into a curated viewing queue for the big screen.

![tvOS](https://img.shields.io/badge/platform-tvOS_18-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-blue)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Why

I upvote Reddit posts throughout the day as a quick way to bookmark things I want to watch or share later. When it's time to sit on the couch, there's no good way to browse that list on the TV. Reddit's tvOS app is long gone, and AirPlay mirroring kills the lean-back experience.

Upvote TV fixes that. It pulls your 100 most recent upvoted posts and presents them in a native Apple TV interface — designed to feel like a personal content feed, not a developer tool.

## What It Looks Like

A single-column list of soft cards. Each card shows the post type, title, metadata, and an optional thumbnail. Selecting a card opens the content full-screen.

```
┌─────────────────────────────────────────────────────────────┐
│  NEW                                                        │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 🟦  Aurora borealis from my backyard    [thumb]   ●   │  │
│  │     r/space · 3 hours ago                              │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │ 🟥  Grandmother's pasta recipe          [thumb]   ●   │  │
│  │     r/Cooking · 5 hours ago                            │  │
│  ├────────────────────────────────────────────────────────┤  │
│  │ 🟩  10 years as a software engineer                ●   │  │
│  │     r/cscareerquestions · 9 hours ago                  │  │
│  └────────────────────────────────────────────────────────┘  │
│  WATCHED                                                    │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ 🟥  Golden retriever opens the fridge   [thumb]   ✓   │  │
│  │     r/funny · 1 day ago                                │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Six post types** — video, image, gallery, text, YouTube, and link — each with a dedicated full-screen detail view
- **Watched state tracking** — posts you've viewed move to a "Watched" section; unwatched posts stay on top
- **Smart watched rules** — video marks at 85% playback, images/text/galleries after 2 seconds, YouTube only when you tap "Open in YouTube"
- **NSFW filtering** — toggle via tvOS system Settings
- **Offline resilience** — cached metadata keeps the app usable when the network is down, with a stale-content banner
- **Dark, minimal UI** — designed for a TV viewing distance with large typography and generous whitespace

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Platform | tvOS 18 |
| Language | Swift |
| UI | SwiftUI |
| Video | AVKit |
| Persistence | SwiftData |
| Preferences | Settings.bundle |
| Architecture | MVVM + ContentProvider protocol |

## Project Structure

```
UpvoteTV/
├── Models/              # Post, PostType, GalleryItem, SwiftData models
├── Providers/           # ContentProvider protocol, Mock + Reddit implementations
├── Services/            # Auth, API client, watched state, rate limiting, NSFW filter
├── ViewModels/          # GalleryViewModel, DetailViewModel
├── Views/
│   ├── Browse/          # Card list, PostCardRow, TypeIconView
│   ├── Detail/          # Video, Image, Text, Gallery, YouTube, Link views
│   └── States/          # Loading skeleton, auth error, stale banner
├── Settings.bundle/     # NSFW toggle
└── Resources/           # Assets
```

## Architecture

The UI never talks to Reddit directly. All data flows through a `ContentProvider` protocol:

```swift
protocol ContentProvider {
    func fetchUpvotedPosts() async throws -> [Post]
}
```

`MockContentProvider` returns sample data for development. `RedditContentProvider` handles the real API. The app doesn't know or care which one it's using.

## Building

```bash
# Build for tvOS Simulator
xcodebuild -scheme UpvoteTV \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  build

# Run tests
xcodebuild -scheme UpvoteTV \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  test
```

> **Note:** The app currently runs against mock data. Reddit API integration (Phase 4) is pending API approval.

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Data models, providers, SwiftData setup | Done |
| 2 | Browse list UI with mock data | Done |
| 3 | All detail views (video, image, text, gallery, YouTube, link) | Done |
| 4 | Reddit API integration | Pending API approval |
| 5 | Polish — rate limiting, NSFW filter, debug overlay, memory optimization | Done |
| 6 | Auth setup tooling | Not started |

## License

MIT — do whatever you want with it.

## Credits

Built by [Justin Nikolaus](https://github.com/nikolausj1) with [Claude Code](https://claude.ai/claude-code).
