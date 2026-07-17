# Release Hardening & Distribution Guide

This document explains the build hardening applied to Rewind and the one-time
setup needed to produce **signed, notarized** release builds.

> **Reality check.** Rewind is open source (AGPL-3.0). Obfuscation only slows
> down someone inspecting the *binary* — anyone can read the source on GitHub.
> The measures below deter casual binary poking and, more importantly, let you
> ship a **notarized** build so users can't be handed a tampered "Rewind."
> They are not, and cannot be, a lock on the source.

---

## Do you need a paid Apple Developer account?

**No — not for any of the hardening.** Only the *optional* notarization step
(section 2) needs one, and that's an Apple restriction, not something this
project can work around.

| Feature | Paid Apple account? |
|---------|---------------------|
| Reflection/symbol stripping, dead-strip, string obfuscation | **No** (free) |
| Anti-debug guard | **No** (free) |
| Ad-hoc signed DMG (current default) | **No** (free) |
| Notarization (removes the Gatekeeper warning) | **Yes** — $99/yr Apple Developer Program |

A plain `./scripts/build-package.sh 1.2.3` with **no** environment variables set
gives you the full hardening on a free, ad-hoc-signed DMG — exactly how the
project already shipped. The only downside of skipping notarization is that
users hit macOS's "unidentified developer" prompt and open the app via
**right-click → Open** (already documented in the README).

Notarization can't be made free: Apple's notary service only accepts uploads
from a paid membership holding a *Developer ID Application* certificate, which
free Apple IDs cannot obtain. No signing trick, self-signed certificate, or
script change changes that.

---

## 1. What happens automatically (no setup required, no account)

These are baked into `Package.swift` and `scripts/build-package.sh` and apply to
every `swift build -c release` / packaged build:

| Hardening | Where | Effect |
|-----------|-------|--------|
| Blank reflection names | `Package.swift` (`-disable-reflection-names`, release only) | Property/field names removed from `__swift5_reflstr` |
| Strip local symbols | `Package.swift` (`-Xlinker -x`) + `strip -x` in the packager | Symbol-table names removed (measured 3,136 → 1) |
| Dead-code strip | `Package.swift` (`-Xlinker -dead_strip`, release only) | Unreachable code removed |
| String obfuscation | `Sources/Rewind/Utilities/ObfuscatedString.swift` | GitHub URL + Discord ID no longer appear in `strings` |

Nothing to configure. A plain `./scripts/build-package.sh 1.2.3` still produces
an **ad-hoc-signed** DMG exactly like before if you set none of the variables
below.

### What obfuscation does *not* remove
Swift embeds type names (`CaptureManager`, `AppState`, …) in nominal type
descriptors that the runtime needs. No compiler flag or `strip` removes them;
only renaming the types in source would, which is fragile and not worth it.

---

## 2. Developer ID signing + notarization (optional — needs a paid account)

Skip this entire section if you don't have a paid Apple Developer account; the
build works fine without it (see above). If you do, this is the highest-value
step: it lets macOS Gatekeeper trust the app, removes the "unidentified
developer" wall, and protects users from tampered redistributions.

### Prerequisites
1. A paid **Apple Developer Program** membership.
2. A **Developer ID Application** certificate installed in your login keychain
   (Xcode → Settings → Accounts → Manage Certificates → "+" → Developer ID
   Application). Confirm it's present:
   ```bash
   security find-identity -v -p codesigning
   ```
   Copy the full identity string, e.g.
   `Developer ID Application: Jane Doe (ABCDE12345)`.
3. An **app-specific password** for your Apple ID
   (<https://account.apple.com> → Sign-In and Security → App-Specific Passwords).

### One-time notary credential setup
Store your notary credentials in the keychain once, under a profile name:
```bash
xcrun notarytool store-credentials "RewindNotary" \
  --apple-id "you@example.com" \
  --team-id "ABCDE12345" \
  --password "abcd-efgh-ijkl-mnop"   # the app-specific password
```

### Build a signed + notarized release
```bash
export SIGNING_IDENTITY="Developer ID Application: Jane Doe (ABCDE12345)"
export NOTARY_PROFILE="RewindNotary"

./scripts/build-package.sh 1.2.3
```

The packager will now:
1. Sign the Sparkle framework **inside-out** (XPC services → `Updater.app` →
   `Autoupdate` → framework). Missing this is the #1 cause of notarization
   failure.
2. Sign the app with the **hardened runtime** + secure timestamp + entitlements.
3. **Notarize + staple** the app (so the extracted `.app` validates offline).
4. Build, sign, notarize, and staple the DMG.
5. Run an `spctl` Gatekeeper assessment.

### Verify the result
```bash
spctl --assess --type open --context context:primary-signature -v dist/Rewind-v1.2.3.dmg
# expected: "accepted" + "source=Notarized Developer ID"

xcrun stapler validate dist/Rewind-v1.2.3.dmg
# expected: "The validate action worked!"
```

If you set `NOTARY_PROFILE` but leave `SIGNING_IDENTITY` ad-hoc, notarization is
skipped with a warning (Apple can't notarize ad-hoc builds).

---

## 3. Anti-debug guard (optional, OFF by default)

`Sources/Rewind/Utilities/RuntimeGuard.swift` can issue `PT_DENY_ATTACH` to
refuse debugger attachment. It is **disabled** unless you opt in.

- It interferes with debuggers/crash tooling and is trivially patched out, so on
  an open-source app it's a speed bump, not a lock.
- **Test before shipping** — a misfire here can block app launch.

To enable, add the define to the `Rewind` target's `swiftSettings` in
`Package.swift`:
```swift
.unsafeFlags(["-D", "REWIND_ANTIDEBUG"], .when(configuration: .release)),
```
Then build, **launch the app**, and confirm it opens normally and that Sparkle
update checks still work before releasing.

---

## 4. What still needs a real machine to verify

The following could not be validated in a headless CI-style environment and
should be confirmed on your Mac before a public release:

- [ ] A full **universal** build (`--arch arm64 --arch x86_64`) — requires full
      Xcode, not just Command Line Tools.
- [ ] One real **notarized** build (needs the Apple Developer account above).
- [ ] **Launching the app** to confirm the release compiler flags don't affect
      the SwiftUI menu bar / settings UI at runtime.
- [ ] If you enable it, the **anti-debug** guard (section 3).

The build-flag hardening, string obfuscation, script syntax, and the ad-hoc
signing path (including inside-out Sparkle signing) have been verified.
