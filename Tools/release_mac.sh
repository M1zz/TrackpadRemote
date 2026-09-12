#!/bin/bash
#
# Builds, signs, notarizes and publishes TrackpadServer.app as a GitHub Release,
# which is what the download page's "Mac용 다운로드" button points at.
#
# The Mac app cannot ship on the Mac App Store (CGEventPost is blocked in the
# sandbox), so Developer ID + notarization is the whole distribution story. An
# app that is signed but NOT notarized is worse than useless here: Gatekeeper
# refuses to open it at all once it arrives with a quarantine flag, and the user
# reads that as "the app is broken", not "the developer skipped a step".
#
#   usage: Tools/release_mac.sh [version] [--no-publish]
#
#   version      defaults to MARKETING_VERSION in project.yml
#   --no-publish stops after stapling, leaving the zip in build/ (dry run)
#
# One-time setup is documented in README.md ("Mac 앱 배포"). Two things must
# exist before this script can run: a Developer ID Application certificate in
# the keychain, and a notarytool keychain profile holding an app-specific
# password.

set -euo pipefail

cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-TrackpadRemote}"
TEAM_ID="QGAQ3AY3R3"
SCHEME="TrackpadServer"
APP_NAME="TrackpadServer.app"
ZIP_NAME="TrackpadServer.zip"
BUILD_DIR="build/mac-release"

VERSION=""
PUBLISH=1
for arg in "$@"; do
  case "$arg" in
    --no-publish) PUBLISH=0 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) VERSION="$arg" ;;
  esac
done

if [ -z "$VERSION" ]; then
  VERSION=$(awk '/MARKETING_VERSION/ {gsub(/"/, "", $2); print $2; exit}' project.yml)
fi
if [ -z "$VERSION" ]; then
  echo "could not read MARKETING_VERSION from project.yml; pass a version" >&2
  exit 1
fi

TAG="v$VERSION"

say() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
die() { printf '\n\033[31merror: %s\033[0m\n' "$1" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
# Every one of these fails much later and much less legibly if we don't say it
# here — a missing certificate surfaces as an opaque exportArchive error.

say "Preflight"

security find-identity -v -p codesigning | grep -q "Developer ID Application" \
  || die "No 'Developer ID Application' certificate in the keychain.
       An 'Apple Development' certificate cannot sign apps for distribution
       outside the App Store. Create one at
       https://developer.apple.com/account/resources/certificates
       (or Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸
       Developer ID Application) and download it into the login keychain.
       Requires the Account Holder role."

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "No notarytool keychain profile named '$NOTARY_PROFILE'.
       Create an app-specific password at https://appleid.apple.com ▸ Sign-In
       and Security ▸ App-Specific Passwords, then store it once:

         xcrun notarytool store-credentials $NOTARY_PROFILE \\
           --apple-id <your Apple ID> --team-id $TEAM_ID --password <app-specific password>"

if [ "$PUBLISH" -eq 1 ]; then
  command -v gh >/dev/null || die "gh CLI not installed (brew install gh)"
  gh auth status >/dev/null 2>&1 || die "gh is not logged in (gh auth login)"
  if gh release view "$TAG" >/dev/null 2>&1; then
    die "Release $TAG already exists. Bump MARKETING_VERSION in project.yml,
       or delete the release: gh release delete $TAG --cleanup-tag"
  fi
fi

command -v xcodegen >/dev/null && xcodegen generate >/dev/null

echo "version   $VERSION  (tag $TAG)"
echo "identity  $(security find-identity -v -p codesigning | grep 'Developer ID Application' | head -1 | sed 's/.*"\(.*\)"/\1/')"
echo "notary    $NOTARY_PROFILE"

# ------------------------------------------------------------------ archive

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

ARCHIVE="$BUILD_DIR/$SCHEME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"

say "Archiving"
xcodebuild -project TrackpadRemote.xcodeproj \
           -scheme "$SCHEME" \
           -configuration Release \
           -destination 'generic/platform=macOS' \
           -archivePath "$ARCHIVE" \
           -allowProvisioningUpdates \
           archive | tail -3

# Written here rather than kept in the repo so it can never drift from the team
# id and signing style the rest of the build uses.
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>destination</key>
	<string>export</string>
</dict>
</plist>
PLIST

say "Exporting with Developer ID"
xcodebuild -exportArchive \
           -archivePath "$ARCHIVE" \
           -exportOptionsPlist "$EXPORT_PLIST" \
           -exportPath "$EXPORT_DIR" \
           -allowProvisioningUpdates | tail -3

APP="$EXPORT_DIR/$APP_NAME"
[ -d "$APP" ] || die "export produced no $APP_NAME"

# The sandbox must stay off and the hardened runtime must stay on; getting
# either backwards produces an app that installs and then silently refuses to
# move the cursor. Cheap to assert, expensive to discover from a bug report.
codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - - \
  | grep -A1 'com.apple.security.app-sandbox' | grep -q '<false/>' \
  || die "App Sandbox is enabled — CGEventPost will be blocked and the app will do nothing"
codesign -d -v "$APP" 2>&1 | grep -q 'flags=.*runtime' \
  || die "Hardened runtime is not enabled — notarization will reject this"

# ---------------------------------------------------------------- notarize

say "Notarizing (this waits on Apple; a few minutes is normal)"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/submit.zip"
xcrun notarytool submit "$BUILD_DIR/submit.zip" \
      --keychain-profile "$NOTARY_PROFILE" --wait

say "Stapling"
xcrun stapler staple "$APP"

# What a user's Mac will actually decide when the download is opened. If this
# says anything but "accepted", the download is a dead end.
spctl -a -vvv -t exec "$APP" 2>&1 | sed 's/^/    /'

# Re-zipped AFTER stapling so the ticket travels inside the download; a machine
# that is offline on first launch still passes.
ZIP="$BUILD_DIR/$ZIP_NAME"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "    $ZIP ($(du -h "$ZIP" | cut -f1))"

if [ "$PUBLISH" -eq 0 ]; then
  say "Done (--no-publish): $ZIP"
  exit 0
fi

# ------------------------------------------------------------------ publish
# The download page links to releases/latest, so the newest release must be the
# Mac one and its asset must keep the name TrackpadServer.zip.

say "Publishing $TAG"
gh release create "$TAG" "$ZIP" \
   --title "TrackpadServer $VERSION" \
   --notes "$(cat <<NOTES
Mac 앱입니다. iPhone 앱과 함께 써야 동작합니다.

설치
1. TrackpadServer.zip 을 내려받아 압축을 풀고 **응용 프로그램**으로 옮깁니다.
2. 실행하면 메뉴 막대에 트랙패드 아이콘이 생깁니다. Dock 에는 나타나지 않습니다.
3. 처음 연결될 때 손쉬운 사용 권한을 묻습니다. 허용해야 커서가 움직입니다.

Apple 공증(notarized)을 마친 빌드라 경고 없이 열립니다.
https://m1zz.github.io/TrackpadRemote/
NOTES
)"

say "Done"
gh release view "$TAG" --json url --jq .url
echo "download page: https://m1zz.github.io/TrackpadRemote/"
