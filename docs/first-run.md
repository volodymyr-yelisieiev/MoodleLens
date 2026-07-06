# MoodleLens First Run

1. Open `MoodleLens-...-macos.dmg`.
2. Drag `MoodleLens.app` onto the `Applications` shortcut.
3. Open `MoodleLens.app` from Applications.
4. Choose OpenAI API key or Codex CLI.
5. Use Settings -> Permissions -> `Grant / Repair` for Screen Recording and Accessibility.
6. Restart MoodleLens after granting Screen Recording.
7. Optional: open Chrome, Arc, Edge, Brave, or Chromium and grant Browser Context from Settings. In Chrome-family browsers, also enable `View -> Developer -> Allow JavaScript from Apple Events`.
8. Use Settings -> `Check for Updates` for native updates.

`Grant / Repair` removes the current bundle's old TCC row for that permission before asking macOS to add it back.

Ad-hoc builds are not notarized and may need fresh Privacy grants after rebuilds. Signed releases with the same identity preserve Privacy permissions across updates.
