#!/bin/bash
# Archive and upload a build to App Store Connect / TestFlight without Xcode.app UI.
#
# Requires an App Store Connect API key (App Manager or Admin role):
#   ASC_KEY_ID      Key ID            (e.g. ABC123DEFG)
#   ASC_ISSUER_ID   Issuer ID         (UUID)
#   ASC_KEY_PATH    path to AuthKey_<KEY_ID>.p8
#
# Usage: ./scripts/upload-appstore.sh [build_number]
set -euo pipefail
cd "$(dirname "$0")/.."

: "${ASC_KEY_ID:?set ASC_KEY_ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
: "${ASC_KEY_PATH:?set ASC_KEY_PATH}"

TEAM_ID="J659DC2DZR"
ARCHIVE="build/EightBallPool.xcarchive"
EXPORT_DIR="build/export"
BUILD_NUMBER="${1:-}"

EXTRA_SETTINGS=()
if [[ -n "$BUILD_NUMBER" ]]; then
  EXTRA_SETTINGS+=("CURRENT_PROJECT_VERSION=$BUILD_NUMBER")
fi

rm -rf "$ARCHIVE" "$EXPORT_DIR"

# The archive is built unsigned; exportArchive re-signs it with a cloud-managed
# Apple Distribution certificate, so no devices or local certificates are needed.
xcodebuild -project EightBallPool.xcodeproj -scheme EightBallPool -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" archive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO "${EXTRA_SETTINGS[@]}" \
  | grep -E "error:|ARCHIVE" || true

cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>destination</key>
	<string>upload</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist build/ExportOptions.plist \
  -exportPath "$EXPORT_DIR" -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" \
  | grep -E "error|Upload succeeded|Upload failed|EXPORT" || true
