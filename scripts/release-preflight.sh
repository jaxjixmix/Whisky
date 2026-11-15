#!/bin/bash
#
# release-preflight.sh
#
# This file is part of Whisky.
#
# Whisky is free software: you can redistribute it and/or modify it under the terms
# of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Whisky is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
# without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along with Whisky.
# If not, see https://www.gnu.org/licenses/.
#
# Checks the live 3.9.x release prerequisites before building or announcing a release.
#
# Usage: scripts/release-preflight.sh
# Environment: NOTARY_PROFILE (default AC_PASSWORD), SPARKLE_BIN

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${NOTARY_PROFILE:-AC_PASSWORD}"
VERSION="$(grep -m1 'MARKETING_VERSION = ' Whisky.xcodeproj/project.pbxproj \
    | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d '[:space:]')"
BUILD="$(grep -m1 'CURRENT_PROJECT_VERSION = ' Whisky.xcodeproj/project.pbxproj \
    | sed -E 's/.*CURRENT_PROJECT_VERSION = ([^;]+);/\1/' | tr -d '[:space:]')"
FAIL=0

pass() { printf 'PASS: %s\n' "$1"; }
warn() { printf 'WARN: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=1; }

echo "Whisky release preflight: version $VERSION (build $BUILD)"
echo

if xcodebuild -version >/dev/null 2>&1; then
    pass "Xcode is available"
else
    fail "xcodebuild is unavailable; run this on the Developer ID machine"
fi

if security find-identity -v -p codesigning 2>/dev/null \
    | grep -q 'Developer ID Application'; then
    pass "Developer ID Application identity is installed"
else
    fail "no Developer ID Application identity in the keychain"
fi

if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    pass "notarytool profile '$PROFILE' works"
else
    fail "notarytool profile '$PROFILE' is missing or invalid"
fi

PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Whisky/Info.plist 2>/dev/null || true)"
if [ -n "$PUBLIC_KEY" ]; then
    pass "SUPublicEDKey is present (verify it is this fork's key, not upstream's)"
else
    fail "SUPublicEDKey is missing"
fi

if [ -z "${SPARKLE_BIN:-}" ]; then
    SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
        -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin' -type d 2>/dev/null \
        | head -1)"
fi
if [ -n "$SPARKLE_BIN" ] && [ -x "$SPARKLE_BIN/sign_update" ]; then
    pass "Sparkle sign_update found at $SPARKLE_BIN"
else
    fail "Sparkle sign_update not found; build once or set SPARKLE_BIN"
fi

if grep -q "<sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>" \
    dist/pages/appcast.xml; then
    pass "appcast has an item for $VERSION (auto-update enabled)"
else
    fail "appcast has no item for $VERSION; Sparkle offers no update"
fi

RUNTIME_PLIST="dist/pages/WhiskyWineVersion.plist"
if [ -f "$RUNTIME_PLIST" ]; then
    RUNTIME_HASH="$(/usr/libexec/PlistBuddy -c 'Print :sha256' "$RUNTIME_PLIST" 2>/dev/null || true)"
    if [ -n "$RUNTIME_HASH" ]; then
        pass "runtime manifest has a SHA-256"
    else
        fail "runtime manifest has no SHA-256"
    fi
    if /usr/libexec/PlistBuddy -c 'Print :signature' "$RUNTIME_PLIST" >/dev/null 2>&1; then
        pass "runtime manifest has an Ed25519 signature"
    else
        warn "runtime manifest has no Ed25519 signature (3.9.4 verifies SHA-256 only)"
    fi
else
    fail "missing $RUNTIME_PLIST"
fi

for url in \
    "https://jaxjixmix.github.io/Whisky/WhiskyWineVersion.plist" \
    "https://jaxjixmix.github.io/Whisky/appcast.xml"; do
    if curl -fsSI --max-time 20 "$url" >/dev/null 2>&1; then
        pass "live URL responds: $url"
    else
        fail "live URL does not respond: $url"
    fi
done

if gh release view "app-v$VERSION" --repo jaxjixmix/Whisky >/dev/null 2>&1; then
    pass "GitHub release app-v$VERSION exists"
else
    warn "GitHub release app-v$VERSION does not exist yet"
fi

DMG="build/release/Whisky-$VERSION.dmg"
if [ -f "$DMG" ]; then
    if codesign -dv "$DMG" >/dev/null 2>&1; then
        pass "DMG is signed"
    else
        fail "DMG is not signed"
    fi
    if spctl --assess --type open --context context:primary-signature "$DMG" >/dev/null 2>&1; then
        pass "DMG is accepted by Gatekeeper"
    else
        fail "DMG is not notarized/accepted by Gatekeeper"
    fi
else
    warn "no local DMG at $DMG; build with scripts/release.sh $VERSION"
fi

echo
if [ "$FAIL" -ne 0 ]; then
    echo "Preflight failed. Fix the FAIL lines before releasing."
    exit 1
fi
echo "Preflight passed. The release is ready to publish."
