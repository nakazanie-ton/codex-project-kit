#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT_DIR/.local_codex"
GENERATOR="$ROOT_DIR/.codex_bootstrap/bootstrap/generate_codex_state.py"
CONFIG_FILE="${CODEX_BOOTSTRAP_CONFIG:-$ROOT_DIR/.codex_bootstrap/config.json}"
CHECKLIST_FILE="$STATE_DIR/CODEX_LOCAL_CHECKLIST.md"

mkdir -p "$STATE_DIR"

if [[ ! -f "$GENERATOR" ]]; then
  echo "[codex-bootstrap] ERROR: generator not found: $GENERATOR" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[codex-bootstrap] ERROR: python3 is required" >&2
  exit 1
fi

python3 "$GENERATOR" --root "$ROOT_DIR" --config "$CONFIG_FILE"

echo "Status checklist saved: CODEX_LOCAL_CHECKLIST.md"
if [[ -f "$CHECKLIST_FILE" ]]; then
  sed -n '1,40p' "$CHECKLIST_FILE"
fi

echo "=================================================="
echo "Codex Agent Bootstrap"
echo "=================================================="
echo "This script restores project context at every start."
echo "Loaded state files:"
echo ""

for file in \
  "$STATE_DIR/AGENT_STATE.md" \
  "$STATE_DIR/PROJECT_AGENT_STATE.json" \
  "$STATE_DIR/PROJECT_TREE.txt" \
  "$STATE_DIR/PROJECT_NAVIGATION.md" \
  "$STATE_DIR/PROJECT_DEPENDENCY_GRAPH.md"; do
  if [[ -f "$file" ]]; then
    echo "===== $(basename "$file") ====="
    sed -n '1,80p' "$file"
    echo ""
  fi
done

echo "Done."
