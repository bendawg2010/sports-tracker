# Contributing to Sports Tracker

Thanks for considering it. Sports Tracker is a one-person hobby project, so contributions are genuinely appreciated.

## Issues

Open one for anything:

- **Bug reports** — Please include your macOS version, Sports Tracker version (in the app's About panel), and a short repro. Screenshots help. Crash logs help even more.
- **Feature requests** — Tell me the use case, not just the feature. "I want to track Liga Argentina" beats "add more soccer leagues."
- **Sport requests** — If ESPN's public API has it, I can probably add it. If they don't, it's a much bigger project.

## Pull requests

PRs are welcome — including big ones, but it's worth opening an issue first for anything substantial so we don't end up with a wasted weekend.

Quick checklist:

- Run the app locally and confirm your change actually does the thing.
- Keep the diff focused — one PR, one concern.
- Don't introduce third-party Swift packages without a really good reason. The "no dependencies" thing is intentional; it keeps the binary small and the supply chain narrow.
- Match the existing code style. We use Swift's standard formatting; no custom rules.

## Tests

Tests are appreciated but not required for every change. The codebase has light test coverage focused on data parsing and the trickier pure functions (win probability calculations, score formatting, etc.). If you're touching one of those areas, a test for the new behavior is a great addition.

Run tests with Cmd+U in Xcode, or from the command line:

```bash
xcodebuild test -scheme SportsTracker -destination 'platform=macOS'
```

## Style notes

- **SwiftUI first** — Drop down to AppKit only when SwiftUI genuinely can't do it (menu bar status item, floating windows, the ticker overlay).
- **Plain values, not magic types** — Prefer `struct` over `class`, `let` over `var`, value semantics over reference juggling.
- **Comment the "why," not the "what"** — Especially for anything ESPN-API-shaped, since their schema is undocumented and full of surprises.
- **No emojis in code or commits.** The README and INSTALL.md are different — emojis are fine in user-facing markdown.
- **Async/await, not callbacks.** All new networking should use `async`.

## Releases

I cut releases roughly when there's enough new stuff to justify it. If your PR adds something user-visible, mention it in the PR description so it makes the release notes.

## Code of conduct

Be decent. The project is small enough that this is the whole policy.

## Questions

Open an issue tagged `question`, or just ping me on the discussion in your PR.
