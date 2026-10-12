#!/usr/bin/env bash
# Install the debug APK on the running emulator, start the app, and check that
# it comes up and stays up.
#
#   android-smoke.sh <apk> <application id>
#
# Run by reactivecircus/android-emulator-runner once the emulator has booted.
# Writes android-smoke.png (a screenshot) and android-smoke.log (the app's
# logcat) to the working directory for the run to attach.
#
# What it asserts, and why each one:
#   * the install succeeds: a manifest, signature or ABI problem fails here;
#   * the app's process is alive after the settle time: a crash on start-up
#     kills it;
#   * the app's activity is the top resumed one: the process can be alive and
#     the window gone;
#   * logcat has no `FATAL EXCEPTION` for the process and no uncaught Dart
#     error: a Flutter app can keep running after its first frame threw.
set -euo pipefail

apk=${1:?usage: android-smoke.sh <apk> <application id>}
app=${2:?usage: android-smoke.sh <apk> <application id>}
settle=${SETTLE_SECONDS:-25}

adb install -r "$apk"
adb logcat -c
adb shell am start -W -n "$app/$app.MainActivity"

# Give the Dart isolate time to build its first frames and finish start-up work.
sleep "$settle"

adb exec-out screencap -p >android-smoke.png || true
adb logcat -d >android-smoke.log || true

fail() {
  echo "android-smoke: $*" >&2
  echo "--- the last 60 lines of logcat ---" >&2
  tail -n 60 android-smoke.log >&2 || true
  exit 1
}

pid=$(adb shell pidof "$app" | tr -d '\r' || true)
[ -n "$pid" ] || fail "the app's process is not running $settle seconds after launch (it crashed or was killed)."

if ! adb shell dumpsys activity activities | tr -d '\r' | grep -E 'topResumedActivity|mResumedActivity|ResumedActivity' | grep -q "$app"; then
  fail "$app is running but its activity is not the resumed one."
fi

if grep -E 'FATAL EXCEPTION' android-smoke.log | grep -q .; then
  fail "logcat holds a FATAL EXCEPTION."
fi
if grep -E 'flutter.*(Unhandled Exception|FlutterError|Exception caught by)' android-smoke.log | grep -q .; then
  fail "the Flutter engine reported an unhandled Dart error."
fi

echo "android-smoke: $app (pid $pid) is up after $settle s, the activity is resumed, and logcat is clean."
