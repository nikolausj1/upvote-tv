---
title: "Upvote TV - Claude Code Prompt Guide"
created: 2026-04-10
modified: 2026-04-17
version: 3.0
author: Claude Opus 4.7 (claude-opus-4-7)
tags:
---

# Upvote TV - Claude Code Prompt Guide

A reference of prompts to use when building Upvote TV with Claude Code. Copy and paste these as you work through each phase. You don't need to use them word-for-word, adjust based on what's happening in your project at the time.

---

## Current Project Status (as of v3.0 of this guide)

Phases 1-3 and parts of Phase 5 were previously completed against the v2 PRD, which assumed Reddit API as the data source. The strategy changed in v3 of the PRD: the app now reads from an iCloud-backed queue file populated by an iPhone Shortcut. Reddit API integration is deferred indefinitely.

| Phase | Description | Status as of 2026-04-17 |
|-------|-------------|--------|
| 1 | Data models, providers, SwiftData setup | Done (v2 models, needs migration) |
| 2 | Browse list UI with mock data | Done |
| 3 | All detail views (video, image, text, gallery, YouTube, link) | Done |
| 4 (v2 Reddit) | Reddit API integration | Abandoned (Reddit API approval never granted) |
| 4 (v3 new) | iCloud queue integration + metadata resolvers | Not started |
| 5 (v2 polish) | NSFW toggle, debug overlay, memory optimization | Done (mock-data only) |
| 5 (v3 new) | iOS Shortcut | Not started |
| 6 | Polish and edge cases for queue model | Not started |
| 7 | Reddit API (deferred, optional) | Not started |

**The next prompt to run is the Migration prompt below, followed by Phase 4 (v3).**

---

## Before You Start

When you open the Upvote TV folder in Claude Code, it will automatically read the CLAUDE.md file. CLAUDE.md has been updated to reflect v3, but the actual codebase still contains v2 Reddit-specific files. Your first message should orient it to both the updated PRD and the cleanup work that needs to happen.

---

## Migration: v2 to v3 Architecture

Run this FIRST, before any Phase 4 work. The codebase was built against v2's Reddit-API assumptions. This migration updates data models, removes Reddit-specific files that no longer apply, and adds the new Queue types needed for v3.

### Migrate existing code to v3 architecture

```
The PRD has changed significantly. Please re-read PRD.md (now v3.0) and 
CLAUDE.md. The core shift: we're no longer planning to use the Reddit 
API as the primary data source. Instead, content comes from an 
iCloud-backed queue file populated by an iPhone Shortcut.

Please do the following migration work. Do NOT build Phase 4 yet - just 
clean up the existing code so it matches the new architecture.

1. Add new data models:
   - QueueItem (id, url, source, sharedAt)
   - QueueSource enum (.reddit, .youtube)

2. Update the Post model:
   - Add optional sharedAt: Date?
   - Make subreddit and author optional (YouTube items don't have them)
   - Add resolvedAt: Date? for cache freshness tracking

3. Update CachedPost (SwiftData) to include resolvedAt.

4. Remove the AuthState SwiftData model entirely. Also remove any 
   migration code that references it.

5. Move these files to a /Deferred folder at the project root (keep the 
   code around for Phase 7 but remove from the active build target):
   - Services/AuthService.swift
   - Services/RedditAPIClient.swift
   - Services/RedditResponseParser.swift
   - Providers/RedditContentProvider.swift
   - Tools/reddit-auth-setup.sh
   
   These files should no longer compile into the app. Either remove 
   them from the Xcode target membership or delete them (I'd prefer 
   moving to /Deferred so we can bring them back for Phase 7 if Reddit 
   approval ever comes through).

6. Delete App/Secrets.plist if it exists locally. Update .gitignore if 
   needed to keep it excluded for Phase 7.

7. Update MockContentProvider to include:
   - Direct YouTube queue items (not just Reddit posts that link to 
     YouTube). Examples: a Short, a full-length video, a live stream.
   - All mock items should have a sharedAt timestamp populated.
   - Sort order in mock data should be newest-sharedAt first.

8. Update PostCardRow and the list sort logic to use sharedAt (falling 
   back to createdAt) for "newest first" ordering.

9. Update any UI that displays "subreddit" to handle the YouTube case 
   gracefully - for YouTube items, show the channel name (author) and 
   "YouTube" as the source label instead.

10. Confirm the app still builds and runs against mock data after these 
    changes. The browse list, all detail views, and watched state 
    should all still work.

Do not add QueueContentProvider, iCloud integration, or the metadata 
resolvers yet - that's Phase 4 work, which comes next.
```

### Verify the migration

```
Can you walk me through what changed in the migration? I want to confirm:
- What files were moved to /Deferred
- What new models exist
- That the app still builds and runs with mock data
- That the browse screen and all detail views still work
```

---

## Phase 4 (v3): iCloud Queue Integration

This replaces the original Phase 4 (Reddit API). It wires up the real data source: a queue.json file in an iCloud container, hydrated by calls to public web endpoints.

### Before starting Phase 4

You need to configure the iCloud capability in Xcode first:

```
Before we build the QueueContentProvider, I need to configure the iCloud 
capability in Xcode. Can you walk me through the exact steps in Xcode 
to:

1. Enable the iCloud capability for the Upvote TV target
2. Check "iCloud Documents" under services
3. Configure a ubiquity container identifier 
   (iCloud.com.justinnikolaus.Upvote-TV)
4. Verify the entitlements file is updated correctly
5. Confirm the container is visible in the Apple Developer portal

I want to make sure this is set up right before we start writing code 
that depends on it.
```

### Kick off Phase 4

```
Let's build Phase 4 of v3: the iCloud Queue integration. Using the 
architecture in PRD.md (Architecture Overview, Queue File Specification, 
and Metadata Resolution sections), please build:

1. QueueFileReader - reads queue.json from the iCloud ubiquity container.
   Handles the file-not-found case gracefully.

2. QueueFileWriter - atomic writer (temp file + rename) for queue.json.
   Used later by the "Remove from Queue" context menu action.

3. RedditMetadataResolver - takes a QueueItem with source=.reddit and 
   fetches https://www.reddit.com/comments/{id}.json (no auth). Parses 
   the response into a Post using the same normalizer logic originally 
   planned for RedditContentProvider. Handles all post type variants:
   - v.redd.it video (extract hls_url from media.reddit_video)
   - Gallery (gallery_data + media_metadata, HTML-decoded URLs)
   - Image (preview.images, resolution closest to 1920px wide)
   - Text (selftext)
   - YouTube-domain Reddit posts (classify as PostType.youtube)
   - Link (url_overridden_by_dest)

4. YouTubeMetadataResolver - takes a QueueItem with source=.youtube 
   and fetches https://www.youtube.com/oembed?url={url}&format=json. 
   Returns a Post with postType=.youtube, title, author, thumbnailURL.

5. MetadataCache - SwiftData-backed cache for resolved Posts with 
   24-hour freshness. On hydration, items with fresh cache skip 
   the network call.

6. QueueContentProvider - conforms to ContentProvider. Orchestrates:
   - Read queue file
   - For each item, check cache, fetch if stale/missing
   - Return fully hydrated [Post] to UI
   - Up to 10 concurrent fetches, 10-second per-request timeout
   - Failed items return as a fallback Post with PostType.unsupported 
     and the raw URL visible

7. Update the app entry point (UpvoteTVApp or equivalent) so it uses 
   QueueContentProvider in release and debug builds against real 
   iCloud. Keep MockContentProvider for SwiftUI previews.

8. Add the Setup Required state (Screen I in PRD) - shown when the 
   iCloud container can't be accessed.

9. Add the Empty Queue state (Screen A-2 in PRD) - shown when queue.json 
   is missing or has zero items. Should poll for the file every 10 
   seconds while visible.

10. Add the stale metadata badge per post (when cache is stale and 
    refresh failed).

11. Wire up the "Remove from Queue" action in the long-press context 
    menu so it rewrites queue.json via QueueFileWriter and removes 
    the CachedPost from SwiftData.

Do NOT build the iOS Shortcut yet - that's Phase 5. For testing this 
phase, you can manually create a queue.json file with sample entries 
and drop it into the iCloud container via the Files app on a Mac.
```

### Testing Phase 4 with a hand-written queue.json

```
Before we build the Shortcut, let's test the QueueContentProvider with 
a manually-created queue file. Can you:

1. Give me the exact file path where queue.json should live for testing 
   on my Mac (the iCloud container Documents folder)
2. Provide a sample queue.json with a few Reddit posts and YouTube 
   videos so I can drop it in and see the app hydrate it
3. Explain how to trigger the app to re-read the file after I edit it
```

### If iCloud access isn't working

```
The app is showing the Setup Required state but I AM signed into iCloud 
and iCloud Drive is enabled. Can you add debug logging to figure out 
what's going wrong with the ubiquity container access? What's the exact 
error or nil return from NSFileManager?
```

### If metadata fetches are failing

```
Queue items are loading but some aren't resolving. [Describe what - 
"all Reddit posts return errors", "YouTube items load but Reddit 
doesn't", "some post types fail", etc.]. Can you add logging to the 
metadata resolvers so we can see what the actual HTTP response looks 
like?
```

### If `reddit.com/comments/{id}.json` is now gated

```
Fetching Reddit metadata is failing with a 403 or similar. It looks 
like the public JSON endpoint may now require auth. Please:
1. Confirm the failure mode (status code, response body)
2. Check if there's a different public endpoint we can use 
3. If none works, we'll need to reconsider the strategy - flag this 
   to me as a blocker and don't try workarounds yet
```

---

## Phase 5 (v3): iOS Shortcut

### Kick off Phase 5

```
Let's build the iOS Shortcut that captures shared URLs into the queue 
file. Refer to the Capture Mechanism (iOS Shortcut) section of PRD.md.

I'll build the Shortcut in the iOS Shortcuts app myself, but I need 
your help to plan the exact sequence of actions. Please produce:

1. A step-by-step list of the Shortcuts actions to add, in order, with 
   settings for each. This should cover:
   - Accept shared URL from share sheet
   - Domain validation (whitelist: reddit.com and subdomains, redd.it, 
     youtube.com and subdomains, youtu.be). Reject everything else with 
     a user-facing error.
   - URL normalization (per the rules in PRD Section "Validation and 
     Normalization")
   - Post/video ID extraction
   - Read queue.json from the iCloud container (give me the exact path 
     to use in the "Get File" action)
   - Parse JSON
   - Duplicate check by id + source
   - Append new entry with current ISO8601 timestamp
   - Write queue.json back atomically
   - Show success or error haptic/toast

2. Any JavaScript / Run Script actions needed for URL parsing or JSON 
   manipulation that's beyond what Shortcuts can do natively.

3. Guidance on how to test each step incrementally while building.

4. A brief user-facing setup doc I can keep with the Shortcut: "How 
   Justin (or wife) installs and uses the Upvote TV Shortcut."
```

### Distributing the Shortcut to both phones

```
The Shortcut works on my phone. Now I want to install it on my wife's 
phone too. What's the best way to share it so both phones are writing 
to the same queue.json? Options I know of: iCloud share link, AirDrop, 
exported .shortcut file. Please recommend and explain any caveats.
```

### If the Shortcut can't read the queue file

```
The Shortcut errors out at the "Get File" step. It can't access the 
Upvote TV iCloud container. Is this a capability issue, a path issue, 
or something else? Can you walk me through how to verify the container 
is visible to the Files app first?
```

### If atomic writes aren't working

```
Sometimes the queue file ends up truncated or malformed after a share, 
especially if I share quickly or multiple times in a row. It looks like 
the write isn't atomic. Can you adjust the Shortcut's write step to be 
more resilient?
```

---

## Phase 6 (v3): Polish and Edge Cases

### Kick off Phase 6

```
Let's do Phase 6 - polish pass on the queue model. Please work through:

1. NSFW filtering - read the Settings.bundle preference and hide NSFW 
   posts when disabled. Applies ONLY to Reddit items (over_18 flag). 
   YouTube items don't have an NSFW flag - just keep them visible.

2. Debug diagnostic overlay (dev builds only) - show:
   - Queue file path and last modified time
   - Number of items in queue, number cached fresh, number stale
   - Last metadata resolution attempt per source (Reddit, YouTube) 
     with success/fail counts

3. Cache eviction - if the queue has items removed from it (via the 
   tvOS "Remove from Queue" action or via the Shortcut not being able 
   to remove, just via bulk edit of the JSON file), orphan CachedPost 
   entries should eventually be pruned. Add a pass on launch that 
   deletes any CachedPost whose id+source isn't in the current queue.

4. Image memory optimization - make sure we're not loading full-res 
   originals into memory. Reddit's preview.images array should give us 
   a resolution close to 1920px wide; use that.

5. Visual polish - consistent typography, spacing, focus animations, 
   smooth transitions across both Reddit and YouTube item types.

6. Test all error states: 
   - Queue file missing
   - iCloud unavailable
   - Individual metadata fetch failure (Reddit and YouTube)
   - Media load failure per post type
   - Empty queue
   - All items watched ("You're Caught Up")
   - Mixed fresh + stale cache
```

### If the app feels slow

```
The app feels sluggish when [describe when - scrolling the list, opening 
detail views, loading images, etc.]. Can you profile what's happening 
and optimize it? The PRD targets instant-feeling focus movement and 
cached items rendering within 500ms of shell appearance.
```

### Final visual pass

```
I want to do a final visual pass. Here are the things I'd like adjusted:
- [list your visual tweaks]
```

---

## Phase 7 (Optional, Deferred): Reddit API Provider

Only run this if Reddit API access is eventually approved under the 
Responsible Builder Policy. Until then, Phase 7 is not prioritized.

### If/when Reddit approves API access

```
Reddit API access has been approved. Let's restore the deferred Reddit 
code and integrate it as a supplemental provider.

1. Move these files back from /Deferred into the active target:
   - Services/AuthService.swift
   - Services/RedditAPIClient.swift
   - Services/RedditResponseParser.swift
   - Providers/RedditContentProvider.swift
   - Tools/reddit-auth-setup.sh

2. Update them as needed to match the current data models (Post now 
   has sharedAt, etc.).

3. Build the OAuth helper script and generate a Secrets.plist. My 
   Reddit client ID is [paste].

4. Update the app so the user (me, in a debug setting or similar) can 
   choose between:
   - QueueContentProvider only (current default)
   - RedditContentProvider only (fetch 100 upvotes, ignore queue)
   - Hybrid (merge both sources, dedup by ID)

Refer to PRD.md Phase 7 for the architectural decision there.
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
How do I test [specific scenario - e.g., "what happens when the queue 
file is empty", "what happens when a YouTube fetch fails", "what the 
app looks like with 50 items", "what happens when iCloud is offline"]? 
Can you set up the mock data or conditions for this?
```

### When you want to understand what was built

```
Can you give me a plain-English summary of what [specific file or 
feature] does? I want to understand it at a high level without needing 
to read the code.
```

### When you want to switch between mock and real data

```
Can you add a debug toggle to switch between MockContentProvider and 
QueueContentProvider without changing code each time? A launch argument 
or a hidden settings flag would both work.
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
the steps, including how to get a queue.json into the right place for 
the Simulator to see it.
```

### When you need to redo something

```
I don't like how [feature/screen] turned out. Can we start that part 
over? Here's what I want instead: [describe what you want].
```

### When the iCloud queue file gets corrupted

```
The queue.json file seems to be corrupted. The app either won't load 
or skips entries. Can you:
1. Help me inspect the current file contents
2. Diagnose the corruption (invalid JSON, missing fields, etc.)
3. Decide whether to repair in place or reset and rebuild from scratch
```

### When a share from iPhone isn't appearing on the TV

```
I shared a [Reddit post / YouTube video] from my iPhone about [time 
ago] but it's still not showing up on the TV. Can you help me debug 
whether the problem is:
- The Shortcut didn't write to the file
- iCloud hasn't synced yet
- The Apple TV is reading a stale cache
- Something else
```

---

## Tips for Prompting Claude Code

**Be specific about what you see.** Instead of "it looks wrong," say "the thumbnail is stretched horizontally and the title text is cut off after one line instead of two."

**Reference the PRD.** If Claude Code drifts from the spec, you can say "Check Section X in PRD.md, it should work like [this]."

**One phase at a time.** Don't try to do multiple phases in one prompt. Finish one, make sure it works, then move on.

**Test before moving on.** After each phase, ask Claude Code to help you verify things work before starting the next phase.

**Migration steps need extra care.** The v2 to v3 migration touches working code. Always verify the app still builds and runs after each migration sub-step before moving to the next.

**It's okay to say "undo that."** If a change makes things worse, tell Claude Code to revert it. That's normal.

**Screenshots help.** If you can describe or screenshot what you're seeing, Claude Code can fix things much faster than if you just say "it's broken."

**iCloud is slow sometimes.** When testing the queue flow end-to-end, give iCloud Drive 30 seconds or so to sync from iPhone to Apple TV. If nothing shows up after a minute, then debug.
