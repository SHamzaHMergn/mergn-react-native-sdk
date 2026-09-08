#!/usr/bin/env bash
# Publish the Mergn iOS xcframework to GitHub Releases and update the podspec's
# checksum, so the binary does not have to ship inside the npm package.
#
#   ./scripts/release-ios.sh 19.0.0 /path/to/mergn_ios.xcframework
#
# Requires the `gh` CLI, authenticated (`gh auth login`).
# Free: public GitHub repos have unlimited release-asset storage and bandwidth.
set -euo pipefail

VERSION="${1:?usage: release-ios.sh <version> <path-to-xcframework>}"
FRAMEWORK="${2:?usage: release-ios.sh <version> <path-to-xcframework>}"
REPO="${MERGN_IOS_REPO:-SHamzaHMergn/Mergn_sdk_ios}"

[ -d "$FRAMEWORK" ] || { echo "not a directory: $FRAMEWORK" >&2; exit 1; }

# The framework's own minimum iOS must match the podspec, or clients hit link
# errors that point nowhere useful.
IFACE=$(find "$FRAMEWORK" -name "*-apple-ios.swiftinterface" | head -1)
if [ -n "$IFACE" ]; then
  MIN=$(grep -o "target arm64-apple-ios[0-9.]*" "$IFACE" | head -1 | sed 's/.*ios//')
  echo "framework minimum iOS: ${MIN:-unknown}"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Zip from the framework's PARENT dir so the archive contains
# mergn_ios.xcframework/... and not an absolute path prefix.
cp -R "$FRAMEWORK" "$WORK/"
NAME=$(basename "$FRAMEWORK")
( cd "$WORK" && zip -qr "$WORK/mergn_ios.xcframework.zip" "$NAME" )

ZIP="$WORK/mergn_ios.xcframework.zip"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
echo "zip:    $(du -h "$ZIP" | cut -f1)"
echo "sha256: $SHA"

# The upload needs either the gh CLI or a manual step; the zip and digest are
# already produced either way, so the podspec can be updated regardless.
OUT_DIR="${MERGN_RELEASE_OUT:-$PWD/dist}"
mkdir -p "$OUT_DIR"
cp "$ZIP" "$OUT_DIR/"

if command -v gh >/dev/null 2>&1; then
  gh release view "$VERSION" --repo "$REPO" >/dev/null 2>&1 \
    && gh release upload "$VERSION" "$ZIP" --repo "$REPO" --clobber \
    || gh release create "$VERSION" "$ZIP" --repo "$REPO" \
         --title "Mergn iOS SDK $VERSION" \
         --notes "xcframework for CocoaPods. sha256: $SHA"
  echo "uploaded to https://github.com/$REPO/releases/tag/$VERSION"
else
  cat <<MSG

gh CLI not found - the zip is ready but was NOT uploaded.

  zip: $OUT_DIR/mergn_ios.xcframework.zip

Either install the CLI:
  brew install gh && gh auth login

or upload by hand:
  1. https://github.com/$REPO/releases/new
  2. Tag: $VERSION
  3. Attach the zip above, publish.

The podspec below has been updated with the digest either way, so once the
asset is live at the release URL nothing else needs changing.
MSG
fi

# Keep the podspec's version and digest in lockstep with what was uploaded.
SPEC="$(cd "$(dirname "$0")/.." && pwd)/sdk/MergnSDK.podspec"
/usr/bin/sed -i '' -E "s/  s\.version      = '.*'/  s.version      = '$VERSION'/" "$SPEC"
/usr/bin/sed -i '' -E "s/:sha256 => '[a-f0-9]*'/:sha256 => '$SHA'/" "$SPEC"

echo
echo "Updated $SPEC"
echo "Verify with: pod spec lint MergnSDK.podspec"
