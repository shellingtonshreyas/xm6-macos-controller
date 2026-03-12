#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Sony Audio.app"
SOURCE_APP="$ROOT_DIR/dist/$APP_NAME"
TARGET_APP="/Applications/$APP_NAME"

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Built app not found at: $SOURCE_APP"
    echo "Run ./scripts/bundle_app.sh first."
    exit 1
fi

ditto "$SOURCE_APP" "$TARGET_APP"
echo "Installed app to: $TARGET_APP"
