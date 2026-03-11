#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TASK_SCRIPT="$ROOT_DIR/scripts/codex_task.sh"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/codex_task_from_clipboard.sh [codex_task.sh args]

macOS helper:
- reads the current clipboard with pbpaste
- derives the task title from the first non-empty clipboard line
- pipes the clipboard body into scripts/codex_task.sh

Examples:
  bash scripts/codex_task_from_clipboard.sh
  bash scripts/codex_task_from_clipboard.sh --json-path-only
USAGE
}

fail() {
  echo "[taskflow-clipboard] ERROR: $1" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

command -v pbpaste >/dev/null 2>&1 || fail "pbpaste is required (macOS clipboard helper)"
[[ -x "$TASK_SCRIPT" ]] || fail "taskflow script not found or not executable: $TASK_SCRIPT"

CLIPBOARD_TEXT="$(pbpaste)"
if [[ -z "${CLIPBOARD_TEXT//[$' \t\r\n']/}" ]]; then
  fail "clipboard is empty; copy the task request first"
fi

TASK_TITLE="$(
  printf '%s\n' "$CLIPBOARD_TEXT" |
    sed -n '/[^[:space:]]/ { s/^[[:space:]]*//; s/[[:space:]]*$//; p; q; }'
)"
[[ -n "$TASK_TITLE" ]] || TASK_TITLE="Clipboard Task"

printf '%s' "$CLIPBOARD_TEXT" | bash "$TASK_SCRIPT" --title "$TASK_TITLE" "$@"
