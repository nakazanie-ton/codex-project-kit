#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$KIT_ROOT/templates"

TARGET=""
FORCE=0

usage() {
  cat <<'USAGE'
Usage:
  bash bin/install.sh --target <repo_path> [--force]

Options:
  --target   Target repository root where taskflow files will be installed
  --force    Overwrite existing files
USAGE
}

while (( $# > 0 )); do
  case "$1" in
    --target)
      shift
      TARGET="${1:-}"
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "[install] Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift || true
done

if [[ -z "$TARGET" ]]; then
  echo "[install] --target is required" >&2
  usage
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

copy_file() {
  local rel="$1"
  local src="$TEMPLATES_DIR/$rel"
  local dst="$TARGET/$rel"

  if [[ ! -f "$src" ]]; then
    echo "[install] ERROR: template file not found: $src" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$dst")"

  if [[ -f "$dst" && "$FORCE" -ne 1 ]]; then
    echo "[install] skip (exists): $rel"
    return
  fi

  cp "$src" "$dst"
  echo "[install] write: $rel"
}

FILES=(
  "scripts/codex_task.sh"
  ".codex_taskflow/config.json"
  ".codex_taskflow/taskflow_engine.py"
  ".codex_taskflow/templates/intake.md"
  ".codex_taskflow/templates/scope.md"
  ".codex_taskflow/templates/plan.md"
  ".codex_taskflow/templates/execution_log.md"
  ".codex_taskflow/templates/verification.md"
  ".codex_taskflow/templates/handoff.md"
)

for rel in "${FILES[@]}"; do
  copy_file "$rel"
done

chmod +x \
  "$TARGET/scripts/codex_task.sh" \
  "$TARGET/.codex_taskflow/taskflow_engine.py"

echo "[install] done"
echo "[install] next: bash $TARGET/scripts/codex_task.sh --help"
