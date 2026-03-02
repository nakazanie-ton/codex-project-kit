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
  --target   Target repository root where bootstrap files will be installed
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

if [[ ! -d "$TARGET/.git" ]]; then
  echo "[install] WARNING: $TARGET does not look like a git repository (.git not found)" >&2
fi

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
  "scripts/codex_bootstrap.sh"
  "scripts/codex_session.sh"
  "scripts/git_pre_commit_sync.sh"
  "scripts/install_git_hooks.sh"
  ".githooks/pre-commit"
  ".codex_bootstrap/bootstrap/codex_bootstrap_core.sh"
  ".codex_bootstrap/bootstrap/generate_codex_state.py"
  ".codex_bootstrap/config.json"
  ".local_codex/AGENT_STATE.md"
)

for rel in "${FILES[@]}"; do
  copy_file "$rel"
done

chmod +x \
  "$TARGET/scripts/codex_bootstrap.sh" \
  "$TARGET/scripts/codex_session.sh" \
  "$TARGET/scripts/git_pre_commit_sync.sh" \
  "$TARGET/scripts/install_git_hooks.sh" \
  "$TARGET/.githooks/pre-commit" \
  "$TARGET/.codex_bootstrap/bootstrap/codex_bootstrap_core.sh"

echo "[install] done"
echo "[install] next: bash $TARGET/scripts/codex_bootstrap.sh"
