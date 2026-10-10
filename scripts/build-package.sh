#!/usr/bin/env bash

set -euo pipefail

APP_NAME="Rewind"
BUNDLE_ID="com.rewind.app"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
VERSION_FILE="${PROJECT_ROOT}/VERSION"

POSTHOG_ENV_FILE="${PROJECT_ROOT}/.posthog.env"
if [[ -f "${POSTHOG_ENV_FILE}" ]]; then
  echo "Loading PostHog config from ${POSTHOG_ENV_FILE}"
  # shellcheck disable=SC1090
  source "${POSTHOG_ENV_FILE}"
fi

POSTHOG_HOST="${POSTHOG_HOST:-https://eu.i.posthog.com}"
VERSION_OVERRIDE=""
if [[ $# -gt 0 ]]; then
  case "$1" in
    -v|--version)
      if [[ $# -lt 2 ]]; then
        echo "missing value for $1" >&2
        exit 1
      fi
      VERSION_OVERRIDE="$2"
      shift 2
      ;;
    *)
      VERSION_OVERRIDE="$1"
      shift
      ;;
  esac
fi

if [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--version X.Y.Z|vX.Y.Z]" >&2
  exit 1
fi

if [[ -n "${VERSION_OVERRIDE}" ]]; then
  VERSION="${VERSION_OVERRIDE}"
else
  if [[ ! -f "${VERSION_FILE}" ]]; then
    echo "missing version file at ${VERSION_FILE}" >&2
    exit 1
  fi

  VERSION="$(tr -d '[:space:]' < "${VERSION_FILE}")"
fi

VERSION="${VERSION#v}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "not semantic" >&2
  exit 1
fi


VERSION_TAG="v${VERSION}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION_TAG}.dmg"
INSTALLER_DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION_TAG}-installer.dmg"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.XXXXXX")"
APP_BUNDLE="${STAGING_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"
DIST_APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"

cleanup() {
  rm -rf "${STAGING_ROOT}"
}
trap cleanup EXIT

remove_path() {
  local path="$1"
  local label="$2"

  if [[ -e "${path}" ]]; then
    if rm -rf "${path}" 2>/dev/null; then
      return 0
    fi

    local stale_path="${path}.stale.$(date +%s)"
    echo "Warning: could not remove ${label} at ${path}; moving it to ${stale_path}"
    if mv "${path}" "${stale_path}"; then
      return 0
    fi

    echo "unable to clean ${label} at ${path}" >&2
    return 1
  fi

  return 0
}

adhoc_sign() {
  local target_path="$1"
  local label="$2"
  local entitlements="${3:-}"

  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign is required to sign ${label}" >&2
    return 1
  fi

  local opts=("--force" "--deep" "--sign" "-" "--timestamp=none")
  if [[ -n "${entitlements}" ]]; then
    opts+=("--entitlements" "${entitlements}" "--options" "runtime")
  fi

  echo "Adhoc signing ${label}..."
  codesign "${opts[@]}" "${target_path}"
  codesign --verify --deep --strict --verbose=2 "${target_path}"
}

mkdir -p "${DIST_DIR}"

echo "Cleaning ${DIST_DIR}..."
shopt -s nullglob dotglob
for path in "${DIST_DIR}"/*; do
  remove_path "${path}" "dist entry" || exit 1
done
shopt -u dotglob nullglob

echo "Building ${APP_NAME} in release mode..."
swift build -c release --package-path "${PROJECT_ROOT}" --product "${APP_NAME}" --arch arm64 --arch x86_64

BIN_DIR="$(swift build -c release --package-path "${PROJECT_ROOT}" --show-bin-path --arch arm64 --arch x86_64)"
EXECUTABLE_PATH="${BIN_DIR}/${APP_NAME}"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "built executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi


echo "Creating app bundle..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}" "${FRAMEWORKS_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"

ICON_FILE=""
if [[ -f "${PROJECT_ROOT}/Resources/AppIcon.icns" ]]; then
  cp "${PROJECT_ROOT}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
  ICON_FILE="AppIcon"
fi

if [[ -d "${PROJECT_ROOT}/Resources/Sounds" ]]; then
  cp -R "${PROJECT_ROOT}/Resources/Sounds/" "${RESOURCES_DIR}/"
fi

if [[ -f "${PROJECT_ROOT}/Resources/games.tsv" ]]; then
  cp "${PROJECT_ROOT}/Resources/games.tsv" "${RESOURCES_DIR}/games.tsv"
fi

if [[ -d "${PROJECT_ROOT}/Resources/Tour" ]]; then
  cp -R "${PROJECT_ROOT}/Resources/Tour/" "${RESOURCES_DIR}/"
fi

cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>DTCompiler</key>
  <string>com.apple.compilers.llvm.clang.1_0</string>
  <key>DTPlatformBuild</key>
  <string>24A335</string>
  <key>DTPlatformName</key>
  <string>macosx</string>
  <key>DTPlatformVersion</key>
  <string>16.0</string>
  <key>DTSDKBuild</key>
  <string>24A335</string>
  <key>DTSDKName</key>
  <string>macosx16.0</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>https://l1zov.github.io/rewind/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>d0qDhMh7Acak94tDqDkPiyYj9U01VMshN1MZo7T6uD4=</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Rewind needs screen capture access to record your screen.</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Rewind needs microphone access to record microphone audio.</string>
</dict>
</plist>
EOF

if [[ -n "${ICON_FILE}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${ICON_FILE}" "${CONTENTS_DIR}/Info.plist"
fi

if [[ -n "${POSTHOG_PROJECT_TOKEN:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :PostHogProjectToken string ${POSTHOG_PROJECT_TOKEN}" "${CONTENTS_DIR}/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :PostHogHost string ${POSTHOG_HOST}" "${CONTENTS_DIR}/Info.plist"
  echo "Injected privacy-preserving PostHog configuration into Info.plist"
else
  echo "POSTHOG_PROJECT_TOKEN not set; analytics will be disabled in this build."
fi


SPARKLE_FRAMEWORK_SRC="${PROJECT_ROOT}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "${SPARKLE_FRAMEWORK_SRC}" ]]; then
  ditto "${SPARKLE_FRAMEWORK_SRC}" "${FRAMEWORKS_DIR}/Sparkle.framework"
  adhoc_sign "${FRAMEWORKS_DIR}/Sparkle.framework" "Sparkle framework"
else
  echo "Warning: Sparkle.framework not found in .build/artifacts" >&2
fi

cat > "${STAGING_ROOT}/Rewind.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
EOF

adhoc_sign "${APP_BUNDLE}" "app bundle" "${STAGING_ROOT}/Rewind.entitlements"

echo "Creating drag-and-drop DMG..."
remove_path "${DMG_PATH}" "disk image" || exit 1
APP_DMG_STAGING_DIR="${STAGING_ROOT}/dmg"
mkdir -p "${APP_DMG_STAGING_DIR}"
ditto "${APP_BUNDLE}" "${APP_DMG_STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${APP_DMG_STAGING_DIR}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${APP_DMG_STAGING_DIR}" -ov -format UDZO "${DMG_PATH}" >/dev/null
adhoc_sign "${DMG_PATH}" "disk image"

echo "Creating installer DMG..."
remove_path "${INSTALLER_DMG_PATH}" "installer disk image" || exit 1
INSTALLER_STAGING_DIR="${STAGING_ROOT}/installer-dmg"
mkdir -p "${INSTALLER_STAGING_DIR}"

INSTALLER_NAME="Install ${APP_NAME}"
INSTALLER_APP="${INSTALLER_STAGING_DIR}/${INSTALLER_NAME}.app"
INSTALLER_CONTENTS="${INSTALLER_APP}/Contents"
INSTALLER_MACOS="${INSTALLER_CONTENTS}/MacOS"
INSTALLER_RESOURCES="${INSTALLER_CONTENTS}/Resources"

mkdir -p "${INSTALLER_MACOS}" "${INSTALLER_RESOURCES}"

ditto "${APP_BUNDLE}" "${INSTALLER_RESOURCES}/${APP_NAME}.app"

if [[ -f "${PROJECT_ROOT}/Resources/AppIcon.icns" ]]; then
  cp "${PROJECT_ROOT}/Resources/AppIcon.icns" "${INSTALLER_RESOURCES}/AppIcon.icns"
fi

cat > "${INSTALLER_CONTENTS}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>installer</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}.installer</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${INSTALLER_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

cat > "${INSTALLER_MACOS}/installer" <<'EOF'
#!/bin/bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="Rewind"
BUNDLE_ID="com.rewind.app"
APP_SOURCE="$(cd "${SCRIPT_DIR}/../Resources/${APP_NAME}.app" 2>/dev/null && pwd || true)"

if [[ -z "${APP_SOURCE}" || ! -d "${APP_SOURCE}" ]]; then
  osascript -e "display alert \"${APP_NAME} Installer Error\" message \"Could not find ${APP_NAME}.app inside the installer bundle.\" as critical"
  exit 1
fi

DEST_DIR="/Applications"
TARGET_APP="${DEST_DIR}/${APP_NAME}.app"

CONFIRM=$(osascript -e "button returned of (display dialog \"Install ${APP_NAME} to /Applications?\" with title \"${APP_NAME} Installer\" buttons {\"Cancel\", \"Install\"} default button \"Install\")" 2>/dev/null || echo "Cancel")

if [[ "${CONFIRM}" != "Install" ]]; then
  exit 0
fi

do_install() {
  local target="$1"
  local source="$2"
  local bundle="$3"

  killall "${APP_NAME}" 2>/dev/null || true
  rm -rf "${target}"
  ditto "${source}" "${target}"

  xattr -cr "${target}" 2>/dev/null || true
  xattr -dr com.apple.quarantine "${target}" 2>/dev/null || true
  chmod -R 755 "${target}" 2>/dev/null || true

  tccutil reset ScreenCapture "${bundle}" 2>/dev/null || true
  tccutil reset Microphone "${bundle}" 2>/dev/null || true
  tccutil reset Accessibility "${bundle}" 2>/dev/null || true
}

if [[ ! -w "${DEST_DIR}" ]] || [[ -e "${TARGET_APP}" && ! -w "${TARGET_APP}" ]]; then
  ADMIN_SCRIPT="killall ${APP_NAME} 2>/dev/null || true; rm -rf '${TARGET_APP}' && ditto '${APP_SOURCE}' '${TARGET_APP}' && xattr -cr '${TARGET_APP}' 2>/dev/null || true; xattr -dr com.apple.quarantine '${TARGET_APP}' 2>/dev/null || true; chmod -R 755 '${TARGET_APP}' 2>/dev/null || true; tccutil reset ScreenCapture ${BUNDLE_ID} 2>/dev/null || true; tccutil reset Microphone ${BUNDLE_ID} 2>/dev/null || true; tccutil reset Accessibility ${BUNDLE_ID} 2>/dev/null || true"

  if ! osascript -e "do shell script \"${ADMIN_SCRIPT}\" with administrator privileges" 2>/dev/null; then
    osascript -e "display alert \"Installation Cancelled\" message \"Administrator privileges were required but not granted.\" as critical"
    exit 1
  fi
else
  do_install "${TARGET_APP}" "${APP_SOURCE}" "${BUNDLE_ID}"
fi

if [[ ! -d "${TARGET_APP}" || ! -x "${TARGET_APP}/Contents/MacOS/${APP_NAME}" ]]; then
  osascript -e "display alert \"Installation Failed\" message \"Failed to install ${APP_NAME} to /Applications.\" as critical"
  exit 1
fi

CHOICE=$(osascript -e "button returned of (display dialog \"${APP_NAME} has been successfully installed!\" with title \"Installation Complete\" buttons {\"Done\", \"Open ${APP_NAME}\"} default button \"Open ${APP_NAME}\")" 2>/dev/null || echo "Done")

if [[ "${CHOICE}" == "Open ${APP_NAME}" ]]; then
  open "${TARGET_APP}"
fi

MOUNT_POINT="$(df "${SCRIPT_DIR}" 2>/dev/null | tail -1 | awk '{print $NF}')"
if [[ "${MOUNT_POINT}" =~ ^/Volumes/ ]]; then
  (sleep 1 && diskutil eject "${MOUNT_POINT}" >/dev/null 2>&1) &
fi

exit 0
EOF

chmod +x "${INSTALLER_MACOS}/installer"
adhoc_sign "${INSTALLER_APP}" "installer app bundle"

hdiutil create -volname "${INSTALLER_NAME}" -srcfolder "${INSTALLER_STAGING_DIR}" -ov -format UDZO "${INSTALLER_DMG_PATH}" >/dev/null
adhoc_sign "${INSTALLER_DMG_PATH}" "installer disk image"

echo "Publishing app bundle to dist..."
APP_BUNDLE_PUBLISHED="false"
if [[ -e "${DIST_APP_BUNDLE}" && ! -w "${DIST_APP_BUNDLE}" ]]; then
  echo "Warning: ${DIST_APP_BUNDLE} is not writable; skipping app bundle publish."
elif remove_path "${DIST_APP_BUNDLE}" "existing dist app bundle"; then
  ditto "${APP_BUNDLE}" "${DIST_APP_BUNDLE}"
  APP_BUNDLE_PUBLISHED="true"
else
  echo "Warning: could not replace ${DIST_APP_BUNDLE}; packaged artifacts are still valid."
fi

echo "Done."
