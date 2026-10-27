#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ICON_PRODUCT=singularity-desktop
APP="$ROOT/.build/Singularity.app"
# Where the operator launches the app from: ~/Applications unless
# SINGULARITY_INSTALL_APP_PATH names another place.
if [ -n "${SINGULARITY_INSTALL_APP_PATH+set}" ]; then
  INSTALLED=$SINGULARITY_INSTALL_APP_PATH
else
  INSTALLED="$HOME/Applications/Singularity.app"
fi
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
FRAMEWORKS="$CONTENTS/Frameworks"
RESOURCES="$CONTENTS/Resources"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# Installed files: data readable by everyone and writable by its owner;
# executables additionally executable by everyone.
DATA_MODE=u=rw,go=r
EXECUTABLE_MODE=u=rwx,go=rx
swift build --package-path "$ROOT" -c release --product Singularity
BIN_DIR=$(swift build --package-path "$ROOT" -c release --show-bin-path)
rm -rf "$APP"
mkdir -p "$MACOS" "$FRAMEWORKS" "$RESOURCES"
install -m "$DATA_MODE" "$ROOT/App/Info.plist" "$CONTENTS/Info.plist"
# A release build states its version; the build number is the version unless
# the release states one of its own.
if [ -n "${WISENT_RELEASE_VERSION+set}" ]; then
  plutil -replace CFBundleShortVersionString -string "$WISENT_RELEASE_VERSION" "$CONTENTS/Info.plist"
  if [ -n "${WISENT_BUILD_NUMBER+set}" ]; then
    plutil -replace CFBundleVersion -string "$WISENT_BUILD_NUMBER" "$CONTENTS/Info.plist"
  else
    plutil -replace CFBundleVersion -string "$WISENT_RELEASE_VERSION" "$CONTENTS/Info.plist"
  fi
fi
# Stado resolves the deployment's update origin; source carries no host.
# WISENT_UPDATE_FEED_URL explicitly overrides it for a staging feed.
if [ -n "${WISENT_UPDATE_FEED_URL+set}" ]; then
  UPDATE_FEED_URL=$WISENT_UPDATE_FEED_URL
else
  UPDATE_FEED_URL=$(stado web origin url /api/release/appcast --query "product=$ICON_PRODUCT")
fi
case "$UPDATE_FEED_URL" in
  https://*) ;;
  '')
    printf '%s\n' "Stado returned no update feed URL; declare an appcast origin or set WISENT_UPDATE_FEED_URL." >&2
    false ;;
  *)
    printf 'Update feed must use HTTPS: %s\n' "$UPDATE_FEED_URL" >&2
    false ;;
esac
plutil -replace SUFeedURL -string "$UPDATE_FEED_URL" "$CONTENTS/Info.plist"
install -m "$EXECUTABLE_MODE" "$BIN_DIR/Singularity" "$MACOS/Singularity"
if [ -f "$ROOT/App/AppIcon.icns" ]; then
  install -m "$DATA_MODE" "$ROOT/App/AppIcon.icns" "$RESOURCES/AppIcon.icns"
else
  sh "$SCRIPT_DIR/import-brand-icon.sh" "$ICON_PRODUCT" "$RESOURCES/AppIcon.icns"
fi
for bundle in "$BIN_DIR"/*.bundle; do
  [ -d "$bundle" ] || continue
  ditto "$bundle" "$RESOURCES/$(basename "$bundle")"
done
if [ -d "$BIN_DIR/Sparkle.framework" ]; then
  ditto "$BIN_DIR/Sparkle.framework" "$FRAMEWORKS/Sparkle.framework"
  if ! otool -l "$MACOS/Singularity" | grep -q '@executable_path/../Frameworks'; then
    install_name_tool -add_rpath '@executable_path/../Frameworks' "$MACOS/Singularity"
  fi
fi

# Shared Wisent sessions are stored by one fixed signed helper identity. A
# packaged app without it would keep its session in an isolated bundle-scoped
# Keychain item and ask for another login.
IDENTITY_HELPER="$CONTENTS/Helpers/WisentIdentityKeychainHelper"
IDENTITY_BUILD_DIR="$ROOT/.build/identity-helper"
swift build --package-path "$ROOT/.build/checkouts/wisent-desktop-auth" \
    --configuration release --product wisent-identity-keychain-helper --scratch-path "$IDENTITY_BUILD_DIR"
mkdir -p "$(dirname "$IDENTITY_HELPER")"
install -m "$EXECUTABLE_MODE" "$IDENTITY_BUILD_DIR/release/wisent-identity-keychain-helper" "$IDENTITY_HELPER"

# The shared signer signs SIGN_TARGET as SIGN_IDENTIFIER with the hardened
# runtime and verifies continuity with SIGN_PREVIOUS. A release names its
# certificate in WISENT_CODESIGN_IDENTITY; otherwise Stado selects the declared
# Skarbiec certificate itself, so no identity is guessed from whatever the
# login keychain holds.
sign_target() {
  if [ -n "${WISENT_CODESIGN_IDENTITY+set}" ]; then
    stado product signing sign "$SIGN_TARGET" --identifier "$SIGN_IDENTIFIER" \
      --previous "$SIGN_PREVIOUS" --identity "$WISENT_CODESIGN_IDENTITY" --hardened-runtime --json
  else
    stado product signing sign "$SIGN_TARGET" --identifier "$SIGN_IDENTIFIER" \
      --previous "$SIGN_PREVIOUS" --hardened-runtime --json
  fi
}
SIGN_TARGET=$IDENTITY_HELPER
SIGN_IDENTIFIER=ai.wisent.identity.keychain-helper
SIGN_PREVIOUS="$INSTALLED/Contents/Helpers/WisentIdentityKeychainHelper"
sign_target
SIGN_TARGET=$APP
SIGN_IDENTIFIER=ai.wisent.singularity.desktop
SIGN_PREVIOUS=$INSTALLED
sign_target
codesign --verify --strict --deep "$APP"
codesign --verify --strict --test-requirement '=identifier "ai.wisent.identity.keychain-helper"' "$IDENTITY_HELPER"
echo "Built $APP"

# The build installs unless SINGULARITY_INSTALL_AFTER_BUILD says no.
if [ -n "${SINGULARITY_INSTALL_AFTER_BUILD+set}" ] && [ "$SINGULARITY_INSTALL_AFTER_BUILD" = no ]; then
  exit
fi
mkdir -p "$(dirname "$INSTALLED")"
rm -rf "$INSTALLED"
ditto "$APP" "$INSTALLED"
# While the .build copy stays registered it competes for the app's URL schemes
# with the installed copy, so it is unregistered. `lsregister -u` also exits
# non-zero over the Spotlight importer's own failure to scan the .build copy,
# after the installed copy is already in place; that failure is said, with
# lsregister's own output left visible above, and the installed copy is still
# registered and restarted.
if ! "$LSREGISTER" -u "$APP"; then
  printf '%s\n' "lsregister did not unregister $APP (its output above says why); registering the installed copy anyway." >&2
fi
"$LSREGISTER" -f "$INSTALLED"
echo "Installed $INSTALLED"
# An install that does not restart is a silent no-op for anyone already running
# the app: the bundle on disk is new, the process in front of the operator is
# the old binary. Stado owns the restart: `--if-running` leaves a stopped app
# stopped and reports what LaunchServices observed.
stado product restart --if-running "$INSTALLED"
