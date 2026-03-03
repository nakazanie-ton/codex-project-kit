#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT_DIR/.local_codex"
GENERATOR="$ROOT_DIR/.codex_bootstrap/bootstrap/generate_codex_state.py"
CONFIG_FILE="${CODEX_BOOTSTRAP_CONFIG:-$ROOT_DIR/.codex_bootstrap/config.json}"
CHECKLIST_FILE="$STATE_DIR/CODEX_LOCAL_CHECKLIST.md"
LOG_LEVEL="${CODEX_BOOTSTRAP_LOG_LEVEL:-full}"

mkdir -p "$STATE_DIR"

case "$LOG_LEVEL" in
  full|summary|quiet) ;;
  *)
    echo "[codex-bootstrap] ERROR: invalid CODEX_BOOTSTRAP_LOG_LEVEL='$LOG_LEVEL' (expected: full|summary|quiet)" >&2
    exit 1
    ;;
esac

log() {
  [[ "$LOG_LEVEL" == "quiet" ]] && return
  echo "$1"
}

if [[ ! -f "$GENERATOR" ]]; then
  echo "[codex-bootstrap] ERROR: generator not found: $GENERATOR" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[codex-bootstrap] ERROR: python3 is required" >&2
  exit 1
fi

python3 "$GENERATOR" --root "$ROOT_DIR" --config "$CONFIG_FILE"

log "Status checklist saved: CODEX_LOCAL_CHECKLIST.md"
if [[ -f "$CHECKLIST_FILE" && "$LOG_LEVEL" != "quiet" ]]; then
  sed -n '1,40p' "$CHECKLIST_FILE"
fi

log "=================================================="
log "Codex Agent Bootstrap"
log "=================================================="
log "This script restores project context at every start."
log "Loaded state files:"
log ""

for file in \
  "$STATE_DIR/AGENT_STATE.md" \
  "$STATE_DIR/PROJECT_AGENT_STATE.json" \
  "$STATE_DIR/PROJECT_TREE.txt" \
  "$STATE_DIR/PROJECT_NAVIGATION.md" \
  "$STATE_DIR/PROJECT_DEPENDENCY_GRAPH.md"; do
  if [[ -f "$file" ]]; then
    if [[ "$LOG_LEVEL" == "full" ]]; then
      echo "===== $(basename "$file") ====="
      sed -n '1,80p' "$file"
      echo ""
    elif [[ "$LOG_LEVEL" == "summary" ]]; then
      echo "- loaded: $(basename "$file")"
    fi
  fi
done

log "Done."
