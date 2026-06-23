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

PROFILE="${PARS_ANDROID_PROFILE:-release}"
CARGO_PROFILE_DIR="release"
CARGO_ARGS=(--release)
if [ "${PROFILE}" = "debug" ]; then
  CARGO_PROFILE_DIR="debug"
  CARGO_ARGS=()
fi

TARGETS="${PARS_ANDROID_TARGETS:-aarch64-linux-android armv7-linux-androideabi x86_64-linux-android}"
OUTPUT_DIR="${PARS_ANDROID_OUTPUT_DIR:-}"
ANDROID_API_LEVEL="${PARS_ANDROID_API_LEVEL:-21}"

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

  export CC_aarch64_linux_android="${toolchain_bin}/aarch64-linux-android${ANDROID_API_LEVEL}-clang"
  export AR_aarch64_linux_android="${llvm_ar}"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="${CC_aarch64_linux_android}"

  export CC_armv7_linux_androideabi="${toolchain_bin}/armv7a-linux-androideabi${ANDROID_API_LEVEL}-clang"
  export AR_armv7_linux_androideabi="${llvm_ar}"
  export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="${CC_armv7_linux_androideabi}"

  export CC_x86_64_linux_android="${toolchain_bin}/x86_64-linux-android${ANDROID_API_LEVEL}-clang"
  export AR_x86_64_linux_android="${llvm_ar}"
  export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="${CC_x86_64_linux_android}"

  export CC_i686_linux_android="${toolchain_bin}/i686-linux-android${ANDROID_API_LEVEL}-clang"
  export AR_i686_linux_android="${llvm_ar}"
  export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="${CC_i686_linux_android}"
}

configure_android_toolchain

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

for target in $TARGETS; do
  if [ "${#CARGO_ARGS[@]}" -eq 0 ]; then
    cargo build -p pars-bridge --target "$target"
  else
    cargo build -p pars-bridge --target "$target" "${CARGO_ARGS[@]}"
  fi

  if [ -n "${OUTPUT_DIR}" ]; then
    abi="$(abi_for_target "$target")"
    source_lib="target/${target}/${CARGO_PROFILE_DIR}/libpars_bridge.so"
    dest_dir="${OUTPUT_DIR}/${abi}"

    if [ ! -f "${source_lib}" ]; then
      echo "error: pars_bridge shared library not found at ${source_lib}" >&2
      exit 1
    fi

    mkdir -p "${dest_dir}"
    cp "${source_lib}" "${dest_dir}/libpars_bridge.so"
  fi
done
