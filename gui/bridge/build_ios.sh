#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/../.."

TARGETS="${PARS_IOS_TARGETS:-aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios}"
for target in $TARGETS; do
  cargo build -p pars-bridge --release --target "$target"
done
