# iOS Companion App + Share Extension

Introduced in v3.2, replacing the v3.1 iOS Shortcut approach. The Shortcut was fragile (undebuggable UI configuration, inconsistent behavior between iOS and Mac Shortcuts), so we ship a small native iOS app + Share Extension instead.

## What ships

Two new Xcode targets alongside the tvOS app:

| Target | Product | What it does |
|---|---|---|
| `Upvote TV Mobile` | `com.justinnikolaus.Upvote-TV-Mobile` | Container app. One screen: explainer + "Test Connection" button. Required for the extension to install. |
| `Upvote TV Share` | `com.justinnikolaus.Upvote-TV-Share` | iOS Share Extension. Shows up in Share Sheets when you share a URL. Does the actual work. |

Both targets are in `Upvote TV.xcodeproj` and share Swift code via the top-level `Shared/` folder.

## User flow

1. User is in Safari (or Reddit app, or YouTube app, or anywhere that shares URLs).
2. Taps Share → Upvote TV.
3. Extension modal appears showing "Adding to Upvote TV…" with a spinner.
4. 1-2 seconds later: "Added" (green check) for a new item, "Already Queued" (blue check) if duplicate, or an error state.
5. Modal auto-dismisses ~1.2 seconds after success.
6. Apple TV app picks up the new item within ~1 second of next queue fetch.

## First-time setup on a new iPhone

### Prerequisites

- Mac running Xcode with the Upvote TV project.
- The iPhone you want to install on.
- You've completed [Gist-Setup.md](./Gist-Setup.md) and have a populated `Secrets.plist`.

### Steps

1. **Plug the iPhone into your Mac** with a USB cable. (Wireless debugging also works but USB is more reliable for first install.)
2. **Trust the computer:** on the iPhone, tap "Trust" when prompted, and enter your passcode.
3. **In Xcode:** at the top, select the `Upvote TV Mobile` scheme and pick your iPhone as the run destination.
4. **Xcode → Product → Run** (⌘R).
5. If Xcode complains about the provisioning profile missing your device, click the suggested "Register Device" button in the signing warning. With a paid Apple Developer Program membership, Xcode auto-registers your iPhone's UDID. Wait ~10 seconds for the profile to refresh and run again.
6. On the iPhone: if you see a "Untrusted Developer" warning, go to **Settings → General → VPN & Device Management → Developer App** and trust your Apple ID. (This step is not usually needed with a paid team — Xcode's code signing handles it automatically.)

After install, the `Upvote TV` app icon appears on the home screen. Open it once and tap **Test Connection** to verify the PAT reaches GitHub.

### The Share Extension appears in share sheets automatically

You don't need to explicitly enable it. Next time you tap Share in Safari or another app, scroll through the row of app icons — "Upvote TV" is there. Tap it to test.

If it doesn't show up: tap the ⋯ "More" button in the share sheet, find Upvote TV in the list, toggle it on, and optionally drag it higher in the order for faster access.

## Distributing to other household iPhones

The paid Apple Developer Program lets you distribute via TestFlight to up to 10,000 "external" testers and an unlimited number of "internal" testers (members of your own developer team). For a 2-person household, **internal testing via TestFlight** is the cleanest path.

### One-time setup

1. Log in to [App Store Connect](https://appstoreconnect.apple.com).
2. Add the other household member's Apple ID as a user on your team with the "App Manager" or "Developer" role.
3. Create an App Store Connect record for `Upvote TV Mobile` (bundle ID `com.justinnikolaus.Upvote-TV-Mobile`).

### Per-release

1. In Xcode: Product → Archive (with the `Upvote TV Mobile` scheme, destination "Any iOS Device").
2. Archive organizer opens. Click **Distribute App** → **App Store Connect** → **Upload**.
3. Wait 5–15 min for Apple to process the build.
4. In App Store Connect → TestFlight → Internal Testing: add the build, add your household member.
5. They install **TestFlight** from the App Store if they haven't already, then accept the invite email on their iPhone.

Internal testers don't require Apple review — builds are available to them as soon as processing completes.

## Development loop (for the maintainer)

- **Iterate on the Share Extension:** run the `Upvote TV Mobile` scheme on the iPhone. Even though you're "launching" the main app, the extension is installed alongside it. Test by sharing a URL from Safari.
- **Debugging the extension:** set the `Upvote TV Share` scheme as the active scheme, run it, and pick "Safari" as the host app when Xcode prompts. Xcode attaches the debugger when you trigger the share sheet.
- **Logs:** the extension uses the same `com.justinnikolaus.Upvote-TV` logger subsystem as the tvOS app (via `OSLog`). Filter in Console.app.

## Architecture notes

- `ShareViewController` (UIKit) is the extension's principal class. It pulls the first URL attachment from the `NSExtensionContext` and hosts a SwiftUI view (`ShareRootView`) via `UIHostingController`.
- `ShareRootView` is a state machine: `working → success | duplicateNotice | failure`. The `runShare()` async function is the whole business logic.
- URL classification uses the shared `URLClassifier.classify(url:)` — same function the tvOS-side Reddit resolver uses to detect YouTube-linked Reddit posts.
- Gist I/O uses the shared `GistQueueClient`. Identical code to tvOS.
- `Secrets.plist` is bundled into the extension as a symlink to `Upvote TV/Upvote TV/Secrets.plist`. One file, one token, all three targets.

## Known limitations

- **Race condition:** two iPhones sharing at the same second can lose one of the writes (last-writer-wins on the Gist PATCH). Accepted per PRD.
- **No history view yet:** the Mobile app doesn't show recent shares. Could be added later by reusing the tvOS `Post` + metadata-resolver code.
- **iOS 17+ only:** the Share Extension uses `symbolEffect` and other iOS 17 APIs for its success animation. Older iOS versions would require stripping the modifier.
