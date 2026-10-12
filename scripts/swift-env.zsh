#!/bin/zsh

if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  export SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
fi

export PROJECT_STANDARD_CACHE_ROOT="${TMPDIR:-/tmp}/project-standard-swift-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_STANDARD_CACHE_ROOT/clang"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_STANDARD_CACHE_ROOT/clang"
export PROJECT_STANDARD_SCRATCH_PATH="$PROJECT_STANDARD_CACHE_ROOT/build"
mkdir -p "$CLANG_MODULE_CACHE_PATH" "$PROJECT_STANDARD_SCRATCH_PATH"
