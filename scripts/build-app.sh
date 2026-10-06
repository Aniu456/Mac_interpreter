#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"
derived_data="$project_root/.build/release-xcode"

# 当前随包的 Grok 组件仅支持 Apple Silicon。
xcodebuild -quiet -project FriendTranslator.xcodeproj -scheme FriendTranslator \
  -configuration Release -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$derived_data" ARCHS=arm64 \
  CODE_SIGN_IDENTITY="${INTERPRETER_SIGN_IDENTITY:-Apple Development}" build

built_app="$derived_data/Build/Products/Release/FriendTranslator.app"
app_bundle="$project_root/dist/FriendTranslator.app"
plutil -lint "$built_app/Contents/Info.plist"
test -s "$built_app/Contents/Resources/AppIcon.icns"
test -x "$built_app/Contents/Helpers/grok"
codesign --verify --deep --strict "$built_app"

mkdir -p "$project_root/dist"
staging="$project_root/dist/.FriendTranslator-$$.app"
trap 'rm -rf "$staging"' EXIT
ditto "$built_app" "$staging"
codesign --verify --deep --strict "$staging"
if [[ -e "$app_bundle" ]]; then
  backup_dir="$(mktemp -d "$derived_data/previous-app.XXXXXX")"
  mv "$app_bundle" "$backup_dir/FriendTranslator.app"
fi
mv "$staging" "$app_bundle"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_bundle/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_bundle/Contents/Info.plist")
archive="$project_root/dist/FriendTranslator-${version}-${build_number}-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive"
echo "Built $app_bundle"
echo "Packaged $archive"
shasum -a 256 "$archive"
