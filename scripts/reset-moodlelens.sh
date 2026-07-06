#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MoodleLens"
PRODUCT_APP_NAME="MoodleLens"
BUNDLE_ID="io.github.volodymyryelisieiev.moodlelens"
KEYCHAIN_ACCOUNT="openai_api_key"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"
INCLUDE_DIST=0

usage() {
  printf 'Usage: %s [--include-dist]\n' "$(basename "$0")"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --include-dist)
      INCLUDE_DIST=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
  shift
done

shopt -s nullglob

note() {
  printf '%s\n' "$*"
}

remove_path() {
  local path="$1"
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -rf "$path"
    note "removed $path"
  else
    note "missing $path"
  fi
}

remove_paths() {
  local path
  for path in "$@"; do
    remove_path "$path"
  done
}

unregister_app() {
  local app="$1"
  if [ -d "$app" ] && [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -u "$app" >/dev/null 2>&1 || true
    note "unregistered $app"
  fi
}

stop_processes() {
  local process
  for process in "$APP_NAME" "$PRODUCT_APP_NAME"; do
    if pgrep -x "$process" >/dev/null 2>&1; then
      pkill -x "$process" || true
      note "stopped $process"
    else
      note "not running $process"
    fi
  done
}

detach_moodlelens_volumes() {
  local volume
  while IFS= read -r -d '' volume; do
    if hdiutil detach "$volume" >/dev/null 2>&1 ||
       hdiutil detach -force "$volume" >/dev/null 2>&1 ||
       diskutil unmount force "$volume" >/dev/null 2>&1; then
      note "detached $volume"
    else
      note "could not detach $volume"
    fi
  done < <(find /Volumes -maxdepth 1 -type d -name 'MoodleLens*' -print0 2>/dev/null)
}

remove_tmp_files() {
  local temp_root="${TMPDIR%/}"
  local path

  remove_path "$temp_root/$BUNDLE_ID"

  while IFS= read -r -d '' path; do
    rm -rf "$path"
    note "removed $path"
  done < <(find /tmp -maxdepth 3 -user "$(id -un)" \( -iname '*moodlelens*' -o -name "$BUNDLE_ID" \) -print0 2>/dev/null)
}

remove_darwin_user_cache() {
  local cache_root
  cache_root="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
  if [ -n "$cache_root" ]; then
    remove_path "${cache_root%/}/$BUNDLE_ID"
  fi
}

remove_keychain_item() {
  if security delete-generic-password -s "$BUNDLE_ID" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1; then
    note "removed Keychain item $BUNDLE_ID/$KEYCHAIN_ACCOUNT"
  else
    note "missing Keychain item $BUNDLE_ID/$KEYCHAIN_ACCOUNT"
  fi
}

stop_processes
detach_moodlelens_volumes

for app in \
  "/Applications/$APP_NAME.app" \
  "$HOME/Applications/$APP_NAME.app" \
  "$ROOT/build/DerivedData/Build/Products/Debug/$PRODUCT_APP_NAME.app" \
  "$ROOT/build/DerivedData/Build/Products/Release/$PRODUCT_APP_NAME.app"
do
  unregister_app "$app"
done

remove_paths \
  "/Applications/$APP_NAME.app" \
  "$HOME/Applications/$APP_NAME.app" \
  "$ROOT/build" \
  "$HOME/Library/Application Support/$BUNDLE_ID" \
  "$HOME/Library/Caches/$BUNDLE_ID" \
  "$HOME/Library/Containers/$BUNDLE_ID" \
  "$HOME/Library/HTTPStorages/$BUNDLE_ID" \
  "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState" \
  "$HOME/Library/Preferences/$BUNDLE_ID.plist"

remove_paths \
  "$HOME/Library/Preferences/ByHost/$BUNDLE_ID".*.plist \
  "$HOME/Library/Developer/Xcode/DerivedData/MoodleLens"-* \
  "$HOME/Library/Logs/$BUNDLE_ID" \
  "$HOME/Library/Logs/MoodleLens"* \
  "$HOME/Library/Logs/DiagnosticReports/MoodleLens"* \
  "$HOME/Library/Logs/CrashReporter/MoodleLens"*

defaults delete "$BUNDLE_ID" >/dev/null 2>&1 && note "deleted defaults $BUNDLE_ID" || note "missing defaults $BUNDLE_ID"
remove_keychain_item
for service in ScreenCapture Accessibility ListenEvent AppleEvents; do
  tccutil reset "$service" "$BUNDLE_ID" >/dev/null 2>&1 || true
done
remove_tmp_files
remove_darwin_user_cache

if [ "$INCLUDE_DIST" -eq 1 ]; then
  remove_path "$ROOT/dist"
else
  note "kept $ROOT/dist (use --include-dist to remove release artifacts)"
fi

note "reset complete"
