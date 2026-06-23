#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/../.."

TARGETS="${PARS_ANDROID_TARGETS:-aarch64-linux-android armv7-linux-androideabi x86_64-linux-android}"
for target in $TARGETS; do
  cargo build -p pars-bridge --release --target "$target"
done
