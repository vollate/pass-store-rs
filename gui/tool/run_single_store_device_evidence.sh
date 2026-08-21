#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
gui="$repo_root/gui"
android_device="${1:-emulator-5554}"
ios_device="${2:-}"
tmp="$(mktemp -d)"
cp "$gui/pubspec.yaml" "$tmp/pubspec.yaml"
cp "$gui/pubspec.lock" "$tmp/pubspec.lock"

cleanup() {
  cp "$tmp/pubspec.yaml" "$gui/pubspec.yaml"
  cp "$tmp/pubspec.lock" "$gui/pubspec.lock"
  rm -rf "$gui/integration_test" "$gui/test_driver"
  (cd "$gui" && PUB_HOSTED_URL=https://pub.flutter-io.cn flutter pub get >/dev/null)
  cp "$tmp/pubspec.lock" "$gui/pubspec.lock"
  rm -rf "$tmp"
}
trap cleanup EXIT

python3 - "$gui/pubspec.yaml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
needle = "  flutter_test:\n    sdk: flutter\n"
addition = needle + "  integration_test:\n    sdk: flutter\n"
if "  integration_test:\n" not in s:
    s = s.replace(needle, addition)
p.write_text(s)
PY
mkdir -p "$gui/integration_test" "$gui/test_driver"
cp "$gui/tool/device_evidence/single_store_device_test.dart.template" \
  "$gui/integration_test/single_store_device_test.dart"
cp "$gui/tool/device_evidence/integration_test_driver.dart.template" \
  "$gui/test_driver/integration_test.dart"

cd "$gui"
PUB_HOSTED_URL=https://pub.flutter-io.cn flutter pub get >/dev/null
before="$(adb -s "$android_device" shell dumpsys package top.vollate.pars_gui \
  | sed -n 's/.*firstInstallTime=//p' | head -1)"
PUB_HOSTED_URL=https://pub.flutter-io.cn flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/single_store_device_test.dart \
  -d "$android_device" --keep-app-running
after="$(adb -s "$android_device" shell dumpsys package top.vollate.pars_gui \
  | sed -n 's/.*firstInstallTime=//p' | head -1)"
test -n "$before" && test "$before" = "$after"
adb -s "$android_device" shell \
  'run-as top.vollate.pars_gui ls files/stores/personm/.gpg-id files/stores/personm/127.0.0.1/foo.gpg files/stores/personm/linux.do/foo.gpg'

if [[ -n "$ios_device" ]]; then
  PUB_HOSTED_URL=https://pub.flutter-io.cn flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/single_store_device_test.dart \
    -d "$ios_device" --keep-app-running
fi
