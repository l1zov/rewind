#!/usr/bin/env bash

set -euo pipefail

APP_NAME="Rewind"
BUNDLE_ID="com.rewind.app"

# Signing / notarization configuration (all optional).
#
# SIGNING_IDENTITY: a "Developer ID Application" identity produces a
#   distributable, notarizable build. Leave unset for a local ad-hoc build
#   (the previous default behaviour). Example:
#     export SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#
# NOTARY_PROFILE: a notarytool keychain profile name. When set (and a real
#   identity is used), the app and DMG are uploaded to Apple, notarized and
#   stapled. Create the profile once with:
#     xcrun notarytool store-credentials "RewindNotary" \
#       --apple-id "you@example.com" --team-id "TEAMID" \
#       --password "app-specific-password"
#   then: export NOTARY_PROFILE="RewindNotary"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

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

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "not semantic" >&2
  exit 1
fi

VERSION_TAG="v${VERSION}"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION_TAG}.dmg"
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

# Sign a single item. With a real Developer ID identity this applies the
# hardened runtime + a secure timestamp (both required for notarization); with
# the ad-hoc identity ("-") it matches the previous local-build behaviour.
#   sign_path <path> <label> [entitlements] [harden=yes|no]
sign_path() {
  local target_path="$1"
  local label="$2"
  local entitlements="${3:-}"
  local harden="${4:-yes}"

  if ! command -v codesign >/dev/null 2>&1; then
    echo "codesign is required to sign ${label}" >&2
    return 1
  fi

  local opts=("--force" "--sign" "${SIGNING_IDENTITY}")
  if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    opts+=("--timestamp=none")
  else
    opts+=("--timestamp")
    if [[ "${harden}" == "yes" ]]; then
      opts+=("--options" "runtime")
    fi
  fi
  if [[ -n "${entitlements}" ]]; then
    opts+=("--entitlements" "${entitlements}")
  fi

  echo "Signing ${label} (identity: ${SIGNING_IDENTITY})..."
  codesign "${opts[@]}" "${target_path}"
}

# Sign the Sparkle framework inside-out: nested helpers must be signed before
# the framework that contains them, or notarization rejects the build.
sign_sparkle() {
  local framework="$1"
  local versioned="${framework}/Versions/B"

  if [[ -d "${versioned}/XPCServices" ]]; then
    shopt -s nullglob
    for xpc in "${versioned}/XPCServices/"*.xpc; do
      sign_path "${xpc}" "Sparkle $(basename "${xpc}")"
    done
    shopt -u nullglob
  fi
  if [[ -d "${versioned}/Updater.app" ]]; then
    sign_path "${versioned}/Updater.app" "Sparkle Updater.app"
  fi
  if [[ -e "${versioned}/Autoupdate" ]]; then
    sign_path "${versioned}/Autoupdate" "Sparkle Autoupdate"
  fi
  sign_path "${framework}" "Sparkle framework"
}

# Upload to Apple's notary service and staple the ticket. No-op unless a notary
# profile is configured. notarytool accepts .zip/.dmg/.pkg, so a bare .app is
# zipped first; the ticket is then stapled onto the original .app.
notarize_and_staple() {
  local target_path="$1"
  local label="$2"

  if [[ -z "${NOTARY_PROFILE}" ]]; then
    return 0
  fi
  if [[ "${SIGNING_IDENTITY}" == "-" ]]; then
    echo "Skipping notarization of ${label}: NOTARY_PROFILE is set but SIGNING_IDENTITY is ad-hoc." >&2
    return 0
  fi
  if ! command -v xcrun >/dev/null 2>&1; then
    echo "xcrun is required to notarize ${label}" >&2
    return 1
  fi

  local submit_path="${target_path}"
  if [[ "${target_path}" == *.app ]]; then
    submit_path="${STAGING_ROOT}/$(basename "${target_path}").zip"
    echo "Zipping ${label} for notarization..."
    ditto -c -k --keepParent "${target_path}" "${submit_path}"
  fi

  echo "Notarizing ${label} (uploads to Apple and waits for the result)..."
  xcrun notarytool submit "${submit_path}" --keychain-profile "${NOTARY_PROFILE}" --wait
  echo "Stapling notarization ticket to ${label}..."
  xcrun stapler staple "${target_path}"
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

# Strip local symbols so the shipped binary doesn't leak internal function,
# type and property names via its symbol table. Must run before code signing.
# -x removes non-global symbols while keeping the binary valid and signable.
echo "Stripping symbols from ${APP_NAME}..."
strip -x "${MACOS_DIR}/${APP_NAME}"

ICON_FILE=""
if [[ -f "${PROJECT_ROOT}/Resources/AppIcon.icns" ]]; then
  cp "${PROJECT_ROOT}/Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
  ICON_FILE="AppIcon"
fi

if [[ -d "${PROJECT_ROOT}/Resources/Sounds" ]]; then
  cp -R "${PROJECT_ROOT}/Resources/Sounds/" "${RESOURCES_DIR}/"
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
  <key>SUFeedURL</key>
  <string>https://l1zov.github.io/rewind/appcast.xml</string>
  <key>SUPublicEDKey</key>
  <string>d0qDhMh7Acak94tDqDkPiyYj9U01VMshN1MZo7T6uD4=</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>Rewind needs screen capture access to record your screen.</string>
</dict>
</plist>
EOF

if [[ -n "${ICON_FILE}" ]]; then
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${ICON_FILE}" "${CONTENTS_DIR}/Info.plist"
fi

SPARKLE_FRAMEWORK_SRC="${PROJECT_ROOT}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ -d "${SPARKLE_FRAMEWORK_SRC}" ]]; then
  ditto "${SPARKLE_FRAMEWORK_SRC}" "${FRAMEWORKS_DIR}/Sparkle.framework"
  sign_sparkle "${FRAMEWORKS_DIR}/Sparkle.framework"
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
</dict>
</plist>
EOF

# Sign the app last (inside-out): its nested Sparkle framework is already signed.
sign_path "${APP_BUNDLE}" "app bundle" "${STAGING_ROOT}/Rewind.entitlements"
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"

# Notarize + staple the app before packaging so the extracted .app validates
# offline. No-op for ad-hoc builds.
notarize_and_staple "${APP_BUNDLE}" "app bundle"

echo "Creating drag-and-drop DMG..."
remove_path "${DMG_PATH}" "disk image" || exit 1
DMG_STAGING_DIR="${STAGING_ROOT}/dmg"
mkdir -p "${DMG_STAGING_DIR}"
ditto "${APP_BUNDLE}" "${DMG_STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${DMG_STAGING_DIR}/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder "${DMG_STAGING_DIR}" -ov -format UDZO "${DMG_PATH}" >/dev/null
# A disk image carries no runtime, so sign it without the hardened-runtime flag.
sign_path "${DMG_PATH}" "disk image" "" "no"
notarize_and_staple "${DMG_PATH}" "disk image"

if [[ "${SIGNING_IDENTITY}" != "-" && -n "${NOTARY_PROFILE}" ]]; then
  echo "Verifying Gatekeeper acceptance..."
  spctl --assess --type open --context context:primary-signature --verbose=2 "${DMG_PATH}" || \
    echo "Warning: spctl assessment did not pass; check signing/notarization output above." >&2
fi

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
