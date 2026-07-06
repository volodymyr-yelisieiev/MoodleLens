# MoodleLens Verification Checklist

Run from the repository root:

```bash
xcodebuild test -project MoodleLens.xcodeproj -scheme MoodleLens -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
scripts/verify-local.sh
scripts/package-share.sh v1.0.0
scripts/generate-appcast.sh v1.0.0
hdiutil verify dist/MoodleLens-v1.0.0-macos.dmg
```

Manual smoke:

- Install from DMG into `/Applications`.
- Launch `MoodleLens.app`.
- Confirm Finder, permission prompts, and Settings show `MoodleLens`.
- Configure OpenAI API key or Codex CLI provider.
- Grant Screen Recording, Accessibility, and optional Browser Context from Settings only.
- Restart after Screen Recording grant.
- First-run or unconfigured launch opens Settings.
- Configured relaunch does not open any normal app window; open Settings explicitly with `⌥G`.
- With Settings open but behind another app, press `⌥G` and confirm Settings comes to the front. Press `⌥G` again while Settings is focused and confirm it closes.
- Confirm Settings is visible locally but absent from supported screenshots/recordings.
- Confirm the app has no Dock icon and no Cmd-Tab entry during the background Ask flow.
- Switch Appearance between System, Light, and Dark; relaunch and confirm it persists.
- Verify default shortcuts: `⌥G`, `⌥A`, `⌥B`, and `⌥C`.
- Change one shortcut in Settings -> Hotkeys, confirm the visible shortcut list updates, then reset defaults.
- Open a Moodle quiz or assignment page in Chrome-family browser.
- Trigger Ask and confirm the response bubble appears in the configured corner without changing foreground app focus.
- Confirm Ask answers only from screenshot plus parsed Moodle task evidence.
- Open Settings -> Ask and confirm Current Session History shows the latest task label and answer.
- Confirm a non-Moodle page produces a deterministic "Moodle page not detected" style response.
- Confirm a Moodle page without an extractable task produces a deterministic "no task found" style response.
- Click the bubble or press `⌥B` to hide it; press `⌥B` again to show the last answer.
- Press `⌥C` and confirm Ask history is cleared.
- With Chrome, Arc, Edge, Brave, or Chromium focused and Browser Context granted, confirm Ask can use compact Moodle page controls/options that may not be visible in the screenshot.
- Check `~/Library/Logs/MoodleLens/browser-context.log` for metadata-only attached/skip status.
- Confirm Settings -> Check for Updates opens the native Sparkle update UI or the releases page fallback.
- Confirm uninstall removes app, Keychain item, preferences, caches, logs, temp files, and best-effort TCC records.

Capture matrix:

| Capture path | Required result |
| --- | --- |
| macOS screenshot `Cmd+Shift+3/4/5` | Settings and Ask bubble absent or failure documented with macOS/app/capture version |
| `/usr/sbin/screencapture` | Settings and Ask bubble absent or failure documented with macOS/app/capture version |
| QuickTime screen recording | Settings and Ask bubble absent or failure documented with macOS/app/capture version |
| Target demo/stream stack | Settings and Ask bubble absent or failure documented with macOS/app/capture version |

Privacy caveat:

- MoodleLens uses macOS window sharing exclusion, but capture exclusion is not guaranteed for every capture stack. Test the exact target app/version before relying on it.
