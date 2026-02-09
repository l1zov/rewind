#!/usr/bin/env bash

set -euo pipefail

APP_NAME="Rewind"
BUNDLE_ID="com.rewind.app"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
VERSION_FILE="${PROJECT_ROOT}/VERSION"

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
  echo "Usage: $0 [--version N|N]" >&2
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

if [[ ! "${VERSION}" =~ ^[0-9]+$ ]]; then
  echo "version must be an integer like 3 (found '${VERSION}')" >&2
  exit 1
fi

VERSION_TAG="v${VERSION}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION_TAG}.dmg"
STAGING_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}.XXXXXX")"
APP_BUNDLE="${STAGING_ROOT}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
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

mkdir -p "${DIST_DIR}"

echo "Cleaning ${DIST_DIR}..."
shopt -s nullglob dotglob
for path in "${DIST_DIR}"/*; do
  remove_path "${path}" "dist entry" || exit 1
done
shopt -u dotglob nullglob

echo "Building ${APP_NAME} in release mode..."
swift build -c release --package-path "${PROJECT_ROOT}" --product "${APP_NAME}"

BIN_DIR="$(swift build -c release --package-path "${PROJECT_ROOT}" --show-bin-path)"
EXECUTABLE_PATH="${BIN_DIR}/${APP_NAME}"

if [[ ! -x "${EXECUTABLE_PATH}" ]]; then
  echo "built executable not found at ${EXECUTABLE_PATH}" >&2
  exit 1
fi

echo "Creating app bundle..."
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${EXECUTABLE_PATH}" "${MACOS_DIR}/${APP_NAME}"

ICON_FILE=""
if [[ -f "${PROJECT_ROOT}/Resources/AppIcon.icns" ]]; then
  cp "${PROJECT_ROOT}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
  ICON_FILE="AppIcon"
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
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
EOF

if [[ -n "${ICON_FILE}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${ICON_FILE}" "${CONTENTS_DIR}/Info.plist"
fi

echo "Creating drag-and-drop DMG..."
remove_path "${DMG_PATH}" "disk image" || exit 1
DMG_STAGING_DIR="${STAGING_ROOT}/dmg"
mkdir -p "${DMG_STAGING_DIR}"
ditto "${APP_BUNDLE}" "${DMG_STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING_DIR}" -ov -format UDZO "${DMG_PATH}" >/dev/null

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
