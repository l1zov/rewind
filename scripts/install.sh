#!/usr/bin/env bash
#
# Rewind installer — downloads the latest release and installs it to /Applications.
#
# It reads the app's own Sparkle appcast to find the newest version, so it always
# matches what Rewind's built-in updater would fetch, and pulls the DMG from the
# GitHub release the appcast points at.
#
# Usage:  ./install.sh          (or: curl -fsSL <raw-url>/install.sh | bash)
#
# Note: this trusts the HTTPS download + the appcast's advertised byte size. The
# in-app updater additionally verifies the Sparkle EdDSA signature, which is
# stronger — prefer letting the app self-update once it's installed.

set -euo pipefail

APPCAST="https://l1zov.github.io/rewind/appcast.xml"
APP="/Applications/Rewind.app"
STAGE="/Applications/.Rewind.app.new"   # staged copy, swapped in only once verified
VOL=""
TMP=""

# Styling — rich output on a terminal, plain text when piped/redirected.
if [ -t 1 ]; then
	BOLD=$'\033[1m'; DIM=$'\033[2m'; OFF=$'\033[0m'
	RED=$'\033[91m'; WHITE=$'\033[97m'; GREEN=$'\033[92m'; YELLOW=$'\033[93m'
	BG_RED=$'\033[101m'   # bright-red background — the logo field
	C_BAR=$'\033[91m'     # red — the curl download bar
else
	BOLD=""; DIM=""; OFF=""; RED=""; WHITE=""; GREEN=""; YELLOW=""; BG_RED=""; C_BAR=""
fi

# ASCII-art app icon (user-supplied).
LOGO=(
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-------------------------------[97m@@@@@@@[91m----------------[97m@@@@[91m-------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m:------------[97m@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m:---------[97m@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m------:[97m@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m---:[97m@@@@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m:[97m@@@@@@@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@@@@@@@@@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m:[97m@@@@@@@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m-[97m@@[91m-[97m@@@@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m-[97m@@@@@[91m-[97m@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m-----[97m@@@@@@@@@@@@@@@[91m.------------------------------[0m'
$'[91m------------------------------:[97m@@@@@@@[91m----------[97m@@@@@@@@@@[91m:------------------------------[0m'
$'[91m-------------------------------[97m@@@@@@@[91m-------------[97m@@@@@@[91m.[97m@[91m------------------------------[0m'
$'[91m-------------------------------[97m@@@@@@@[91m---------------[97m@@@@[91m--------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
$'[91m-----------------------------------------------------------------------------------------[0m'
)

banner() {
	if [ -t 1 ]; then
		local row
		printf '\n'
		for row in "${LOGO[@]}"; do
			printf '  %s\n' "$row"
		done
		printf '\n     %s=[ Rewind · Instant-Replay Installer ]=%s\n' "$BOLD$RED" "$OFF"
		printf '     %sgithub.com/l1zov/rewind%s\n\n' "$DIM" "$OFF"
	else
		printf '\nRewind installer\n\n'
	fi
}
step() { printf '  %s➜%s  %s%s%s\n' "$BOLD$RED" "$OFF" "$WHITE" "$*" "$OFF"; }
ok()   { printf '\n  %s✔%s  %s%s%s\n\n' "$BOLD$GREEN" "$OFF" "$BOLD$WHITE" "$*" "$OFF"; }
warn() { printf '  %s!%s  %s%s%s\n' "$BOLD$YELLOW" "$OFF" "$WHITE" "$*" "$OFF" >&2; }
die()  { printf '\n  %s✖%s  %s%s%s\n\n' "$BOLD$RED" "$OFF" "$WHITE" "$*" "$OFF" >&2; exit 1; }

cleanup() {
	[ -n "$VOL" ] && diskutil eject "$VOL" >/dev/null 2>&1 || true
	[ -n "$TMP" ] && rm -rf "$TMP" 2>/dev/null || true
	[ -e "$STAGE" ] && rm -rf "$STAGE" 2>/dev/null || true
}
trap cleanup EXIT

# --- preflight ---------------------------------------------------------------
[ "$(uname)" = "Darwin" ]      || die "This installer only runs on macOS."
command -v diskutil >/dev/null || die "diskutil not found (need macOS)."
command -v curl >/dev/null     || die "curl is required."
command -v ditto >/dev/null    || die "ditto is required."
[ -w /Applications ]           || die "/Applications isn't writable. Re-run with: sudo bash \"$0\""

banner

# --- find the latest release -------------------------------------------------
step "Checking for the latest release…"
FEED=$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 "$APPCAST") \
	|| die "Couldn't reach the update feed ($APPCAST)."

# '|| true' so a no-match/SIGPIPE under pipefail doesn't kill the script before
# the explicit emptiness checks below can print a friendly message.
DMG_URL=$(printf '%s' "$FEED"     | grep -oE 'url="[^"]+\.dmg"' | head -1 | sed -E 's/^url="//; s/"$//') || true
LATEST=$(printf '%s' "$FEED"      | grep -oE '<sparkle:version>[^<]+' | head -1 | sed -E 's/.*>//') || true
EXPECT_SIZE=$(printf '%s' "$FEED" | grep -oE 'length="[0-9]+"' | head -1 | grep -oE '[0-9]+') || true
[ -n "$DMG_URL" ] || die "Couldn't find a DMG download URL in the update feed."

# --- skip if already current -------------------------------------------------
if [ -d "$APP" ]; then
	CURRENT=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
	if [ -n "$CURRENT" ] && [ "$CURRENT" = "$LATEST" ]; then
		ok "Rewind $CURRENT is already up to date."
		exit 0
	fi
	[ -n "$CURRENT" ] && step "Updating Rewind ${CURRENT} → ${LATEST}" || step "Installing Rewind ${LATEST}"
else
	step "Installing Rewind ${LATEST:-latest}"
fi

# --- download ----------------------------------------------------------------
TMP=$(mktemp -d) || die "Couldn't create a temp directory."
DMG="$TMP/Rewind.dmg"
step "Downloading $(basename "$DMG_URL")…"
# Draw curl's '#' progress bar in red, then reset the terminal color afterwards.
printf '%s' "$C_BAR" >&2
if ! curl -fL# --retry 3 --retry-delay 2 --connect-timeout 15 "$DMG_URL" -o "$DMG"; then
	printf '%s' "$OFF" >&2
	die "Download failed."
fi
printf '%s' "$OFF" >&2
[ -s "$DMG" ] || die "Downloaded file is empty."

# Integrity: match the byte size the appcast advertised (catches truncation /
# a wrong or corrupted download). Not a substitute for signature verification.
if [ -n "$EXPECT_SIZE" ]; then
	GOT_SIZE=$(stat -f%z "$DMG")
	[ "$GOT_SIZE" = "$EXPECT_SIZE" ] \
		|| die "Download size mismatch (got ${GOT_SIZE}, expected ${EXPECT_SIZE}) — aborting."
fi

# --- install: stage a verified copy, then swap it in -------------------------
step "Installing…"
VOL=$(diskutil image attach --nobrowse --readOnly "$DMG" 2>/dev/null | grep -o '/Volumes/.*' | tail -1) || true
[ -n "$VOL" ] && [ -d "$VOL/Rewind.app" ] || die "Rewind.app not found inside the disk image."

rm -rf "$STAGE"
ditto "$VOL/Rewind.app" "$STAGE" || die "Copy from the disk image failed."
diskutil eject "$VOL" >/dev/null 2>&1 || true
VOL=""

# Verify the staged copy *before* touching the existing install.
[ -x "$STAGE/Contents/MacOS/Rewind" ] || die "Staged app is missing its executable — aborting (existing install untouched)."
STAGE_VER=$(defaults read "$STAGE/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "")
if [ -n "$LATEST" ] && [ -n "$STAGE_VER" ] && [ "$STAGE_VER" != "$LATEST" ]; then
	die "Staged version ($STAGE_VER) doesn't match expected ($LATEST) — aborting (existing install untouched)."
fi

# Swap: the old app only goes away once the new one is staged and verified.
killall Rewind 2>/dev/null || true
rm -rf "$APP"
mv "$STAGE" "$APP" || die "Couldn't move the new app into place."

xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
chmod -R +x "$APP" 2>/dev/null || true

# --- confirm it really installed ---------------------------------------------
[ -x "$APP/Contents/MacOS/Rewind" ] || die "Install verification failed: executable missing after install."
FINAL_VER=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "?")
codesign --verify --strict "$APP" 2>/dev/null || warn "Code-signature check didn't pass — the app may still run, but the download couldn't be validated."

ok "Rewind ${FINAL_VER} installed! Open it from your Applications folder."
