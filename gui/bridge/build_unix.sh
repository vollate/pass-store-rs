#!/usr/bin/env bash
set -euo pipefail

if ! command -v cargo >/dev/null 2>&1 && [ -f "${HOME}/.cargo/env" ]; then
  # Gradle does not always inherit the interactive shell PATH.
  # shellcheck disable=SC1091
  . "${HOME}/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to build pars_bridge" >&2
  exit 1
fi

cd "$(dirname "$0")/../.."

usage() {
  cat >&2 <<'EOF'
usage: gui/bridge/build_unix.sh <android|ios|linux|macos>

Environment:
  PARS_BRIDGE_PROFILE      release or debug for non-Android builds
  PARS_<PLATFORM>_TARGETS  space-separated Rust targets
  PARS_<PLATFORM>_OUTPUT_DIR
                            optional directory for built dynamic libraries

Android also supports:
  PARS_ANDROID_PROFILE     release or debug
  PARS_ANDROID_OUTPUT_DIR  optional jniLibs output directory
  PARS_ANDROID_API_LEVEL   default: 21
  PARS_ANDROID_NDK_HOME    explicit Android NDK path
EOF
}

platform="${1:-}"
if [ -z "${platform}" ]; then
  usage
  exit 2
fi

cargo_args_for_profile() {
  profile="$1"
  if [ "${profile}" = "debug" ]; then
    return 0
  fi
  if [ "${profile}" != "release" ]; then
    echo "error: build profile must be 'debug' or 'release'" >&2
    return 1
  fi
  echo "--release"
}

build_targets() {
  platform_name="$1"
  targets="$2"
  profile="${3:-${PARS_BRIDGE_PROFILE:-release}}"
  cargo_args="$(cargo_args_for_profile "${profile}")"
  cargo_profile_dir="release"
  if [ "${profile}" = "debug" ]; then
    cargo_profile_dir="debug"
  fi

  for target in ${targets}; do
    if [ -n "${cargo_args}" ]; then
      cargo build -p pars-bridge --target "${target}" "${cargo_args}"
    else
      cargo build -p pars-bridge --target "${target}"
    fi

    output_dir="$(platform_output_dir "${platform_name}")"
    if [ -n "${output_dir}" ]; then
      copy_dynamic_library "${platform_name}" "${target}" "${cargo_profile_dir}" "${output_dir}"
    fi
  done
}

platform_output_dir() {
  case "$1" in
    ios)
      echo "${PARS_IOS_OUTPUT_DIR:-}"
      ;;
    linux)
      echo "${PARS_LINUX_OUTPUT_DIR:-}"
      ;;
    macos)
      echo "${PARS_MACOS_OUTPUT_DIR:-}"
      ;;
    *)
      echo ""
      ;;
  esac
}

dynamic_library_name() {
  case "$1" in
    ios | macos)
      echo "libpars_bridge.dylib"
      ;;
    linux)
      echo "libpars_bridge.so"
      ;;
    *)
      echo "error: unsupported dynamic library platform '$1'" >&2
      return 1
      ;;
  esac
}

copy_dynamic_library() {
  platform_name="$1"
  target="$2"
  cargo_profile_dir="$3"
  output_dir="$4"
  library_name="$(dynamic_library_name "${platform_name}")"
  source_lib="target/${target}/${cargo_profile_dir}/${library_name}"

  if [ ! -f "${source_lib}" ]; then
    echo "error: pars_bridge dynamic library not found at ${source_lib}" >&2
    exit 1
  fi

  mkdir -p "${output_dir}"
  cp "${source_lib}" "${output_dir}/${library_name}"
  chmod 755 "${output_dir}/${library_name}"
}

find_android_ndk() {
  for candidate in \
    "${PARS_ANDROID_NDK_HOME:-}" \
    "${ANDROID_NDK_HOME:-}" \
    "${ANDROID_NDK_ROOT:-}"; do
    if [ -n "${candidate}" ] && [ -d "${candidate}/toolchains/llvm/prebuilt" ]; then
      echo "${candidate}"
      return 0
    fi
  done

  sdk_dir=""
  if [ -f "gui/android/local.properties" ]; then
    sdk_dir="$(awk -F= '/^sdk.dir=/ { print $2 }' gui/android/local.properties)"
  fi
  if [ -z "${sdk_dir}" ]; then
    sdk_dir="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  fi
  if [ -n "${sdk_dir}" ] && [ -d "${sdk_dir}/ndk" ]; then
    find "${sdk_dir}/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1
    return 0
  fi

  echo "error: Android NDK not found. Set PARS_ANDROID_NDK_HOME or ANDROID_NDK_HOME." >&2
  return 1
}

find_ndk_toolchain_bin() {
  ndk="$1"
  for host in darwin-arm64 darwin-x86_64 linux-x86_64 windows-x86_64; do
    candidate="${ndk}/toolchains/llvm/prebuilt/${host}/bin"
    if [ -d "${candidate}" ]; then
      echo "${candidate}"
      return 0
    fi
  done

  echo "error: Android NDK LLVM toolchain not found in ${ndk}" >&2
  return 1
}

configure_android_toolchain() {
  ndk="$(find_android_ndk)"
  toolchain_bin="$(find_ndk_toolchain_bin "${ndk}")"
  llvm_ar="${toolchain_bin}/llvm-ar"
  android_api_level="${PARS_ANDROID_API_LEVEL:-21}"

  export CC_aarch64_linux_android="${toolchain_bin}/aarch64-linux-android${android_api_level}-clang"
  export AR_aarch64_linux_android="${llvm_ar}"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${CC_aarch64_linux_android}"

  export CC_armv7_linux_androideabi="${toolchain_bin}/armv7a-linux-androideabi${android_api_level}-clang"
  export AR_armv7_linux_androideabi="${llvm_ar}"
  export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="${CC_armv7_linux_androideabi}"

  export CC_x86_64_linux_android="${toolchain_bin}/x86_64-linux-android${android_api_level}-clang"
  export AR_x86_64_linux_android="${llvm_ar}"
  export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="${CC_x86_64_linux_android}"

  export CC_i686_linux_android="${toolchain_bin}/i686-linux-android${android_api_level}-clang"
  export AR_i686_linux_android="${llvm_ar}"
  export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="${CC_i686_linux_android}"
}

abi_for_target() {
  case "$1" in
    aarch64-linux-android)
      echo "arm64-v8a"
      ;;
    armv7-linux-androideabi)
      echo "armeabi-v7a"
      ;;
    x86_64-linux-android)
      echo "x86_64"
      ;;
    i686-linux-android)
      echo "x86"
      ;;
    *)
      echo "error: unsupported Android target '$1'" >&2
      return 1
      ;;
  esac
}

build_android() {
  configure_android_toolchain

  profile="${PARS_ANDROID_PROFILE:-${PARS_BRIDGE_PROFILE:-release}}"
  cargo_profile_dir="release"
  if [ "${profile}" = "debug" ]; then
    cargo_profile_dir="debug"
  fi
  cargo_args="$(cargo_args_for_profile "${profile}")"

  targets="${PARS_ANDROID_TARGETS:-aarch64-linux-android armv7-linux-androideabi x86_64-linux-android}"
  output_dir="${PARS_ANDROID_OUTPUT_DIR:-}"

  for target in ${targets}; do
    if [ -n "${cargo_args}" ]; then
      cargo build -p pars-bridge --target "${target}" "${cargo_args}"
    else
      cargo build -p pars-bridge --target "${target}"
    fi

    if [ -n "${output_dir}" ]; then
      abi="$(abi_for_target "${target}")"
      source_lib="target/${target}/${cargo_profile_dir}/libpars_bridge.so"
      dest_dir="${output_dir}/${abi}"

      if [ ! -f "${source_lib}" ]; then
        echo "error: pars_bridge shared library not found at ${source_lib}" >&2
        exit 1
      fi

      mkdir -p "${dest_dir}"
      cp "${source_lib}" "${dest_dir}/libpars_bridge.so"
    fi
  done
}

case "${platform}" in
  android)
    build_android
    ;;
  ios)
    build_targets ios "${PARS_IOS_TARGETS:-aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios}"
    ;;
  linux)
    build_targets linux "${PARS_LINUX_TARGETS:-$(rustc -vV | awk '/host:/ { print $2 }')}"
    ;;
  macos)
    build_targets macos "${PARS_MACOS_TARGETS:-$(rustc -vV | awk '/host:/ { print $2 }')}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
