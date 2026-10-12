#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
source "$ROOT_DIR/scripts/swift-env.zsh"
cd "$ROOT_DIR"
swift run --disable-sandbox --scratch-path "$PROJECT_STANDARD_SCRATCH_PATH" ProjectStandard --project "$ROOT_DIR/examples"
