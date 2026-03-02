#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENGINE="$ROOT_DIR/.codex_taskflow/taskflow_engine.py"
BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/codex_bootstrap.sh"
CHECKLIST="$ROOT_DIR/.local_codex/CODEX_LOCAL_CHECKLIST.md"

REQUIRE_BOOTSTRAP="${CODEX_TASKFLOW_REQUIRE_BOOTSTRAP:-1}"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/codex_task.sh [--title <title>] [--text <task_text>] [--file <path>] [--out-dir <path>]

Examples:
  bash scripts/codex_task.sh --title "fix auth" --text "login returns 500"
  bash scripts/codex_task.sh --file /tmp/task.txt
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ ! -f "$ENGINE" ]]; then
  echo "[taskflow] ERROR: engine not found: $ENGINE" >&2
  exit 1
fi

if [[ -x "$BOOTSTRAP_SCRIPT" ]]; then
  echo "[taskflow] running bootstrap before taskflow"
  bash "$BOOTSTRAP_SCRIPT"

  if [[ ! -f "$CHECKLIST" ]]; then
    echo "[taskflow] ERROR: checklist not found after bootstrap: $CHECKLIST" >&2
    exit 1
  fi

  if ! grep -Eq "status:[[:space:]]*PASS" "$CHECKLIST"; then
    echo "[taskflow] ERROR: bootstrap checklist status is not PASS" >&2
    exit 1
  fi

  echo "[taskflow] bootstrap checklist status: PASS"
else
  if [[ "$REQUIRE_BOOTSTRAP" == "1" ]]; then
    echo "[taskflow] ERROR: bootstrap script is required but not found: $BOOTSTRAP_SCRIPT" >&2
    echo "[taskflow] install codex-bootstrap-kit or set CODEX_TASKFLOW_REQUIRE_BOOTSTRAP=0" >&2
    exit 1
  fi
  echo "[taskflow] WARNING: running without bootstrap (CODEX_TASKFLOW_REQUIRE_BOOTSTRAP=0)" >&2
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "[taskflow] ERROR: python3 is required" >&2
  exit 1
fi

python3 "$ENGINE" --root "$ROOT_DIR" "$@"
