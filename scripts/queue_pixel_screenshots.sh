#!/usr/bin/env bash

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${project_root}"

agent="$(basename "${project_root}")"
package_id="$(sed -nE 's/.*applicationId[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' android/app/build.gradle.kts | head -n 1)"
queue_url="http://localhost:3000"

log() {
  printf '%s %s\n' "$(date -Is)" "$*"
}

queue_join() {
  curl --max-time 5 -s -X POST "${queue_url}/join?agent=${agent}" || true
  printf '\n'
}

queue_done() {
  curl --max-time 5 -s -X POST "${queue_url}/done?agent=${agent}" || true
  printf '\n'
}

queue_status() {
  curl --max-time 5 -s "${queue_url}/status?agent=${agent}" || true
}

is_turn() {
  printf '%s' "$1" | grep -q '"yourTurn"[[:space:]]*:[[:space:]]*true'
}

online_device() {
  adb devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 == "device" { print $1; exit }'
}

qemu_pixel_count() {
  ps -C qemu-system-x86_64 -o args= 2>/dev/null \
    | awk '/-avd Pixel_8_Pro/ { c++ } END { print c + 0 }'
}

wait_for_pixel_boot() {
  local device boot avd
  for index in $(seq 1 150); do
    device="$(online_device || true)"
    if [[ -n "${device}" ]]; then
      boot="$(adb -s "${device}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      avd="$(adb -s "${device}" shell getprop ro.boot.qemu.avd_name 2>/dev/null | tr -d '\r' || true)"
      log "boot-check index=${index} device=${device} avd=${avd:-unknown} boot=${boot:-waiting}"
      if [[ "${boot}" == "1" && "${avd}" == "Pixel_8_Pro" ]]; then
        return 0
      fi
    else
      log "boot-check index=${index} device=none qemu=$(qemu_pixel_count)"
      if [[ "$(qemu_pixel_count)" == "0" && "${index}" -gt 20 ]]; then
        return 1
      fi
    fi
    sleep 2
  done
  return 1
}

verify_screenshots() {
  local count unique small dims
  count="$(find docs/screens -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
  unique="$(sha256sum docs/screens/*.png 2>/dev/null | awk '{ print $1 }' | sort -u | wc -l | tr -d ' ')"
  small="$(find docs/screens -maxdepth 1 -type f -name '*.png' -size -100k | wc -l | tr -d ' ')"
  dims="$(file docs/screens/*.png 2>/dev/null | sed -E 's|.*/([^/]+): PNG image data, ([0-9]+ x [0-9]+).*|\1=\2|' | tr '\n' ' ')"
  log "screenshot-check count=${count} unique=${unique} small=${small} dims=${dims}"
  [[ "${count}" -ge 6 && "${unique}" -ge 6 && "${small}" == "0" ]]
}

run_turn() {
  local device avd

  log "required adb device check"
  adb devices
  device="$(online_device || true)"
  if [[ -n "${device}" ]]; then
    avd="$(adb -s "${device}" shell getprop ro.boot.qemu.avd_name 2>/dev/null | tr -d '\r' || true)"
    log "existing-device=${device} avd=${avd:-unknown}"
    [[ "${avd}" == "Pixel_8_Pro" ]] || return 1
  else
    if [[ "$(qemu_pixel_count)" != "0" ]]; then
      log "Pixel_8_Pro process exists without ADB device; waiting rather than launching another"
      wait_for_pixel_boot || return 1
    else
      log "launching Pixel_8_Pro"
      flutter emulators --launch Pixel_8_Pro || true
      wait_for_pixel_boot || return 1
    fi
  fi

  if [[ -f build/app/outputs/flutter-apk/app-release.apk ]]; then
    SKIP_SCREENSHOT_BUILD=1 scripts/capture_pixel_screenshots.sh
  else
    scripts/capture_pixel_screenshots.sh
  fi
  verify_screenshots
}

queue_join
for attempt in $(seq 1 80); do
  log "queue-attempt=${attempt}"
  while true; do
    sleep_seconds=10
    status="$(queue_status)"
    log "$(printf '%s' "${status}" | tr '\n' ' ' | tr -s ' ')"
    ahead="$(printf '%s' "${status}" | sed -nE 's/.*"ahead"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p')"
    if [[ -n "${ahead:-}" && "${ahead}" -le 3 ]]; then
      sleep_seconds=2
    fi
    if printf '%s' "${status}" | grep -qi 'not in queue'; then
      queue_join >/dev/null
      sleep 2
      continue
    fi
    if is_turn "${status}"; then
      break
    fi
    sleep "${sleep_seconds}"
  done

  if run_turn; then
    adb shell pm uninstall "${package_id}" >/dev/null 2>&1 || true
    queue_done
    log "screenshots accepted and queue released"
    exit 0
  fi

  log "screenshot attempt failed; uninstalling, releasing, and rejoining"
  adb shell pm uninstall "${package_id}" >/dev/null 2>&1 || true
  queue_done >/dev/null
  sleep 5
  queue_join >/dev/null
  sleep 10
done

log "screenshot queue attempts exhausted"
exit 1
