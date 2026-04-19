# GitHub Gist Setup

Upvote TV stores its shared queue as a single JSON file in a secret GitHub Gist. This is a one-time setup per household.

Takes about 5 minutes.

## 1. Create the secret gist

1. Go to https://gist.github.com while signed into GitHub.
2. **Filename:** `queue.json`
3. **Content** (paste exactly):
   ```json
   {
     "version": 1,
     "items": []
   }
   ```
4. Click **Create secret gist** (not "Create public gist"). Secret gists are unlisted — only people with the URL can find them.
5. On the gist page, copy the **gist ID** from the URL. The URL looks like:
   ```
   https://gist.github.com/YOUR_USERNAME/abc123def4567890abcdef
                                         └─────── this part ─────┘
   ```
   That trailing hex string is your `GistID`. Keep it handy.

## 2. Create a fine-grained Personal Access Token

1. Go to https://github.com/settings/personal-access-tokens/new
2. **Token name:** `Upvote TV`
3. **Resource owner:** your personal account.
4. **Expiration:** 1 year (max allowed; you'll rotate yearly).
5. **Repository access:** doesn't matter — leave as the default ("Public Repositories (read-only)").
6. **Permissions → Account permissions → Gists:** change to **Read and write**.
7. Leave every other permission at No access.
8. Click **Generate token** at the bottom.
9. **Copy the token immediately** — it's shown only once. Starts with `github_pat_…`.

## 3. Wire up the tvOS app

1. In Xcode, in the `Upvote TV` target, find `Secrets.example.plist` and duplicate it in place:

   ```bash
   cd "Upvote TV/Upvote TV"
   cp Secrets.example.plist Secrets.plist
   ```

2. Open `Secrets.plist` and paste:
   - `GistID` → the ID from step 1
   - `GistToken` → the `github_pat_…` token from step 2
3. Save. `Secrets.plist` is gitignored so you won't accidentally commit it.
4. Build & run. If the values are right, the app boots directly to **Empty Queue** (polling every 10s). If `Secrets.plist` is missing or the values are wrong, the app shows **Connection Error** with a debug panel showing what's missing.

## 4. Smoke test without the iPhone app

To verify the tvOS side end-to-end before installing the iOS companion app, hand-edit the gist once:

1. Open your secret gist on github.com → click **Edit**.
2. Replace the content with a test queue that includes one Reddit post and one YouTube video. Example:

   ```json
   {
     "version": 1,
     "items": [
       {
         "id": "1abc2de",
         "url": "https://www.reddit.com/comments/1abc2de",
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

   Replace the Reddit id with a real short post id from a recent Reddit URL.
3. Click **Update secret gist**.
4. Relaunch Upvote TV. The list should populate with both posts within a second or two.

## 5. Next step

Once the tvOS side works, install the iOS companion app + Share Extension on any iPhone in the household so you don't have to hand-edit the gist every time you share something. See [iOS-App.md](./iOS-App.md).

## Token rotation

GitHub caps fine-grained PATs at 1-year expiration. When your token nears expiry GitHub will email you a reminder. When it happens:

1. Generate a new token (step 2 again).
2. Update `GistToken` in `Secrets.plist` (one file; iOS targets symlink to it).
3. Rebuild and reinstall all three targets (tvOS, iOS Mobile, Share Extension).

If the token expires before rotation, tvOS shows the Connection Error screen and the Share Extension shows "Token rejected. It may have expired."
