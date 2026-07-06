# Contributing to MoodleLens

Contributions are welcome, especially focused bug fixes and small runtime UX improvements.

## Report a bug

Open an issue with:

- MoodleLens version and macOS version.
- Provider mode: OpenAI API key or Codex CLI.
- Steps to reproduce.
- Expected behavior and actual behavior.
- Whether Screen Recording, Accessibility, or Input Monitoring is granted.
- Screenshots or logs only if they do not expose secrets, private windows, API keys, or prompts.

## Request a feature

Open an issue first for non-trivial changes. Include:

- The workflow you are trying to improve.
- Why current Settings, hotkeys, or Ask mode do not cover it.
- Any privacy, permissions, or screen-recording implications.

## Pull requests

Keep PRs focused. A good PR changes one behavior, includes a clear description, and updates docs when user-facing behavior changes.

Before opening a PR, run:

```bash
xcodebuild test \
  -project MoodleLens.xcodeproj \
  -scheme MoodleLens \
  -destination 'platform=macOS' \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO
```

```bash
scripts/verify-local.sh
```

For release-path changes, also run:

```bash
scripts/package-share.sh v1.0.0
hdiutil verify dist/MoodleLens-v1.0.0-macos.dmg
```

## AI-assisted code

MoodleLens is heavily AI-assisted. Please review generated changes carefully, keep diffs small, and prefer boring native macOS APIs over new dependencies.

By contributing, you agree that your contribution is licensed under the project MIT license.
