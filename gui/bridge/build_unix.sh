#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: build_unix.sh <linux|android|ios>

Environment:
  PARS_BRIDGE_PROFILE       debug or release (default: debug)
  PARS_LINUX_OUTPUT_DIR     destination for libpars_bridge.so
  PARS_ANDROID_OUTPUT_DIR   destination jniLibs directory
  PARS_ANDROID_TARGETS      comma-separated cargo-ndk targets
  PARS_ANDROID_PROFILE      android-specific profile override
  PARS_IOS_OUTPUT_DIR       destination for pars_bridge.xcframework
  PARS_IOS_PROFILE          ios-specific profile override
USAGE
}

if [ "$#" -ne 1 ]; then
  usage
  exit 2
fi

MODE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${GUI_DIR}/.." && pwd)"
PROFILE="${PARS_BRIDGE_PROFILE:-debug}"

is_release_profile() {
  case "$1" in
    release|Release|profile|Profile)
      return 0
      ;;
  esac
  return 1
}

run_cargo_build() {
  local profile="$1"
  shift
  if is_release_profile "$profile"; then
    cargo build -p pars-bridge --release "$@"
  else
    cargo build -p pars-bridge "$@"
  fi
}

profile_dir() {
  case "$1" in
    release|Release|profile|Profile)
      printf '%s\n' release
      ;;
    *)
      printf '%s\n' debug
      ;;
  esac
}

build_linux() {
  local profile="$PROFILE"
  local dir
  dir="$(profile_dir "$profile")"
  local output_dir="${PARS_LINUX_OUTPUT_DIR:-${GUI_DIR}/build/native/linux}"

  cd "$REPO_ROOT"
  run_cargo_build "$profile"
  mkdir -p "$output_dir"
  cp "${REPO_ROOT}/target/${dir}/libpars_bridge.so" "${output_dir}/libpars_bridge.so"
}

build_android() {
  local profile="${PARS_ANDROID_PROFILE:-$PROFILE}"
  local output_dir="${PARS_ANDROID_OUTPUT_DIR:-${GUI_DIR}/android/app/build/rustJniLibs}"
  local targets_csv="${PARS_ANDROID_TARGETS:-arm64-v8a}"

  if ! command -v cargo-ndk >/dev/null 2>&1; then
    echo "error: cargo-ndk is required for Android bridge builds" >&2
    echo "hint: cargo install cargo-ndk" >&2
    exit 1
  fi

  IFS=',' read -r -a android_targets <<<"$targets_csv"
  local cargo_ndk_targets=()
  for target in "${android_targets[@]}"; do
    target="${target//[[:space:]]/}"
    if [ -z "$target" ]; then
      continue
    fi
    cargo_ndk_targets+=("-t" "$target")
  done
  if [ "${#cargo_ndk_targets[@]}" -eq 0 ]; then
    echo "error: PARS_ANDROID_TARGETS did not contain any Android targets" >&2
    exit 1
  fi

  rm -rf "$output_dir"

  cd "$REPO_ROOT"
  if is_release_profile "$profile"; then
    cargo ndk \
      "${cargo_ndk_targets[@]}" \
      -o "$output_dir" \
      build -p pars-bridge --release
  else
    cargo ndk \
      "${cargo_ndk_targets[@]}" \
      -o "$output_dir" \
      build -p pars-bridge
  fi
}

build_ios_target() {
  local target="$1"
  local profile="$2"
  local dir
  dir="$(profile_dir "$profile")"

  rustup target add "$target" >&2
  cd "$REPO_ROOT"
  run_cargo_build "$profile" --target "$target"
  printf '%s\n' "${REPO_ROOT}/target/${target}/${dir}/libpars_bridge.a"
}

build_ios() {
  local profile="${PARS_IOS_PROFILE:-$PROFILE}"
  local output_dir="${PARS_IOS_OUTPUT_DIR:-${GUI_DIR}/build/native/ios}"
  local headers="${SCRIPT_DIR}/include"
  mkdir -p "$output_dir"

  local device_lib
  device_lib="$(build_ios_target aarch64-apple-ios "$profile")"
  cp "$device_lib" "${output_dir}/libpars_bridge_ios_device.a"

  local sim_libs=()
  if rustup target add aarch64-apple-ios-sim >/dev/null 2>&1; then
    sim_libs+=("$(build_ios_target aarch64-apple-ios-sim "$profile")")
  fi
  if rustup target add x86_64-apple-ios >/dev/null 2>&1; then
    sim_libs+=("$(build_ios_target x86_64-apple-ios "$profile")")
  fi

  if command -v xcodebuild >/dev/null 2>&1 && command -v lipo >/dev/null 2>&1; then
    rm -rf "${output_dir}/pars_bridge.xcframework"
    local sim_lib="${output_dir}/libpars_bridge_ios_sim.a"
    if [ "${#sim_libs[@]}" -gt 0 ]; then
      lipo -create "${sim_libs[@]}" -output "$sim_lib"
      xcodebuild -create-xcframework \
        -library "$device_lib" -headers "$headers" \
        -library "$sim_lib" -headers "$headers" \
        -output "${output_dir}/pars_bridge.xcframework"
    else
      xcodebuild -create-xcframework \
        -library "$device_lib" -headers "$headers" \
        -output "${output_dir}/pars_bridge.xcframework"
    fi
  else
    cp "$device_lib" "${output_dir}/libpars_bridge_ios_device.a"
    for lib in "${sim_libs[@]}"; do
      cp "$lib" "${output_dir}/$(basename "$(dirname "$(dirname "$lib")")")_libpars_bridge.a"
    done
  fi
}

case "$MODE" in
  linux)
    build_linux
    ;;
  android)
    build_android
    ;;
  ios)
    build_ios
    ;;
  *)
    usage
    exit 2
    ;;
esac
