# iPhone Shortcut Specification — DEPRECATED

> **Superseded by [iOS-App.md](./iOS-App.md) as of v3.2.**
>
> The Shortcut approach was abandoned because Shortcuts.app proved too fragile for the required logic:
>
> - No useful debugging (opaque error states, no step-through).
> - URL-binding behavior differs subtly between Mac and iOS Shortcuts.
> - Permission dialogs (e.g., cross-app Chrome access) appear for non-obvious reasons, breaking the happy path.
> - Every config change requires UI clicking, no version control.
>
> The replacement is a native iOS app target (`Upvote TV Mobile`) with a Share Extension (`Upvote TV Share`). Same `GistQueueClient` Swift code that the tvOS app uses, same `URLClassifier`, proper debugging, checked into git.
>
> This doc is left in place as a historical record of the attempted approach. **Do not build the Shortcut.** See `docs/iOS-App.md` instead.
