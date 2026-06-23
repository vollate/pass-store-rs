#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/../.."

TARGETS="${PARS_MACOS_TARGETS:-$(rustc -vV | awk '/host:/ { print $2 }')}"
for target in $TARGETS; do
  cargo build -p pars-bridge --release --target "$target"
done
