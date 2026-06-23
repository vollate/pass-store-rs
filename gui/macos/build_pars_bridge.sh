#!/usr/bin/env bash
set -euo pipefail

if ! command -v cargo >/dev/null 2>&1 && [ -f "${HOME}/.cargo/env" ]; then
  # Xcode does not always inherit the interactive shell PATH.
  # shellcheck disable=SC1091
  . "${HOME}/.cargo/env"
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to build pars_bridge" >&2
  exit 1
fi

REPO_ROOT="$(cd "${PROJECT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

CARGO_ARGS=()
CARGO_PROFILE_DIR="debug"
case "${CONFIGURATION:-Debug}" in
  Release)
    CARGO_ARGS+=(--release)
    CARGO_PROFILE_DIR="release"
    ;;
esac

ARTIFACT_DIR="target/${CARGO_PROFILE_DIR}"
if [ -n "${PARS_BRIDGE_CARGO_TARGET:-}" ]; then
  CARGO_ARGS+=(--target "${PARS_BRIDGE_CARGO_TARGET}")
  ARTIFACT_DIR="target/${PARS_BRIDGE_CARGO_TARGET}/${CARGO_PROFILE_DIR}"
fi

if [ "${#CARGO_ARGS[@]}" -eq 0 ]; then
  cargo build -p pars-bridge
else
  cargo build -p pars-bridge "${CARGO_ARGS[@]}"
fi

SOURCE_LIB="${REPO_ROOT}/${ARTIFACT_DIR}/libpars_bridge.dylib"
FRAMEWORK_DIR="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/pars_bridge.framework"
FRAMEWORK_VERSION_DIR="${FRAMEWORK_DIR}/Versions/A"
FRAMEWORK_RESOURCES_DIR="${FRAMEWORK_VERSION_DIR}/Resources"

if [ ! -f "${SOURCE_LIB}" ]; then
  echo "error: pars_bridge dylib not found at ${SOURCE_LIB}" >&2
  exit 1
fi

rm -rf "${FRAMEWORK_DIR}"
mkdir -p "${FRAMEWORK_RESOURCES_DIR}"
cp "${SOURCE_LIB}" "${FRAMEWORK_VERSION_DIR}/pars_bridge"
install_name_tool -id "@rpath/pars_bridge.framework/pars_bridge" "${FRAMEWORK_VERSION_DIR}/pars_bridge"
cat > "${FRAMEWORK_RESOURCES_DIR}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>pars_bridge</string>
	<key>CFBundleIdentifier</key>
	<string>dev.pars.bridge</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>pars_bridge</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>NSPrincipalClass</key>
	<string></string>
</dict>
</plist>
PLIST
ln -s A "${FRAMEWORK_DIR}/Versions/Current"
ln -s Versions/Current/pars_bridge "${FRAMEWORK_DIR}/pars_bridge"
ln -s Versions/Current/Resources "${FRAMEWORK_DIR}/Resources"

if [ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" "${FRAMEWORK_DIR}"
fi
