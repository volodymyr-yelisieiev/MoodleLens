#!/usr/bin/env bash
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

FAILURES=0
INFO_PLIST="MoodleLens/Info.plist"
ENTITLEMENTS="MoodleLens/MoodleLens.entitlements"

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  FAILURES=$((FAILURES + 1))
}

warn() {
  printf 'WARN %s\n' "$1"
}

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null
}

plist_true() {
  [ "$(plist_value "$1" "$2")" = "true" ]
}

plist_false() {
  [ "$(plist_value "$1" "$2")" = "false" ]
}

plist_missing() {
  ! /usr/libexec/PlistBuddy -c "Print :$2" "$1" >/dev/null 2>&1
}

plist_exists() {
  /usr/libexec/PlistBuddy -c "Print :$2" "$1" >/dev/null 2>&1
}

check() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

app_icon_sizes_ok() {
  local item file size actual
  for item in \
    "icon_16.png:16" "icon_16@2x.png:32" \
    "icon_32.png:32" "icon_32@2x.png:64" \
    "icon_128.png:128" "icon_128@2x.png:256" \
    "icon_256.png:256" "icon_256@2x.png:512" \
    "icon_512.png:512" "icon_512@2x.png:1024"; do
    file=${item%:*}
    size=${item#*:}
    actual=$(
      sips -g pixelWidth -g pixelHeight "MoodleLens/Assets.xcassets/AppIcon.appiconset/$file" 2>/dev/null |
        awk '/pixelWidth|pixelHeight/{print $2}' |
        tr '\n' ' '
    )
    [ "$actual" = "$size $size " ] || return 1
  done
}

check "Info.plist is valid" plutil -lint "$INFO_PLIST"
check "Entitlements plist is valid" plutil -lint "$ENTITLEMENTS"
check "LSUIElement is true" plist_true "$INFO_PLIST" "LSUIElement"
check "LSBackgroundOnly is absent" plist_missing "$INFO_PLIST" "LSBackgroundOnly"
check "Screen capture usage string exists" plist_exists "$INFO_PLIST" "NSScreenCaptureUsageDescription"
check "Apple Events usage string exists for Browser Context" plist_exists "$INFO_PLIST" "NSAppleEventsUsageDescription"
check "Sparkle feed URL exists" plist_exists "$INFO_PLIST" "SUFeedURL"
check "Sparkle public EdDSA key exists" plist_exists "$INFO_PLIST" "SUPublicEDKey"
check "Sparkle automatic checks are disabled" plist_false "$INFO_PLIST" "SUEnableAutomaticChecks"
check "Microphone usage string is absent" plist_missing "$INFO_PLIST" "NSMicrophoneUsageDescription"
check "Speech recognition usage string is absent" plist_missing "$INFO_PLIST" "NSSpeechRecognitionUsageDescription"
check "App Sandbox entitlement is absent for local CLI-provider build" plist_missing "$ENTITLEMENTS" "com.apple.security.app-sandbox"
check "Sandbox network entitlement is absent" plist_missing "$ENTITLEMENTS" "com.apple.security.network.client"
check "User-selected read-only entitlement is absent" plist_missing "$ENTITLEMENTS" "com.apple.security.files.user-selected.read-only"
check "User-selected read-write entitlement is absent" plist_missing "$ENTITLEMENTS" "com.apple.security.files.user-selected.read-write"
check "Microphone entitlement is absent" plist_missing "$ENTITLEMENTS" "com.apple.security.device.microphone"
check "Speech recognition entitlement is absent" plist_missing "$ENTITLEMENTS" "com.apple.security.personal-information.speech-recognition"

if rg -n 'print\([^\n]*(apiKey|api key|Authorization|Bearer|base64|base64Image|prompt|response|requestBody|jsonData|httpBody|responseBody|appTempDirectory\.path)' MoodleLens -g '*.swift' >/dev/null; then
  fail "No obvious sensitive console logging"
else
  pass "No obvious sensitive console logging"
fi

check "Privacy diagnostics source exists" rg -q "printPrivacyDiagnostics" MoodleLens/Application/MoodleLensApp.swift
check "Permission refresh uses silent CGPreflightScreenCaptureAccess" rg -q "CGPreflightScreenCaptureAccess" MoodleLens/Managers/PermissionManager.swift
check "Screenshot capture uses in-process ScreenCaptureKit" rg -q "SCScreenshotManager.captureImage" MoodleLens/Services/Screenshot/ScreenshotService.swift
check "Screenshot capture excludes MoodleLens windows without hiding UI" sh -c "rg -q 'SCContentFilter\\(display: display, excludingWindows: appWindows\\)' MoodleLens/Services/Screenshot/ScreenshotService.swift && ! rg -q 'hideWindow\\(\\)|restoreWindow\\(\\)|addingTimeInterval\\(0\\.1\\)' MoodleLens/Services/Screenshot/ScreenshotService.swift"
check "Message markdown uses native AttributedString parser" sh -c "rg -q 'AttributedString\\(markdown: text' MoodleLens/Utils/MarkdownParser.swift && ! rg -q 'NSRegularExpression|foregroundColor' MoodleLens/Utils/MarkdownParser.swift"
check "Conversation main view is pruned" sh -c "! test -d MoodleLens/Features/Conversation && ! test -f MoodleLens/ViewModels/ConversationViewModel.swift"
check "Shortcut UI is generated from registered hotkeys" rg -q "ForEach\\(AppHotkey\\.registeredHotkeys" MoodleLens/Features/Settings/SettingsView.swift
check "Only Ask-era hotkeys are registered" rg -q "\\[\\.openSettings, \\.ask, \\.toggleBubble, \\.clearChat\\]" MoodleLens/Managers/GlobalHotkeyManager.swift
check "Default hotkeys are Opt+G Opt+A Opt+B Opt+C" sh -c "rg -q 'let modifiers = HotkeyBinding\\.option' MoodleLens/Managers/GlobalHotkeyManager.swift && rg -q 'HotkeyBinding\\(keyCode: 5, modifiers: modifiers\\)' MoodleLens/Managers/GlobalHotkeyManager.swift && rg -q 'HotkeyBinding\\(keyCode: 0, modifiers: modifiers\\)' MoodleLens/Managers/GlobalHotkeyManager.swift && rg -q 'HotkeyBinding\\(keyCode: 11, modifiers: modifiers\\)' MoodleLens/Managers/GlobalHotkeyManager.swift && rg -q 'HotkeyBinding\\(keyCode: 8, modifiers: modifiers\\)' MoodleLens/Managers/GlobalHotkeyManager.swift"
check "Removed hotkeys are not exposed" sh -c "! rg -q 'case panicHide|case quit|case toggleWindow|case captureScreenshot|case zenMode|Panic Hide|Fn\\+Cmd|Zen Mode' MoodleLens README.md docs"
check "Hotkeys are persisted and user-customizable" sh -c "rg -q 'struct HotkeyBinding' MoodleLens/Managers/GlobalHotkeyManager.swift && rg -q 'hotkey_bindings' MoodleLens/Managers/SettingsManager.swift && rg -q 'startHotkeyRecording' MoodleLens/Features/Settings/SettingsView.swift && rg -q 'reloadHotkeys' MoodleLens/Managers/GlobalHotkeyManager.swift"
check "Settings-only app launch has no main window" sh -c "! rg -q 'showWindow\\(with:|makeConversationView' MoodleLens/Application/MoodleLensApp.swift MoodleLens/DI/DIRegistrar.swift"
check "Ask hotkey is registered" sh -c "rg -q 'case ask' MoodleLens/Managers/GlobalHotkeyManager.swift && rg -q 'AskController\\.shared\\.ask' MoodleLens/Managers/GlobalHotkeyManager.swift MoodleLens/Application/MoodleLensApp.swift"
check "Ask bubble is excluded from capture" sh -c "rg -q 'sharingType = \\.none' MoodleLens/Features/Ask/AskController.swift && rg -q 'nonactivatingPanel' MoodleLens/Features/Ask/AskController.swift"
check "Ask auto-hide is fixed at ten seconds" sh -c "rg -q 'autoHideSeconds: TimeInterval = 10' MoodleLens/Features/Ask/AskController.swift && ! rg -q 'zenAutoHideSeconds|Auto-hide after|Zen' MoodleLens README.md docs"
check "Browser context is compact, logged, and runtime silent" sh -c "rg -q 'AEDeterminePermissionToAutomateTarget' MoodleLens/Services/Browser/BrowserContextProvider.swift && rg -q 'askUserIfNeeded: false' MoodleLens/Services/Browser/BrowserContextProvider.swift && rg -q 'maxContextLength = 20_000' MoodleLens/Services/Browser/BrowserContextProvider.swift && rg -q 'browser-context\\.log' MoodleLens/Services/Browser/BrowserContextProvider.swift && rg -q 'BrowserContextProvider.addCurrentContext' MoodleLens/Features/Ask/AskController.swift && rg -q 'Browser snapshot from the current active webpage' MoodleLens/Features/Ask/AskController.swift && ! rg -q 'BrowserContextProvider\\.recordStatus' MoodleLens"
check "Ask bubble renders scrollable history with Markdown" sh -c "rg -q 'AskBubbleView\\(messages: history' MoodleLens/Features/Ask/AskController.swift && rg -q 'ForEach\\(messages\\)' MoodleLens/Features/Ask/AskController.swift && rg -q 'MarkdownParser.parse' MoodleLens/Features/Ask/AskController.swift"
check "Advanced settings expose one shared instructions field" sh -c "rg -q 'Used for every Ask prompt' MoodleLens/Features/Settings/SettingsView.swift && ! rg -q 'selectedContextTab|contextTabs|Context\", selection' MoodleLens/Features/Settings/SettingsView.swift && rg -q 'defaultInstructions' MoodleLens/Managers/SettingsManager.swift"
check "Browser context tolerates transient frontmost-app changes" sh -c "rg -q 'startTrackingFrontmostBrowser' MoodleLens/Application/MoodleLensApp.swift MoodleLens/Services/Browser/BrowserContextProvider.swift && rg -q 'allowRecentFallback: true' MoodleLens/Services/Browser/BrowserContextProvider.swift"
check "Permission repair resets stale TCC rows before prompting" sh -c "rg -q 'tccutil' MoodleLens/Managers/TCCPermissionResetter.swift && rg -q 'resetPermission\\(\\.screenCapture\\)' MoodleLens/Features/Settings/SettingsView.swift && rg -q 'resetPermission\\(\\.accessibility\\)' MoodleLens/Features/Settings/SettingsView.swift && rg -q 'resetAutomationPermission' MoodleLens/Features/Settings/SettingsView.swift MoodleLens/Services/Browser/BrowserContextProvider.swift"
check "Browser Context prompt is Settings-only" sh -c "rg -q 'requestAutomationForFrontmostBrowser' MoodleLens/Features/Settings/SettingsView.swift && ! rg -q 'askUserIfNeeded: true' MoodleLens/Application MoodleLens/Features/Ask MoodleLens/Services/Screenshot"
check "Settings screen recording action can trigger native request" rg -q "grantScreenRecording" MoodleLens/Features/Settings/SettingsView.swift
check "Only Settings triggers native screen recording requests" sh -c "! rg -q 'requestScreenCapturePermission' MoodleLens/Application/MoodleLensApp.swift && rg -q 'requestScreenCapturePermission' MoodleLens/Features/Settings/SettingsView.swift"
check "Grant repair does not also open System Settings" sh -c 'if awk "/private func grantScreenRecording\\(\\)/,/private var browserContextDetail/" MoodleLens/Features/Settings/SettingsView.swift | rg -q "openSystemSettings|openAccessibilitySettings|openAutomationSettings"; then exit 1; fi; if awk "/private func grantBrowserContext\\(\\)/,/private func refreshCodexStatus/" MoodleLens/Features/Settings/SettingsView.swift | rg -q "openSystemSettings|openAccessibilitySettings|openAutomationSettings"; then exit 1; fi'
check "Permission refresh stays silent" sh -c 'if awk "/private func refreshPermissions\\(\\)/,/private func grantScreenRecording\\(\\)/" MoodleLens/Features/Settings/SettingsView.swift | sed "$d" | rg -q "requestScreenCapturePermission|AXIsProcessTrustedWithOptions"; then exit 1; else exit 0; fi'
check "Settings is opened as an app-managed window" rg -q "showSettings\\(firstRunSetup: Bool\\)" MoodleLens/Application/MoodleLensApp.swift
check "Settings window is independent of main window" sh -c "! rg -q 'addChildWindow|removeChildWindow' MoodleLens/Application/MoodleLensApp.swift"
check "App command handler covers quit close escape" sh -c "rg -q 'event.keyCode == 12' MoodleLens/Application/MoodleLensApp.swift && rg -q 'event.keyCode == 13' MoodleLens/Application/MoodleLensApp.swift && rg -q 'event.keyCode == 53' MoodleLens/Application/MoodleLensApp.swift"
check "Assistant windows use floating level without private high levels" sh -c "rg -q 'window.level = \\.floating' MoodleLens/Features/Ask/AskController.swift && ! rg -q 'assistiveTechHigh|specialWindowLevel|secureWindowLevel' MoodleLens/Features/WindowManagement MoodleLens/Application/MoodleLensApp.swift"
check "Ask path does not activate MoodleLens" sh -c "! rg -q 'NSApp\\.activate|makeKeyAndOrderFront' MoodleLens/Features/Ask MoodleLens/Services/Screenshot"
check "Arrow cursor lock covers app windows" sh -c "rg -q 'discardCursorRects\\(in:' MoodleLens/Features/WindowManagement/WindowManager.swift && rg -q 'forceArrow' MoodleLens/Features/WindowManagement/WindowManager.swift && rg -q 'ArrowCursorLock.apply\\(to: window\\)' MoodleLens/Features/Ask/AskController.swift"
check "Appearance mode is persisted and applied" sh -c "rg -q 'appearance_mode' MoodleLens/Managers/SettingsManager.swift MoodleLens/Features/Settings/SettingsView.swift && rg -q 'preferredColorScheme' MoodleLens/Features/Settings/SettingsView.swift"
check "Uninstaller runs detached and can kill stuck app" sh -c 'rg -qF "/usr/bin/nohup" MoodleLens/Features/Settings/SettingsView.swift && rg -qF "kill -9 \"\$pid\"" MoodleLens/Features/Settings/SettingsView.swift'
check "Uninstaller only removes current MoodleLens paths" sh -c "old_names='Ghost''Cue|Hidden''AI|Moodle Assessment'' Probe|in''searcher|ghost''cue'; rg -q '/Applications/MoodleLens\\.app' MoodleLens/Features/Settings/SettingsView.swift scripts/reset-moodlelens.sh && ! rg -n \"\$old_names\" MoodleLens/Features/Settings/SettingsView.swift scripts/reset-moodlelens.sh"
check "Reset script removes user Applications install" rg -qF '$HOME/Applications/$APP_NAME.app' scripts/reset-moodlelens.sh
check "Temp cleanup removes empty app temp directory" rg -q "removeAppTempDirectoryIfEmpty" MoodleLens/Managers/TempFileManager.swift
check "Clear action invokes temp cleanup" rg -q "cleanupAllTempFiles\\(\\)" MoodleLens/Features/Ask/AskController.swift
check "Window visibility uses NSWindow state" rg -q "windowManager.window\\?\\.isVisible" MoodleLens/Application/MoodleLensApp.swift
check "Window close button hides instead of quitting" rg -q "windowShouldClose" MoodleLens/Features/WindowManagement/WindowManager.swift
check "Package script supports stable signed builds without mandatory notarization" sh -c "rg -q 'SIGNED_RELEASE' scripts/package-share.sh && rg -q 'TCC permissions should persist' scripts/package-share.sh"
check "Package script Gatekeeper-assesses notarized app" rg -q "spctl --assess --verbose=4" scripts/package-share.sh
check "Package script Gatekeeper-assesses notarized DMG" rg -q "context:primary-signature" scripts/package-share.sh
check "Package script creates Sparkle app-only ZIP" rg -q 'ditto .*"\$APP_DST" "\$SPARKLE_ZIP_PATH"' scripts/package-share.sh
check "Package script keeps DMG root to app and Applications" sh -c '! rg -q "START_HERE" scripts/package-share.sh && rg -qF "ln -s /Applications \"\$STAGE_DIR/Applications\"" scripts/package-share.sh'
check "Package script styles Finder DMG window" sh -c "rg -q 'set background color' scripts/package-share.sh && rg -q 'set position of item' scripts/package-share.sh"
check "Package script no longer creates old macos ZIP" sh -c '! rg -q "macos\\.zip" scripts/package-share.sh'
check "Package script uses active Xcode developer dir" sh -c "rg -q 'xcode-select -p' scripts/package-share.sh && ! rg -q '/Applications/Xcode\\.app/Contents/Developer' scripts/package-share.sh"
check "Package script supports direct notary credentials" sh -c "rg -q 'MOODLELENS_NOTARY_KEY' scripts/package-share.sh && rg -q 'notarytool submit .*--key' scripts/package-share.sh"
check "Release workflow publishes appcast as release asset" sh -c "rg -q 'tags:' .github/workflows/release.yml && rg -q 'dist/appcast.xml' .github/workflows/release.yml && ! rg -q 'gh pr create|Open appcast pull request' .github/workflows/release.yml"
check "CI and release use latest available GitHub macOS runner" sh -c "rg -q 'runs-on: macos-latest' .github/workflows/ci.yml .github/workflows/release.yml && ! rg -q 'runs-on: macos-[0-9]' .github/workflows/ci.yml .github/workflows/release.yml"
check "Appcast generation script signs Sparkle feed" sh -c "rg -q 'generate_appcast' scripts/generate-appcast.sh && rg -q 'SPARKLE_PRIVATE_KEY' scripts/generate-appcast.sh && rg -q 'download-url-prefix' scripts/generate-appcast.sh"
check "No old product names remain" sh -c "old_names='Ghost''Cue|Hidden''AI|Moodle Assessment'' Probe|in''searcher|hidden''ai|ghost''cue'; ! rg -n -i \"\$old_names\" --glob '!scripts/verify-local.sh' ."
check "No old release versions remain" sh -c "old_versions='v1\\.4''\\.8|1\\.4''\\.8|104''08|v1\\.1''\\.0'; ! rg -n \"\$old_versions\" --glob '!scripts/verify-local.sh' ."
check "Settings manager has no UserDefaults API-key import path" sh -c "import_path='leg''acy''Value|migra''tion''Status|Could not move the OpenAI API'' key'; ! rg -n \"\$import_path\" MoodleLens/Managers/SettingsManager.swift"
check "README documents AI-assisted status and contributions" sh -c "rg -qi 'AI-assisted|vibecoding|vibe' README.md && rg -qi 'contribut' README.md CONTRIBUTING.md"
check "App icon assets keep transparent alpha" sh -c "test \"$(sips -g hasAlpha docs/images/moodlelens-icon.png MoodleLens/Assets.xcassets/MoodleLensMark.imageset/moodlelens-mark.png 2>/dev/null | rg -c 'hasAlpha: yes')\" = 2"
check "App icon slots have correct pixel sizes" app_icon_sizes_ok

if rg -n 'xattr -cr|open /Applications/MoodleLens\.app' docs/first-run.md >/dev/null; then
  fail "START_HERE has no Terminal fallback in the happy path"
else
  pass "START_HERE has no Terminal fallback in the happy path"
fi

if [ -e MoodleLens/Features/Conversation/ConversationView.swift ] && rg -nF '.sheet(isPresented: $showSettings' MoodleLens/Features/Conversation/ConversationView.swift >/dev/null; then
  fail "Settings is not a SwiftUI sheet"
else
  pass "Settings is not a SwiftUI sheet"
fi

if rg -n 'requestAppPermissions|AccessibilityPermissions\.requestAccessibilityPermissions|requestAllPermissions' MoodleLens/Application MoodleLens/Managers/DevelopmentConfig.swift >/dev/null; then
  fail "No automatic permission request on launch"
else
  pass "No automatic permission request on launch"
fi

if rg -n '/usr/sbin/screencapture|CGWindowListCreateImage' MoodleLens/Services/Screenshot/ScreenshotService.swift >/dev/null; then
  fail "No external screencapture or deprecated CGWindowList screenshot path"
else
  pass "No external screencapture or deprecated CGWindowList screenshot path"
fi

if rg -n 'NSAlert' MoodleLens/Managers/PermissionManager.swift MoodleLens/Managers/AccessibilityPermissions.swift >/dev/null; then
  fail "Permission flow has no app-modal alert spam"
else
  pass "Permission flow has no app-modal alert spam"
fi

if rg -n 'private var (windowHidden|isWindowHidden|isProcessingToggle)' MoodleLens/Application MoodleLens/Features/WindowManagement >/dev/null; then
  fail "No duplicate lifecycle state flags"
else
  pass "No duplicate lifecycle state flags"
fi

if rg -n 'asyncAfter\\(deadline: \\.now\\(\\) \\+ 0\\.[12]\\)' MoodleLens/Application MoodleLens/Managers/GlobalHotkeyManager.swift MoodleLens/Features/WindowManagement >/dev/null; then
  fail "No delayed window toggle race"
else
  pass "No delayed window toggle race"
fi

APP_TEMP_DIR="${TMPDIR%/}/io.github.volodymyryelisieiev.moodlelens"
if [ -e "$APP_TEMP_DIR" ]; then
  warn "App temp directory currently exists: $APP_TEMP_DIR"
else
  pass "No current MoodleLens app temp directory"
fi

if command -v codex >/dev/null 2>&1 || [ -x /Applications/Codex.app/Contents/Resources/codex ]; then
  pass "Codex CLI executable is available"
else
  warn "Codex CLI executable not found; Codex provider will show install/login instructions"
fi

if [ "$FAILURES" -eq 0 ]; then
  printf 'Local verification checks passed.\n'
  exit 0
fi

printf 'Local verification checks failed: %s\n' "$FAILURES"
exit 1
