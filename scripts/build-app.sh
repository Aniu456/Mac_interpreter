#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
cd "$project_root"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$project_root/.build/module-cache"
swift build --disable-sandbox --cache-path .build/cache -c debug --product FriendTranslator

app_bundle="$project_root/dist/FriendTranslator.app"
mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
cp .build/debug/FriendTranslator "$app_bundle/Contents/MacOS/FriendTranslator"
cp Config/Info.plist "$app_bundle/Contents/Info.plist"
plutil -lint "$app_bundle/Contents/Info.plist"
codesign --force --sign "${INTERPRETER_SIGN_IDENTITY:--}" --timestamp=none "$app_bundle"
codesign --verify --strict "$app_bundle"
echo "Built $app_bundle"
