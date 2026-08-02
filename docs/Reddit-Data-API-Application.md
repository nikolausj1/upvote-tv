---
title: "Reddit Data API Application Draft"
created: 2026-08-02
modified: 2026-08-02
version: 1.0
author: Claude Opus 5 (claude-opus-5)
tags:
---

# Reddit Data API Application Draft

A submission-ready draft for reapplying to Reddit's Data API under the Responsible Builder Policy. The first application was denied with "lacks necessary details", which is a fixable rejection: the reviewer needs a concrete picture of what is fetched, how often, where it goes, and who sees it. Everything below is specific on those points.

**Justin submits this himself** at <https://support.reddithelp.com/hc/en-us/requests/new> (choose the Data API / API access request category). Review the numbers before sending, and adjust the queue size if it has changed.

---

## Why reapply

Approval would restore what was lost when `reddit.com/comments/{id}.json` was gated:

- gallery posts (currently unresolvable),
- the `over_18` flag, so NSFW filtering can apply to Reddit items rather than YouTube only,
- score, and
- a documented, stable rate limit instead of an undocumented per-IP unit budget shared with every other Reddit client on the household network.

If it is denied again, nothing breaks. The RSS path stays as-is.

---

## Draft answers

### What are you building?

Upvote TV is a private, personal Apple TV app used by one household (currently 2 people, 2 devices). It is a shared "watch later" queue, not a Reddit client. Nobody outside the household can install it. It is not on the App Store, has no public distribution, no website, and no users beyond the household. It is built and signed with a personal Apple developer account.

The workflow is: someone finds a Reddit post on their iPhone and taps Share, which adds the post's URL to a private queue. In the evening the Apple TV displays that queue so the household can watch the items together on the television.

### What Reddit data do you access, and what do you do with it?

For each post explicitly shared by a household member, and only for those posts, the app fetches:

- the post title,
- the subreddit name,
- the post author's username,
- the publish timestamp,
- the preview thumbnail URL,
- and, for Reddit-hosted video, the HLS stream URL so the video plays in the app.

Nothing else is fetched. The app does not browse, search, crawl, or enumerate. It never reads listings, subreddits, feeds, comments, user profiles, or messages. It only ever requests posts a household member deliberately shared, by ID.

### How much traffic will this generate?

Very little, and it is bounded by human behaviour rather than by a loop.

- The queue currently holds 59 posts, accumulated over roughly three months.
- New posts are added at roughly 5 to 15 per week, one request each, at the moment a person taps Share.
- Post metadata is cached locally for 30 days, so an existing item is re-fetched at most once a month. Titles, subreddits, and authors are immutable, so even that is mostly precautionary.
- Steady state is on the order of tens of requests per week, single-digit concurrency, from one household IP.

The existing implementation already reads `x-ratelimit-remaining` and `x-ratelimit-reset` and pauses until the window resets rather than retrying into a 429. That behaviour would carry over to the authenticated API.

### Where is the data stored, and for how long?

- Post metadata is cached on the Apple TV in a local SwiftData store, for 30 days.
- The queue itself (a list of URLs) lives in a private GitHub Gist that only the household's token can read or write.
- Data is deleted when an item is removed from the queue.
- No data is stored on any server we operate, because there isn't one.

### Who can see the data?

Only the two people in the household, on their own devices. There is no sharing, publishing, syndication, or export.

### Do you monetize, advertise, or train models on this data?

No to all three. There is no revenue, no advertising, no analytics, no third-party SDKs, and no use of any Reddit content for training or evaluating machine learning models. The app has no telemetry of any kind.

### How do you attribute Reddit content?

Each item displays its subreddit (as `r/subreddit`) and links back to the original post. The app deliberately carries no Reddit branding, logos, or colors, so it is never mistaken for an official Reddit client.

### Compliance

- Requests are made with a descriptive User-Agent identifying the app and contact.
- Rate limit headers are respected, with a shared governor that pauses rather than retries.
- Deleted or removed posts are detected and shown as unavailable rather than cached indefinitely.
- Content is not redistributed outside the household.
- If access is granted and later revoked, the app degrades to its current unauthenticated behaviour.

---

## Notes for submission

- Keep the tone factual and specific. The previous denial was about missing detail, not about the use case.
- Do not overstate the user base. "One household, two people" is the strongest fact in this application, because it makes the request obviously low risk.
- If Reddit asks for a company or organization, say personal / individual developer rather than inventing one.
- If there is a field for expected queries per minute, answer with a low single-digit number and note that it is bursty only when the TV app first populates, which happens rarely because of the 30-day cache.
