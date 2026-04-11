---
title: "PRD: Upvote TV - Personal tvOS Reddit Viewer"
created: 2026-04-10
modified: 2026-04-10
version: 2.0
author: Claude Opus 4.6 (claude-opus-4-6)
tags:
---

# PRD: Upvote TV

A personal Apple TV app that turns recently upvoted Reddit posts into a curated TV viewing queue.

---

## Problem Statement

Justin upvotes Reddit posts throughout the day on his phone as a lightweight way to bookmark content he wants to share with his wife later. When they sit down in front of the TV together, there's no good way to pull up that curated list and browse it on the big screen. Reddit's own tvOS app is discontinued, and browsing Reddit via AirPlay or screen mirroring is clunky and kills the "lean back" TV experience.

The app should make it feel like they have a personal content feed on their Apple TV, not like they're using a developer tool to query an API.

## Target Users

Justin and his wife. This is a personal-use app, not intended for public distribution. It will be installed through Xcode's developer workflow, not the App Store.

## Goals

1. Fetch the 100 most recent upvoted Reddit posts and display them in a polished two-pane Apple TV interface.
2. Track which posts have been watched on the TV so unwatched content is always prioritized.
3. Support video, image, text, gallery, and link post types with graceful degradation for anything that can't render perfectly.
4. Feel like a premium, minimal Apple TV media app - not a Reddit client or a developer utility.
5. Keep the codebase structured so Reddit integration is isolated behind an abstraction, making the app testable and improvable without live API access.

## Non-Goals (v1)

These are explicitly out of scope for v1:

- **Browsing Reddit broadly.** No subreddits, home feed, popular feed, or search. The only data source is the user's upvoted posts.
- **Social features.** No comments, voting from TV, saving posts, or account switching.
- **Public distribution.** No App Store submission, public onboarding flow, or companion iOS/Mac app.
- **Backend services.** No server, no cloud sync, no cross-device watched state.
- **In-app authentication UI.** Auth is configured manually by the developer outside the app.
- **Manual refresh controls.** The app refreshes automatically on launch. No pull-to-refresh or refresh button.
- **Post-to-post navigation in detail view.** No next/previous swiping between Reddit posts. The user always returns to the gallery list to pick the next item.
- **Offline media caching.** Metadata and watched state persist locally, but media loads on demand.
- **Settings screen.** The only user preference (NSFW toggle) lives in tvOS system Settings via Settings.bundle.

---

## Architecture Overview

### System Diagram

```
+--------------------------------------------------+
|                   Upvote TV App                   |
|                                                   |
|  +------------+    +-------------------------+    |
|  |   UI Layer |    |  Content Provider       |    |
|  |  (SwiftUI) |--->|  (Protocol)             |    |
|  +------------+    +-------+-----------+-----+    |
|                        |               |          |
|              +---------+----+  +-------+-------+  |
|              | Reddit       |  | Mock           |  |
|              | Provider     |  | Provider       |  |
|              +---------+----+  +---------------+  |
|                        |                          |
|              +---------+----+                     |
|              | Auth Service |                     |
|              | (Token Mgmt) |                     |
|              +--------------+                     |
|                                                   |
|  +---------------+    +----------------------+    |
|  | Persistence   |    | Media Loading        |    |
|  | (SwiftData)   |    | (AVKit + URLSession) |    |
|  +---------------+    +----------------------+    |
+--------------------------------------------------+
```

### Layer Responsibilities

**UI Layer (SwiftUI):** All screens, focus handling, and visual presentation. Consumes a `ContentProvider` protocol. Never talks to Reddit directly.

**Content Provider Protocol:** Abstraction that the UI depends on. Defines methods like `fetchUpvotedPosts()` and returns normalized app-level models. Two concrete implementations:
- `RedditContentProvider` - fetches from Reddit API
- `MockContentProvider` - returns local test data for development and SwiftUI previews

**Auth Service:** Manages OAuth token lifecycle. Reads initial refresh token from config file, handles token refresh, persists rotated tokens, surfaces auth failures clearly.

**Persistence Layer (SwiftData):** Stores cached post snapshots, watched state, and rotated auth tokens locally on device.

**Media Loading Layer:** Loads images and video on demand using platform APIs. Handles Reddit's media URL resolution quirks (see Media Handling section).

### Why This Matters

Reddit API access can be flaky, rate-limited, or break due to token issues. By isolating Reddit behind a provider protocol, the UI layer remains fully testable, previewable, and polishable even when the API is unavailable. The `MockContentProvider` should be the first thing built, and the app should be fully functional with mock data before any Reddit integration begins.

---

## Prerequisites (Before Writing Any Code)

These steps must be completed by Justin manually before the app can function.

### 1. Apple Developer Account

Sign up at developer.apple.com. A free account works for personal development, but a paid account ($99/year) is needed to install apps on a physical Apple TV. For Simulator-only development, free is fine.

### 2. Xcode Installation

Install Xcode from the Mac App Store. Ensure tvOS SDK and Simulator are included (check Xcode > Settings > Platforms).

### 3. Reddit API Application Registration

Go to https://www.reddit.com/prefs/apps and create a new application:
- Type: "installed app" (not "web app" or "script")
- Name: "Upvote TV" (or anything)
- Redirect URI: a custom scheme like `upvotetv://auth/callback`
- Note the **client ID** (shown under the app name)

### 4. Obtain Initial Reddit Refresh Token

This is the trickiest manual step. Because tvOS has no web browser, the initial OAuth authorization must happen on a computer. The process:

1. Open a browser and visit Reddit's authorization URL with the app's client ID, requesting `history` and `identity` scopes (the `history` scope is what grants access to upvoted posts)
2. Authorize the app when Reddit prompts
3. Reddit redirects to the custom scheme URL with an authorization code
4. Exchange that code for an access token + refresh token using a curl command or simple script
5. Save the refresh token - this is what goes into the app's config file

**Claude Code should generate a helper script** that walks through this process and outputs the refresh token. This is a one-time setup step.

### 5. Configuration File

Create a `Secrets.plist` file (excluded from source control via .gitignore) containing:
- `redditClientID` - the client ID from step 3
- `redditRefreshToken` - the refresh token from step 4
- `redditUsername` - the Reddit username

---

## Authentication Architecture

### Token Lifecycle

Reddit OAuth tokens work as follows:
- Access tokens expire after 1 hour
- Refresh tokens are **single-use** - each time you use one to get a new access token, Reddit issues a new refresh token and invalidates the old one
- If a refresh token is used twice (or an old one is reused), the entire token chain is invalidated

### What the App Must Do

1. On launch, read the refresh token from local persistence (or from `Secrets.plist` on first launch)
2. Use the refresh token to obtain a new access token
3. **Immediately persist the new refresh token** returned in the response - this replaces the old one
4. Use the access token for all API calls until it expires
5. When the access token expires, repeat from step 2

### Auth Failure States

When auth fails (invalid/expired refresh token, Reddit account password change, token revocation):
- Show a clear, non-technical error screen: "Authentication expired. You'll need to generate a new refresh token."
- Include a brief instruction pointing to the setup process
- The app should still display cached content if available, with a banner indicating data may be stale
- Do not show raw HTTP errors, token strings, or API response codes in the normal UI

### Auth Error Debug Mode

In debug builds only, include additional diagnostic information:
- HTTP status codes
- Token validation state
- Last successful auth timestamp
- API error response bodies

---

## Reddit API Integration

### Endpoint

`GET /user/{username}/upvoted`
- Requires OAuth with `history` scope
- Returns paginated results (25 items per page by default, max 100 per request via `limit` parameter)
- Use `after` parameter for pagination to fetch additional pages if needed

### Rate Limits

Reddit allows 60 authenticated requests per minute for free-tier (non-commercial) use. For this app, a single launch will need:
- 1-2 requests to fetch 100 upvoted posts (one request with `limit=100`, or two paginated requests)
- 1 request per token refresh

This is well within limits. However, the app should:
- Respect `X-Ratelimit-Remaining` and `X-Ratelimit-Reset` headers
- Handle HTTP 429 (rate limited) by waiting and retrying once
- Never retry more than once automatically

### Response Normalization

Reddit API responses are messy. The raw JSON structure varies significantly by post type. The content provider must normalize responses into the app's internal `Post` model. Key challenges:

**Video posts (v.redd.it):**
- Reddit splits video and audio into separate DASH streams
- The `media.reddit_video` object contains `dash_url`, `hls_url`, and `fallback_url`
- **Use `hls_url` for tvOS playback** - AVKit handles HLS natively
- The `fallback_url` is video-only (no audio) - do not use as primary source
- If `hls_url` is not available, fall back to `fallback_url` with a note that audio may be missing

**Image posts:**
- Reddit-hosted images have a `preview.images` array with multiple resolutions
- Use the resolution closest to 1920px wide for TV display (the `source` resolution can be very large)
- External image hosts (imgur, etc.) may need direct URL usage

**Gallery posts:**
- Gallery data is split across two fields: `gallery_data.items` (ordering) and `media_metadata` (URLs keyed by media ID)
- Each item in `media_metadata` has an `s` (source) object with `u` (URL) and dimensions
- URLs in `media_metadata` are HTML-encoded (ampersands as `&amp;`) and must be decoded

**YouTube posts:**
- Detected during normalization when `domain` contains "youtube.com" or "youtu.be"
- Extract the video ID from the URL (e.g., `v=dQw4w9WgXcQ` or `youtu.be/dQw4w9WgXcQ`)
- These cannot be played in-app - tvOS has no web view and YouTube has no embeddable player for third-party tvOS apps
- Classify as `PostType.youtube` so the UI can show the dedicated YouTube detail view with an "Open in YouTube" button
- Use Reddit's `preview.images` for the thumbnail/preview image
- Store the YouTube video ID in `outboundURL` for deep linking

**Link posts:**
- May have a `thumbnail` URL but no full media
- Use `url_overridden_by_dest` for the outbound link
- `domain` field indicates the source

**Text posts:**
- `selftext` contains the body (may be markdown)
- `selftext_html` contains rendered HTML

---

## Data Models

### Post Model

```
Post {
    id: String                    // Reddit post ID (e.g., "t3_abc123")
    title: String
    subreddit: String             // Without "r/" prefix
    author: String
    createdAt: Date               // Reddit post creation time
    postType: PostType
    
    // Media URLs (resolved during normalization)
    thumbnailURL: URL?
    previewImageURL: URL?         // Best resolution for TV display
    mediaURL: URL?                // Primary media (video HLS URL, full image, etc.)
    
    // Gallery-specific
    galleryItems: [GalleryItem]?  // Ordered list of images
    
    // Text-specific  
    textBody: String?             // Selftext content
    
    // Link-specific
    outboundURL: URL?
    domain: String?               // e.g., "youtube.com", "nytimes.com"
    
    // Metadata
    isNSFW: Bool
    score: Int?                   // Upvote count (for display only)
}
```

### PostType Enum

```
PostType {
    case video          // v.redd.it, streamable, etc.
    case image          // Single image (Reddit-hosted or external)
    case text           // Self/text post
    case gallery        // Multi-image Reddit gallery
    case youtube        // YouTube video link (cannot embed, opens YouTube app)
    case link           // Outbound link with no embeddable media
    case unsupported    // Anything that can't be categorized
}
```

### GalleryItem Model

```
GalleryItem {
    id: String
    imageURL: URL
    width: Int
    height: Int
    position: Int                 // Display order
}
```

### WatchedState Model (Persisted via SwiftData)

```
WatchedState {
    postID: String                // Keyed to Post.id
    isWatched: Bool
    watchedAt: Date?
    lastViewedAt: Date?
    viewCount: Int                // Default 0, for future use
}
```

### CachedPost Model (Persisted via SwiftData)

```
CachedPost {
    // Mirror of Post model fields, stored locally
    // Used when API refresh fails so the app still has content to show
    cachedAt: Date                // When this snapshot was stored
}
```

### AuthState Model (Persisted via SwiftData)

```
AuthState {
    refreshToken: String
    accessToken: String?
    accessTokenExpiresAt: Date?
    lastRefreshAt: Date?
}
```

---

## Screen-by-Screen Requirements

### Screen A: Browse List (Main Screen)

This is the primary screen and the navigation hub. It uses a single-column, full-width list layout. There is no two-pane split or side preview panel. Selecting any post opens it full-screen.

**Row Layout (Soft Card Style):**

Each row is a subtle card with a faint background and border. The layout of each row from left to right:

1. **Type icon** (left side) - A colored SF Symbol icon in a rounded square container that immediately communicates what kind of content the post is:
   - Video: `play.rectangle.fill` (red tint)
   - Image: `photo` (blue tint)
   - Gallery: `square.stack` (purple tint)
   - Text: `doc.text` (green tint)
   - YouTube: `play.rectangle.fill` (red tint, same as video - distinguished by "YouTube" badge or youtube.com domain in metadata)
   - Link: `arrow.up.right` (amber tint)
   Each icon container is approximately 40x40pt with a colored background tint matching the content type.

2. **Title and metadata** (center, takes remaining width) - The post title is the dominant element. Large, readable, up to 2 lines. Below the title: subreddit name (accent colored), post age, and domain for link/YouTube posts. The title must be easily readable from TV viewing distance (6-10 feet).

3. **Thumbnail** (right side, optional) - A small thumbnail image (approximately 96x64pt, rounded corners) appears on the right for posts that have visual content (image, video, gallery, YouTube). Text and link posts without good thumbnails skip the thumbnail entirely, giving the title more breathing room.

4. **Watched/unwatched indicator** (far right) - Blue dot for unwatched, subtle checkmark for watched.

**Card Styling:**
- Each row has a subtle background fill (approximately 2% white) and faint border (approximately 3% white)
- Focused/hovered rows brighten slightly with a stronger border and subtle lift/scale
- Watched rows dim further (1% white background, more transparent border)
- Spacing between cards: approximately 8pt

**Sort Order:**
1. Unwatched posts first
2. Watched posts below
3. Within each group, newest first (by Reddit post creation time)

The list order must remain stable. Reopening a watched item does not move it. Marking an item unwatched does not reorder the list until the next app launch/refresh.

**Section Headers:**
- "New" label above the unwatched group
- "Watched" label above the watched group
- Small, uppercase, subtle color (similar to system secondary label)

**Default Focus:**
- On launch, focus goes to the top item in the list
- Since unwatched posts sort first and newest first, this should be the newest unwatched post
- If all posts are watched, focus goes to the "You're Caught Up" synthetic row

**Context Menu (Long Press):**
- Long-pressing the select button on any post row opens a context menu
- MVP options: "Mark as Unwatched" (for watched items) / "Mark as Watched" (for unwatched items)
- This is a local state change only - nothing is sent to Reddit

### Screen A-1: "You're Caught Up" State

When no unwatched posts exist:
- A synthetic row appears at the top of the left list, labeled "You're Caught Up"
- This row receives default focus
- Watched posts remain visible and browsable below it
- When this row is focused, the right pane shows: "You're Caught Up" heading with "No new upvoted posts to watch together right now." subtitle
- Selecting this row does nothing
- This should look intentional and designed, not like an error or placeholder

### Screen B: Video Detail View

Triggered by selecting a video-type post from the gallery.

- Video autoplays immediately on open
- Audio is on by default
- Center click (select button) toggles play/pause
- Standard tvOS scrubbing behavior via swipe on touchpad
- At end of playback, show a single "Replay" action - no "Next Post" button
- Back/Menu button returns to the gallery at the same focused row and scroll position
- Mark watched when playback reaches 85% duration

### Screen C: Image Detail View

Triggered by selecting an image-type post from the gallery.

- Full-screen image display
- No buttons or overlays on screen
- No metadata overlay (not even on center click in v1)
- Back/Menu returns to gallery at same position
- Mark watched after 2 seconds

### Screen D: Text Detail View

Triggered by selecting a text-type post from the gallery.

- Title displayed prominently at top
- Body text below, vertically scrollable via tvOS remote swipe
- Clean typography, generous margins, optimized for TV reading distance
- Back/Menu returns to gallery at same position
- Mark watched after 2 seconds

### Screen E: Gallery Detail View (Multi-Image)

Triggered by selecting a gallery-type post from the gallery.

- Opens into a full-screen image viewer for that single Reddit post's images
- Left/right swipe navigates between images within the post
- Small position indicator (e.g., "2 / 5") visible but unobtrusive
- No filmstrip or thumbnail rail in v1
- No navigation to other Reddit posts from within this view
- Back/Menu returns to the main gallery at same position
- Mark watched after 2 seconds open or after any interaction within the gallery

### Screen F-1: YouTube Detail View

Triggered by selecting a youtube-type post from the gallery. YouTube videos cannot be played inside the app because tvOS has no web view and YouTube does not provide an embeddable player for third-party tvOS apps. Instead, the app shows a preview card and offers to open the YouTube app.

- Large thumbnail/preview image at top
- Title displayed prominently below
- "YouTube" badge and video duration if available
- Subreddit and post age
- Prominent "Open in YouTube" button that launches the YouTube app via URL scheme (`youtube://watch?v={videoID}` or `https://www.youtube.com/watch?v={videoID}`)
- If the YouTube app is not installed, the button should handle the failure gracefully (show a brief "YouTube app not found" message)
- Back/Menu returns to gallery at same position
- Mark watched after selecting "Open in YouTube" (not after 2 seconds, since the user hasn't seen the content yet just by viewing the card)

### Screen F-2: Link/Fallback Detail View

Triggered by selecting a link-type or unsupported-type post from the gallery.

- Title displayed prominently
- Domain shown (e.g., "nytimes.com")
- Text excerpt or selftext if available
- Thumbnail if available
- This is a polished information card, not an error state
- Back/Menu returns to gallery at same position
- Mark watched after 2 seconds

### Screen G: Media Error State

Shown when a specific post's media fails to load after the detail view opens.

- Title of the post
- Simple message: "Media could not be loaded"
- Back/Menu returns to gallery at same position
- Do not mark as watched

### Screen H: Loading State

Shown on app launch while fetching data.

- App shell (list layout) appears immediately
- Shows skeleton/placeholder card rows matching the soft card layout
- Transition to real content when data arrives
- Should feel fast and intentional, not janky

### Screen I: Auth Error / Setup State

Shown when auth configuration is missing or invalid.

- Clean, non-technical message: "Setup Required" or "Authentication Expired"
- Brief guidance: "Check the project README for setup instructions."
- If cached content exists, show it with a stale-data banner instead of this screen
- Debug builds show additional technical detail below the user-facing message

### Screen J: Stale Data Banner

Shown when the app has cached content but the current refresh failed.

- Small, non-intrusive banner at the top of the gallery
- Text like: "Showing cached content. Last updated 2 hours ago."
- Does not block interaction
- Gallery and detail views function normally with cached data

---

## Watched State Rules

| Post Type | When Marked Watched |
|-----------|-------------------|
| Video/GIF | Playback reaches 85% of duration |
| Image | After 2 seconds in detail view |
| Text | After 2 seconds in detail view |
| Gallery | After 2 seconds open OR any interaction within |
| YouTube | When user taps "Open in YouTube" (not on view of card) |
| Link/Fallback | After 2 seconds in detail view |
| Media Error | Never marked watched |

**Visual Treatment - Unwatched:**
- Full brightness type icon, thumbnail, and title
- Stronger title contrast
- Small bright blue dot indicator on far right of card
- Card background at normal subtle tint

**Visual Treatment - Watched:**
- Small checkmark replacing the blue dot
- Dimmed thumbnail (~50% opacity)
- Reduced title contrast (muted color)
- Card background slightly more transparent
- Still fully attractive and easily selectable

The visual distinction must be clear from TV viewing distance (6-10 feet).

---

## NSFW Handling

- Controlled via Settings.bundle (tvOS system Settings > Apps > Upvote TV)
- **Default on first launch: NSFW enabled** (show NSFW posts normally)
- When NSFW is disabled: hide NSFW posts completely from the gallery and detail flow
- Filtering uses the `over_18` flag from Reddit API responses

---

## Startup and Refresh Behavior

1. App launch shows the shell immediately with skeleton rows
2. Auth service attempts token refresh
3. If auth succeeds, fetch upvoted posts from Reddit
4. Normalize responses into Post models
5. Merge with existing watched state
6. Update cached post snapshot in SwiftData
7. Replace skeleton with real content
8. If auth or fetch fails, load cached posts and show stale-data banner

**Caching:** The app persists the last successful post snapshot locally. This means the app is usable even after auth failures or network issues - the content just may not be current.

**No manual refresh UI in v1.** To refresh, close and reopen the app.

---

## Visual Design Direction

**The app should feel:** Minimal. Premium. Calm. Dark-first. Spacious. Apple TV native. Content-first.

**The app should NOT feel:** Reddit-branded. Cluttered. Utilitarian. Debug-like. Busy. Like a generic API client.

**Guidance:**
- Clean, large typography optimized for TV distance
- Generous whitespace and padding
- Minimal on-screen controls
- Elegant focus highlight treatments using tvOS native focus engine
- Dark background, high-contrast text
- Subtle animations for focus changes and transitions
- No Reddit logos, Reddit colors, or Reddit branding anywhere

---

## tvOS-Specific Technical Notes

**Memory:** Apple TV has limited memory compared to iOS devices. Prefer Reddit's preview images at resolutions appropriate for 1080p/4K display rather than loading full-resolution originals. Avoid holding multiple full-resolution images in memory simultaneously.

**Focus Engine:** Use tvOS's built-in focus system rather than inventing custom navigation. The focus engine handles the remote's swipe-to-move and click-to-select behavior automatically when using standard SwiftUI views.

**AVKit:** Use AVKit for all video playback. It provides standard tvOS transport controls (play, pause, scrub) automatically. For HLS streams (which Reddit's v.redd.it provides), AVKit handles adaptive bitrate streaming natively.

**Settings.bundle:** This is the standard tvOS mechanism for app preferences that appear in the system Settings app. It requires a `Settings.bundle` directory in the app bundle with a `Root.plist` defining the toggle.

---

## Performance Expectations

- App shell visible within 1 second of launch
- Focus movement between list items feels instant (no visible lag)
- Right preview pane updates within ~200ms of focus change
- Returning from detail view to gallery restores exact position
- Video playback starts within 2-3 seconds of selecting a video post
- Watched state persists immediately (no delay or "saving" indicator)

---

## Acceptance Criteria

The MVP is complete when all of the following are true:

1. App launches into a polished full-width soft card list with skeleton loading state
2. App fetches 100 most recent upvoted Reddit posts using developer-configured auth
3. Auth token rotation is handled correctly (new refresh tokens are persisted)
4. List shows unwatched items first, watched items below, newest first within each group
5. Default focus goes to top item, or "You're Caught Up" row when all posts are watched
6. Each card row shows colored type icon, title, metadata, optional thumbnail, and watched indicator
7. Selecting a row opens a full-screen detail view for that single post
8. YouTube posts show a preview card with "Open in YouTube" button
9. Video posts autoplay with audio, show Replay at end, mark watched at 85%
10. Image posts display full-screen with no UI overlay, mark watched after 2s
11. Text posts show scrollable title + body, mark watched after 2s
12. Gallery posts support in-post image navigation with position indicator
13. Link/unsupported posts show a polished fallback info card
14. Back/Menu always returns to the list at the same scroll position and focused row
15. Watched state persists across app launches
16. Long press on a row exposes Mark as Watched/Unwatched context menu
17. App refreshes on launch, uses cached content if refresh fails
18. Stale-data banner appears when showing cached content after a failed refresh
19. NSFW visibility is controlled through tvOS system Settings
20. Missing/invalid auth shows a clean setup-required screen
21. Media load failures show a clean error state per-post
22. Debug builds expose auth and API diagnostics without affecting normal UX
23. Mock content provider works fully, enabling development without Reddit access
24. App feels minimal, premium, and Apple TV native

---

## Implementation Phases

This section provides recommended build order for Claude Code.

### Phase 1: Project Setup and Mock Data

- Create tvOS Xcode project with SwiftUI
- Define all data models (Post, PostType, GalleryItem, WatchedState, etc.)
- Build MockContentProvider with realistic sample data covering all post types
- Set up SwiftData persistence for watched state and cached posts
- Create Settings.bundle for NSFW toggle
- Add Secrets.plist to .gitignore template

### Phase 2: Gallery Screen with Mock Data

- Build the two-pane gallery layout
- Implement left list with focus handling
- Implement passive right preview pane
- Implement sort logic (unwatched first, newest first)
- Implement watched/unwatched visual treatment
- Build "You're Caught Up" synthetic row
- Build skeleton loading state
- Build long-press context menu

### Phase 3: Detail Views with Mock Data

- Video detail view (using a sample HLS stream for testing)
- Image detail view
- Text detail view
- Gallery detail view with in-post navigation
- Link/fallback detail view
- Media error state
- Watched-state auto-marking logic for each type
- Back navigation preserving gallery position

### Phase 4: Reddit Integration

- Build auth service with token rotation and persistence
- Build Reddit API client for `/user/{username}/upvoted`
- Build response normalizer handling all post type variations
- Handle v.redd.it HLS URL extraction
- Handle gallery data structure (gallery_data + media_metadata)
- Handle image preview resolution selection
- Wire RedditContentProvider to UI
- Build auth error / setup-required screen
- Build stale-data banner
- Build refresh-on-launch flow

### Phase 5: Polish and Edge Cases

- Rate limit handling (429 retry)
- NSFW filtering based on Settings.bundle preference
- Debug diagnostic overlay for dev builds
- Performance optimization (image sizing, memory)
- Visual polish pass (typography, spacing, focus animations)
- Test all error states and fallback paths

### Phase 6: Auth Setup Tooling

- Generate a helper script or CLI tool that walks through the Reddit OAuth flow on a Mac
- Script opens browser for authorization, captures the callback, exchanges for tokens
- Outputs a ready-to-use Secrets.plist file

---

## Open Questions

| Question | Owner | Blocking? |
|----------|-------|-----------|
| Does Reddit's `limit=100` parameter work reliably on the upvoted endpoint, or will we need pagination? | Engineering (test during Phase 4) | No |
| What resolution should preview images target for optimal Apple TV display without excessive memory use? | Engineering (test during Phase 5) | No |
| Should watched state for posts that drop out of the top 100 be pruned, or kept indefinitely? | Product decision (Justin) | No |
| Is the `hls_url` field reliably present on v.redd.it posts, or do some only have `dash_url`? | Engineering (test during Phase 4) | No |

---

## Future Considerations (v2+)

Intentionally deferred but worth designing around:

- In-app OAuth flow using device code grant (eliminates manual token setup)
- App Store submission with proper onboarding
- Companion iPhone app for easier auth and settings
- Custom media caching for offline viewing
- Next/previous post navigation from detail view
- Autoplay/playlist mode for video posts
- Sync watched state across devices
- Multiple user profiles
- Search or filter within upvoted posts
