#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_root}"

package_id="$(sed -nE 's/.*applicationId[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' android/app/build.gradle.kts | head -n 1)"
if [[ -z "${package_id}" ]]; then
  echo "Could not read applicationId from android/app/build.gradle.kts" >&2
  exit 1
fi

mkdir -p docs/screens
rm -f docs/screens/*.png

screenshot_apk="${SCREENSHOT_APK:-build/app/outputs/flutter-apk/app-release.apk}"

if [[ "${SKIP_SCREENSHOT_BUILD:-0}" != "1" ]]; then
  flutter build apk --release --dart-define=SCREENSHOT_MODE=true
fi

if [[ ! -f "${screenshot_apk}" ]]; then
  echo "Expected ${screenshot_apk} to exist" >&2
  exit 1
fi

adb install -r "${screenshot_apk}" >/dev/null

focus_for_package() {
  adb shell dumpsys window 2>/dev/null \
    | tr -d '\r' \
    | grep -E 'mCurrentFocus|mFocusedApp' || true
}

wait_for_foreground() {
  local focus
  for _ in $(seq 1 30); do
    focus="$(focus_for_package)"
    if [[ "${focus}" == *"${package_id}"* ]]; then
      return 0
    fi
    sleep 1
  done

  focus="$(focus_for_package)"
  echo "Target package did not reach foreground. Focus: ${focus}" >&2
  return 1
}

adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
adb shell am force-stop "${package_id}" >/dev/null || true
adb shell am start -n "${package_id}/.MainActivity" >/dev/null
adb shell monkey -p "${package_id}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
wait_for_foreground
sleep 1

names=(
  "01_dashboard"
  "02_containers"
  "03_detail"
  "04_create_reservation"
  "05_planning"
  "06_settings"
)

for index in "${!names[@]}"; do
  if (( index > 0 )); then
    sleep 2.2
  fi

  focus="$(focus_for_package)"
  if [[ "${focus}" != *"${package_id}"* ]]; then
    adb shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
    adb shell wm dismiss-keyguard >/dev/null 2>&1 || true
    adb shell am start -n "${package_id}/.MainActivity" >/dev/null
    adb shell monkey -p "${package_id}" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
    if ! wait_for_foreground; then
      echo "Refusing to capture: foreground app is not ${package_id}. Focus: ${focus}" >&2
      exit 1
    fi
  fi

  adb exec-out screencap -p > "docs/screens/${names[index]}.png"
done

echo "Captured ${#names[@]} screenshot(s) for ${package_id}"
