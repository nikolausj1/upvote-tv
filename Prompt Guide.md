---
title: "Upvote TV - Claude Code Prompt Guide"
created: 2026-04-10
modified: 2026-04-10
version: 2.0
author: Claude Opus 4.6 (claude-opus-4-6)
tags:
---

# Upvote TV - Claude Code Prompt Guide

A reference of prompts to use when building Upvote TV with Claude Code. Copy and paste these as you work through each phase. You don't need to use them word-for-word - adjust based on what's happening in your project at the time.

---

## Before You Start

When you first open the Upvote TV folder in Claude Code, it will automatically read the CLAUDE.md file. You don't need to tell it about the project from scratch - it already knows the context. Your first message should orient it to the PRD and the current state of the project.

---

## UI Redesign: Two-Pane to Single-Column Card List

Use this prompt NOW. The PRD has been updated from a two-pane split layout to a single-column full-width card list. Since you've already built Phases 1-3 with the old layout, this prompt tells Claude Code to rebuild the browse screen to match the new design.

### Redesign the browse screen

```
I've made a significant design change to the app. Please re-read 
PRD.md and CLAUDE.md - both have been updated.

The main change: we're replacing the two-pane gallery layout with a 
single-column full-width card list. There is no longer a side preview 
panel. Every post type opens full-screen when selected.

Please rebuild the main browse screen (Screen A in the PRD) as follows:

1. Remove the two-pane split layout entirely. No right preview pane.

2. Build a full-width scrollable list where each row is a soft card:
   - Subtle background fill (~2% white) with faint border (~3% white)
   - Focused cards brighten with stronger border and subtle scale/lift
   - ~8pt spacing between cards

3. Each card row contains (left to right):
   - Type icon: SF Symbol in a ~40x40pt rounded square with colored 
     tint background:
     * Video: play.rectangle.fill (red)
     * Image: photo (blue)  
     * Gallery: square.stack (purple)
     * Text: doc.text (green)
     * YouTube: play.rectangle.fill (red)
     * Link: arrow.up.right (amber)
   - Title (large, up to 2 lines) + metadata below (subreddit in 
     accent color, post age, domain for link/YouTube posts)
   - Thumbnail on the right (~96x64pt, rounded) ONLY for visual 
     posts (image, video, gallery, YouTube). No thumbnail for text 
     and link posts.
   - Unwatched indicator: blue dot. Watched: subtle checkmark.

4. Keep everything else working:
   - Sort order (unwatched first, watched below, newest first)
   - "New" and "Watched" section headers
   - "You're Caught Up" row
   - Long-press context menu
   - Skeleton loading state
   - All detail views still open full-screen as before
   - Back/Menu returns to list at same position

5. Watched cards should be visually muted: dimmer thumbnail, 
   reduced title contrast, more transparent card background.

The title is the most important element in every row. It must be 
easily readable from 6-10 feet away on a TV.
```

### If the cards don't look right

```
The card rows need adjustment:
- [describe what's wrong, e.g., "the type icons are too big/small",
  "there's not enough padding inside the cards", "the thumbnails 
  are taking too much space", "the focused state isn't obvious 
  enough", etc.]
```

---

## Phase 1: Project Setup and Mock Data

### Kick off Phase 1

```
Read PRD.md. The Xcode project has already been created (SwiftUI, Swift, 
SwiftData). Let's start with Phase 1. Please:

1. Define all the data models from the PRD: Post, PostType, GalleryItem, 
   WatchedState, CachedPost, and AuthState
2. Build a MockContentProvider with realistic sample data covering every 
   post type (video, image, text, gallery, link, unsupported)
3. Create the ContentProvider protocol that both MockContentProvider and 
   the future RedditContentProvider will conform to
4. Set up the SwiftData model container for WatchedState and CachedPost
5. Create a Settings.bundle with the NSFW toggle
6. Make sure Secrets.plist is in .gitignore
```

### If you get build errors

```
I'm getting a build error. Here's what Xcode says: [paste the error]. 
Can you fix this?
```

### Verify Phase 1

```
Can you make sure the project builds for the tvOS Simulator? Walk me 
through how to run it.
```

---

## Phase 2: Browse List Screen

### Kick off Phase 2

```
Let's build Phase 2 - the browse list screen. Using the mock data from 
Phase 1, build a full-width single-column list with soft card rows.

Refer to Screen A in PRD.md for the full spec, but here's the summary:

Each row is a subtle card. From left to right:
1. Colored SF Symbol type icon in a rounded square (use the specific 
   symbols listed in CLAUDE.md - play.rectangle.fill for video, photo 
   for image, square.stack for gallery, doc.text for text, 
   arrow.up.right for link). Each icon container gets a tinted 
   background matching the content type.
2. Title (large, dominant, up to 2 lines) with subreddit, age, and 
   domain below
3. Small thumbnail on the right ONLY for posts with visual content 
   (image, video, gallery, YouTube). Skip it for text and link posts.
4. Unwatched dot (blue) or watched checkmark on the far right

Cards have a subtle background fill and border. Focused card brightens 
with a stronger border. Watched cards are more muted.

Also build:
- Sort order: unwatched first ("New" section), watched below 
  ("Watched" section), newest first in each group
- "You're Caught Up" synthetic row when all posts are watched
- Skeleton loading state for app startup
- Long-press context menu with Mark as Watched / Mark as Unwatched
- Focus behavior using tvOS native focus engine

There is NO two-pane layout or side preview panel. Selecting a row 
will open full-screen (we'll build that in Phase 3).
```

### Adjusting the visual design

```
The list looks good but I'd like some changes:
- [describe what you want changed, e.g., "the type icons are too small", 
  "I want more space between cards", "the title text is hard to read", 
  "the thumbnail should be bigger/smaller", etc.]
```

### If focus behavior isn't working right

```
The focus behavior isn't feeling right. When I swipe on the remote, 
[describe what happens]. Can you check the tvOS focus handling on the 
card rows?
```

### Testing the "Caught Up" state

```
Can you modify the mock data so all posts are marked as watched? I want 
to test the "You're Caught Up" empty state.
```

---

## Phase 3: Detail Views

### Kick off Phase 3

```
Let's build Phase 3 - all the detail views. Using mock data, build each 
detail view type:

1. Video detail - autoplay, play/pause on center click, Replay button 
   at end, mark watched at 85%
2. Image detail - full-screen image only, no overlays, mark watched 
   after 2 seconds
3. Text detail - title + scrollable body text, mark watched after 2 seconds
4. Gallery detail - in-post image navigation with left/right swipe, 
   position indicator (e.g., "2 / 5"), mark watched after 2 seconds
5. Link/fallback detail - polished info card with title, domain, excerpt
6. Media error state - clean "Media could not be loaded" message

For ALL detail views: Back/Menu must return to the gallery at the same 
scroll position and focused row.

Use a sample HLS video URL for testing video playback. Refer to Screens 
B through J in PRD.md.
```

### If video playback has issues

```
Video playback isn't working correctly. [Describe the issue - no audio, 
won't play, no controls, etc.]. The PRD notes that v.redd.it videos use 
HLS streaming. Can you check the AVKit setup?
```

### Tweaking the text detail view

```
The text post detail view needs adjustment. The text is [too small / too 
close to the edges / not scrolling properly / etc.]. Remember this needs 
to be readable from TV distance (6-10 feet).
```

### Testing watched state persistence

```
Can you verify that watched state actually persists? I want to:
1. Open a post so it gets marked as watched
2. Go back to the gallery and confirm it shows the watched indicator
3. Close and reopen the app and confirm it's still marked as watched
```

---

## Phase 3.5: Add YouTube Post Support

You've finished Phase 3, but we've since updated the PRD to handle YouTube posts specially. YouTube videos can't be played inside a tvOS app (no web view, no embeddable player), so they get their own detail view with an "Open in YouTube" button. Run this before starting Phase 4.

### Add YouTube support

```
I've updated PRD.md since we finished Phase 3. There's a new post type 
and detail view for YouTube links. Please read the updated PRD.md and 
then:

1. Add a "youtube" case to the PostType enum
2. Add a YouTubeDetailView (Screen F-1 in the PRD) that shows:
   - Large thumbnail/preview image
   - Title
   - "YouTube" badge
   - Subreddit and post age
   - A prominent "Open in YouTube" button
3. The button should try to open the YouTube app via URL scheme 
   (youtube://watch?v={videoID}), falling back to the HTTPS URL. If 
   neither works, show a brief "YouTube app not found" message.
4. Mark watched ONLY when the user taps "Open in YouTube" - not on a 
   timer like other detail views
5. Add YouTube sample posts to the MockContentProvider so we can test 
   this in the Simulator
6. Wire up the gallery so YouTube-type posts route to YouTubeDetailView
7. The gallery row should show a "YouTube" post type badge

Back/Menu returns to the gallery at the same position as always.
```

### If the YouTube deep link doesn't work in Simulator

```
The "Open in YouTube" button isn't working in the Simulator. That's 
probably expected since the Simulator doesn't have the YouTube app 
installed. Can you add a fallback so it handles the case where the 
YouTube app isn't available? It should show a brief message like 
"YouTube app not found" instead of failing silently.
```

---

## Phase 4: Reddit Integration

### Before starting Phase 4

You need your Reddit API credentials first. Use this prompt to get help setting that up:

```
Before we wire up Reddit, I need help getting my API credentials. Can you 
create the reddit-auth-setup helper script from the PRD? It should:

1. Walk me through the OAuth flow on my Mac
2. Open the browser for Reddit authorization
3. Capture the callback with the authorization code
4. Exchange it for access + refresh tokens
5. Output a ready-to-use Secrets.plist file

The Reddit app client ID is: [paste your client ID here]
The redirect URI I registered is: upvotetv://auth/callback
```

### Kick off Phase 4

```
I have my Reddit credentials in Secrets.plist. Let's build Phase 4 - 
Reddit integration:

1. Auth service that reads Secrets.plist on first launch, handles token 
   refresh, and persists rotated refresh tokens via SwiftData
2. Reddit API client for GET /user/{username}/upvoted
3. Response normalizer that handles all the Reddit API quirks:
   - v.redd.it HLS URL extraction from media.reddit_video
   - Gallery data from gallery_data + media_metadata (with HTML entity 
     decoding)
   - Image preview resolution selection (aim for ~1920px wide)
   - YouTube detection (domain contains "youtube.com" or "youtu.be") 
     classified as PostType.youtube with video ID extracted
   - Link post URL and domain extraction
   - NSFW flag mapping from over_18
4. RedditContentProvider conforming to the ContentProvider protocol
5. Auth error screen (Screen I from PRD)
6. Stale data banner (Screen J from PRD)
7. Refresh-on-launch flow with fallback to cached content

Refer to the Reddit API Integration and Authentication Architecture 
sections of PRD.md.
```

### If auth is failing

```
The Reddit auth is failing. Here's what I'm seeing: [describe the error 
or behavior]. Can you add some debug logging so we can figure out what's 
going wrong with the token refresh?
```

### If posts aren't loading correctly

```
Posts are loading from Reddit but some aren't displaying correctly. 
[Describe which types - e.g., "videos have no audio", "gallery posts 
show no images", "some image posts show a tiny thumbnail instead of the 
full image"]. Can you check the response normalizer for those post types?
```

### Testing with real data

```
The Reddit integration is working. Can you switch the app from 
MockContentProvider to RedditContentProvider so I can test with my 
real upvoted posts?
```

---

## Phase 5: Polish and Edge Cases

### Kick off Phase 5

```
Let's do Phase 5 - polish pass. Please work through:

1. Rate limit handling - respect Reddit's X-Ratelimit headers, retry 
   once on 429
2. NSFW filtering - read the Settings.bundle preference and hide NSFW 
   posts when disabled
3. Debug diagnostic overlay for dev builds (auth status, last refresh, 
   API errors)
4. Image memory optimization - make sure we're not loading full-res 
   originals into memory
5. Visual polish - consistent typography, spacing, focus animations, 
   smooth transitions
6. Test all error states: auth failure, network failure, media load 
   failure, empty states
```

### If the app feels slow

```
The app feels sluggish when [describe when - scrolling the list, opening 
detail views, loading images, etc.]. Can you profile what's happening 
and optimize it? The PRD targets instant-feeling focus movement and 
preview updates within ~200ms.
```

### Final visual adjustments

```
I want to do a final visual pass. Here are the things I'd like adjusted:
- [list your visual tweaks]
```

---

## Phase 6: Auth Setup Tooling

### Kick off Phase 6

```
Let's build the auth setup helper script for Phase 6. This should be a 
Mac command-line tool or script that:

1. Takes my Reddit client ID as input
2. Opens my browser to the Reddit authorization page
3. Starts a local HTTP server to capture the redirect callback
4. Exchanges the authorization code for access + refresh tokens
5. Writes a Secrets.plist file I can drop into the Xcode project

Make it simple and well-documented since I'll need to run this again 
whenever my refresh token chain breaks.
```

---

## General Purpose Prompts

These are useful throughout the project, not tied to a specific phase.

### When something doesn't look right

```
Here's a screenshot of what I'm seeing: [paste or describe]. 
This doesn't look right because [explain what you expected]. 
Can you fix it?
```

### When you want to test a specific scenario

```
How do I test [specific scenario - e.g., "what happens when the network 
is offline", "what happens when a video fails to load", "what the app 
looks like with only 3 posts"]? Can you set up the mock data or 
conditions for this?
```

### When you want to understand what was built

```
Can you give me a plain-English summary of what [specific file or 
feature] does? I want to understand it at a high level without needing 
to read the code.
```

### When you want to switch between mock and real data

```
Can you add a way to easily switch between MockContentProvider and 
RedditContentProvider? I want to be able to go back to mock data 
for testing without changing code every time.
```

### When Xcode shows warnings

```
Xcode is showing these warnings: [paste warnings]. Are any of these 
important? If so, can you fix them?
```

### When you want to commit your progress

```
Let's commit what we have so far. Can you create a git commit with 
a good message describing what we built?
```

### When you want to run the app

```
How do I run this in the tvOS Simulator right now? Walk me through 
the steps.
```

### When you need to redo something

```
I don't like how [feature/screen] turned out. Can we start that part 
over? Here's what I want instead: [describe what you want].
```

### When the refresh token breaks

```
My Reddit refresh token stopped working. The app is showing the auth 
error screen. Can you help me run the auth setup script to get a new 
token?
```

---

## Tips for Prompting Claude Code

**Be specific about what you see.** Instead of "it looks wrong," say "the thumbnail is stretched horizontally and the title text is cut off after one line instead of two."

**Reference the PRD.** If Claude Code drifts from the spec, you can say "Check Section X in PRD.md - it should work like [this]."

**One phase at a time.** Don't try to do multiple phases in one prompt. Finish one, make sure it works, then move on.

**Test before moving on.** After each phase, ask Claude Code to help you verify things work before starting the next phase.

**It's okay to say "undo that."** If a change makes things worse, just tell Claude Code to revert it. That's normal.

**Screenshots help.** If you can describe or screenshot what you're seeing, Claude Code can fix things much faster than if you just say "it's broken."
