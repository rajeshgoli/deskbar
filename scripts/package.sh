#!/bin/bash
set -euo pipefail

APP_NAME="DeskBar"
BUILD_DIR=".build/release"
BUNDLE_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# See config/signing.env: signing with a persistent certificate is what keeps
# the Accessibility and Screen Recording grants across rebuilds, because TCC
# keys a grant to the designated requirement and an ad-hoc signature has no
# stable certificate to anchor one.
SIGNING_CONFIG="${DESKBAR_SIGNING_CONFIG:-$REPO_ROOT/config/signing.env}"
SIGN_IDENTITY="${DESKBAR_SIGN_IDENTITY:-}"
SIGN_IDENTIFIER="${DESKBAR_SIGN_IDENTIFIER:-}"
SIGN_REQUIREMENT="${DESKBAR_SIGN_DESIGNATED_REQUIREMENT:-}"
REQUIRE_SIGNING="${DESKBAR_REQUIRE_SIGNING:-0}"

fail() { echo "ERROR: $1" >&2; exit 1; }

# The config is deployment data, not shell code: parse the keys with sed rather
# than sourcing it, so editing it can never execute commands. Values already
# supplied in the environment win, which is how a certificate rotation is tested
# before it becomes the tracked default.
read_config_key() {
  [[ -r "$SIGNING_CONFIG" ]] || return 0
  sed -n -E "s/^$1=//p" "$SIGNING_CONFIG" | tail -n 1
}
[[ -n "$SIGN_IDENTITY" ]] || SIGN_IDENTITY="$(read_config_key DESKBAR_SIGN_IDENTITY)"
[[ -n "$SIGN_IDENTIFIER" ]] || SIGN_IDENTIFIER="$(read_config_key DESKBAR_SIGN_IDENTIFIER)"
[[ -n "$SIGN_REQUIREMENT" ]] || SIGN_REQUIREMENT="$(read_config_key DESKBAR_SIGN_DESIGNATED_REQUIREMENT)"
SIGN_IDENTIFIER="${SIGN_IDENTIFIER:-com.deskbar.app}"

# Resolve the signing mode before building anything, so an unusable identity is
# reported immediately instead of after a full package.
ADHOC_REASON=""
if [[ -z "$SIGN_IDENTITY" || "$SIGN_IDENTITY" == "-" ]]; then
  ADHOC_REASON="no persistent signing identity is configured"
elif ! [[ "$SIGN_IDENTITY" =~ ^[0-9A-F]{40}$ ]]; then
  fail "DESKBAR_SIGN_IDENTITY must be the uppercase 40-hex fingerprint from 'security find-identity -v -p codesigning' (got: $SIGN_IDENTITY)"
elif ! security find-identity -v -p codesigning 2>/dev/null | grep -Eq "^[[:space:]]*[0-9]+\) $SIGN_IDENTITY "; then
  ADHOC_REASON="signing identity $SIGN_IDENTITY is not a valid usable codesigning identity in this keychain"
fi
if [[ -n "$ADHOC_REASON" && "$REQUIRE_SIGNING" != "0" ]]; then
  fail "$ADHOC_REASON, and DESKBAR_REQUIRE_SIGNING is set"
fi

# Clean previous bundle
rm -rf "$BUNDLE_DIR"

# Create bundle structure
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"

# Copy resources
if [ -f "Resources/AppIcon.icns" ]; then
  cp "Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Generate Info.plist from template
sed "s|__EXECUTABLE__|$APP_NAME|g" Info.plist.template > "$CONTENTS_DIR/Info.plist"

# Codesign. The identifier is pinned explicitly so the designated requirement
# does not quietly follow a change to CFBundleIdentifier.
if [[ -n "$ADHOC_REASON" ]]; then
  codesign --force --sign - --identifier "$SIGN_IDENTIFIER" "$BUNDLE_DIR"
  codesign --verify --strict "$BUNDLE_DIR" || fail "signature verification failed"
  echo
  echo "WARNING: ad-hoc signed - $ADHOC_REASON."
  echo "WARNING: macOS will ask for Accessibility and Screen Recording permission"
  echo "WARNING: again after every rebuild. See config/signing.env."
else
  codesign --force --sign "$SIGN_IDENTITY" --identifier "$SIGN_IDENTIFIER" "$BUNDLE_DIR" \
    || fail "codesign with identity $SIGN_IDENTITY failed"
  codesign --verify --strict "$BUNDLE_DIR" || fail "signature verification failed"

  metadata="$(codesign -dvvv "$BUNDLE_DIR" 2>&1)" || fail "could not inspect the signature"
  printf '%s\n' "$metadata" | grep -Fxq "Identifier=$SIGN_IDENTIFIER" \
    || fail "signature identifier is not $SIGN_IDENTIFIER"
  if printf '%s\n' "$metadata" | grep -Fxq 'Signature=adhoc'; then
    fail "signature is ad-hoc despite a configured certificate identity"
  fi

  # The requirement is what TCC matches existing grants against. A mismatch here
  # means the permissions would have to be granted again, so say so rather than
  # shipping a bundle that silently asks the user to re-approve.
  if [[ -n "$SIGN_REQUIREMENT" ]]; then
    actual_requirement="$(codesign -d -r- "$BUNDLE_DIR" 2>/dev/null | grep '^designated => ')"
    [[ "$actual_requirement" == "$SIGN_REQUIREMENT" ]] \
      || fail "designated requirement changed; existing macOS permission grants would not carry over
  expected: $SIGN_REQUIREMENT
  actual:   ${actual_requirement:-<none>}"
  fi
fi

echo "Bundle created: $BUNDLE_DIR"
if [[ -z "$ADHOC_REASON" ]]; then
  echo "Signed with persistent identity $SIGN_IDENTITY ($SIGN_IDENTIFIER)"
fi
echo "To run: open $BUNDLE_DIR"
