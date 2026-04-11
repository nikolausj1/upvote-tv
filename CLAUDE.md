# Upvote TV - Project Instructions

## What This Is

A personal-use tvOS app that displays the user's 100 most recent upvoted Reddit posts in a polished Apple TV interface. Not a Reddit client. Not for public distribution. See `PRD.md` for full requirements.

## Tech Stack

- **Platform:** tvOS (Apple TV)
- **Language:** Swift
- **UI Framework:** SwiftUI
- **Video Playback:** AVKit
- **Local Persistence:** SwiftData
- **Preferences:** Settings.bundle (tvOS system settings)
- **Architecture:** MVVM with a content provider protocol abstraction

## Project Structure

```
UpvoteTV/
├── App/                          # App entry point, configuration
│   ├── UpvoteTVApp.swift
│   └── Secrets.plist             # NOT in source control
├── Models/                       # Data models
│   ├── Post.swift
│   ├── PostType.swift
│   ├── GalleryItem.swift
│   ├── WatchedState.swift        # SwiftData model
│   ├── CachedPost.swift          # SwiftData model
│   └── AuthState.swift           # SwiftData model
├── Providers/                    # Content provider abstraction
│   ├── ContentProvider.swift     # Protocol
│   ├── RedditContentProvider.swift
│   └── MockContentProvider.swift
├── Services/                     # Auth, networking, persistence
│   ├── AuthService.swift
│   ├── RedditAPIClient.swift
│   ├── RedditResponseParser.swift
│   └── WatchedStateManager.swift
├── Views/                        # SwiftUI views
│   ├── Browse/
│   │   ├── BrowseListView.swift
│   │   ├── PostCardRow.swift
│   │   ├── TypeIconView.swift
│   │   └── CaughtUpRow.swift
│   ├── Detail/
│   │   ├── VideoDetailView.swift
│   │   ├── ImageDetailView.swift
│   │   ├── TextDetailView.swift
│   │   ├── GalleryDetailView.swift
│   │   ├── YouTubeDetailView.swift
│   │   ├── LinkDetailView.swift
│   │   └── MediaErrorView.swift
│   └── States/
│       ├── LoadingView.swift
│       ├── AuthErrorView.swift
│       └── StaleBanner.swift
├── ViewModels/
│   ├── GalleryViewModel.swift
│   └── DetailViewModel.swift
├── Settings.bundle/              # NSFW toggle in tvOS Settings
│   └── Root.plist
├── Resources/
│   └── Assets.xcassets
└── Tools/
    └── reddit-auth-setup.sh      # Helper script for initial OAuth setup
```

## Critical Architecture Rules

1. **UI never talks to Reddit directly.** All data flows through the `ContentProvider` protocol.
2. **MockContentProvider comes first.** Build and test all UI against mock data before touching Reddit integration.
3. **Secrets.plist must never be committed.** Add it to .gitignore immediately.
4. **Reddit refresh tokens are single-use.** After each token refresh, the NEW refresh token must be persisted immediately. Reusing an old token invalidates the entire chain.
5. **Graceful degradation over filtering.** Show posts even when they can't render perfectly. Only hide truly broken/deleted posts with no usable data.
6. **Cached content is the safety net.** If API calls fail, the app must still work with cached data + stale banner.

## Reddit API Gotchas

- **v.redd.it videos:** Audio and video are separate DASH streams. Use the `hls_url` field from `media.reddit_video` for AVKit playback. The `fallback_url` is video-only (no audio).
- **Gallery posts:** Image data is split across `gallery_data.items` (ordering) and `media_metadata` (URLs). URLs in `media_metadata` are HTML-encoded and need decoding.
- **Image resolution:** The `preview.images` array has multiple resolutions. Use a resolution appropriate for TV (close to 1920px wide), not the full-size source.
- **Rate limits:** 60 requests/minute for authenticated free-tier use. Respect `X-Ratelimit-*` headers. Handle 429 with a single retry.
- **NSFW flag:** Use `over_18` field for filtering.
- **YouTube links:** Cannot be played in-app (no web view on tvOS, no embeddable YouTube player). Detect via `domain` containing "youtube.com" or "youtu.be". Classify as `PostType.youtube`. Show a preview card with an "Open in YouTube" button that deep-links via `youtube://watch?v={id}` or falls back to the HTTPS URL. Mark watched only when the user taps "Open in YouTube", not on a timer.

## Build Phases

Follow the implementation phases in PRD.md. The key principle: get the app fully working with mock data before integrating Reddit. This means Phases 1-3 can proceed without any Reddit credentials.

## Commands

```bash
# Build for tvOS Simulator
xcodebuild -scheme UpvoteTV -destination 'platform=tvOS Simulator,name=Apple TV' build

# Run tests
xcodebuild -scheme UpvoteTV -destination 'platform=tvOS Simulator,name=Apple TV' test
```

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
- Title is the dominant element in every row - must be readable from 6-10 feet
