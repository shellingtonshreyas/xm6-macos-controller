#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SORA_CLI="${SORA_CLI:-/Users/shreyas/.codex/skills/sora/scripts/sora.py}"
PYTHON_BIN="${PYTHON_BIN:-python3}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/dist/sora/branding}"
PROMPTS_DIR="$ROOT_DIR/assets/sora/branding/prompts"
MODEL="${MODEL:-sora-2}"
SIZE="${SIZE:-1280x720}"
CLIP_SECONDS="${CLIP_SECONDS:-4}"

mkdir -p "$OUT_DIR"

usage() {
  cat <<'EOF'
Usage:
  run_branding_sora.sh dry-run
  run_branding_sora.sh icon-preview
  run_branding_sora.sh installer-preview
  run_branding_sora.sh extract-icon-still <input_mp4> <output_png> [time_seconds]

Environment:
  OPENAI_API_KEY  required for live Sora runs
  SORA_CLI        optional absolute path to sora.py
  PYTHON_BIN      optional python binary, defaults to python3
  CLIP_SECONDS    optional Sora clip duration, defaults to 4
EOF
}

ensure_cli() {
  if [[ ! -f "$SORA_CLI" ]]; then
    echo "Sora CLI not found at: $SORA_CLI" >&2
    exit 1
  fi
}

ensure_live_ready() {
  if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo "OPENAI_API_KEY is not set." >&2
    exit 1
  fi

  if ! "$PYTHON_BIN" -c "import openai" >/dev/null 2>&1; then
    echo "The Python 'openai' package is not installed for $PYTHON_BIN." >&2
    exit 1
  fi
}

create_dry_run() {
  local prompt_file="$1"
  local out_json="$2"

  "$PYTHON_BIN" "$SORA_CLI" create \
    --model "$MODEL" \
    --size "$SIZE" \
    --seconds "$CLIP_SECONDS" \
    --prompt-file "$prompt_file" \
    --no-augment \
    --dry-run \
    --json-out "$out_json"
}

create_live() {
  local prompt_file="$1"
  local stem="$2"

  "$PYTHON_BIN" "$SORA_CLI" create-and-poll \
    --model "$MODEL" \
    --size "$SIZE" \
    --seconds "$CLIP_SECONDS" \
    --prompt-file "$prompt_file" \
    --no-augment \
    --download \
    --variant video \
    --out "$OUT_DIR/$stem.mp4" \
    --json-out "$OUT_DIR/$stem.json"
}

extract_icon_still() {
  local input_path="$1"
  local output_path="$2"
  local time_seconds="${3:-0.5}"
  local temp_png="$OUT_DIR/.icon-frame.png"

  if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg is required for extract-icon-still." >&2
    exit 1
  fi

  ffmpeg -y -ss "$time_seconds" -i "$input_path" -frames:v 1 "$temp_png" >/dev/null 2>&1
  sips -c 1024 1024 "$temp_png" --out "$output_path" >/dev/null
  rm -f "$temp_png"
}

ensure_cli

case "${1:-}" in
  dry-run)
    create_dry_run "$PROMPTS_DIR/icon-concept.txt" "$OUT_DIR/icon-concept.request.json"
    create_dry_run "$PROMPTS_DIR/installer-concept.txt" "$OUT_DIR/installer-concept.request.json"
    ;;
  icon-preview)
    ensure_live_ready
    create_live "$PROMPTS_DIR/icon-concept.txt" "icon-preview"
    ;;
  installer-preview)
    ensure_live_ready
    create_live "$PROMPTS_DIR/installer-concept.txt" "installer-preview"
    ;;
  extract-icon-still)
    [[ -n "${2:-}" && -n "${3:-}" ]] || { usage >&2; exit 1; }
    extract_icon_still "$2" "$3" "${4:-0.5}"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    usage >&2
    exit 1
    ;;
esac
