#!/usr/bin/env bash
set -euo pipefail

TARGET=""
TARGET_SET=0
FORCE=1
DRY_RUN=0
BACKUP=0

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/one_click_install.sh --target /absolute/path/to/target-repo [--dry-run] [--backup] [--no-force]

Options:
  --target   Absolute path to target repository root
  --dry-run  Preview installation and normalization actions without writing files
  --backup   Backup overwritten files/config under .codex_install_backups/
  --no-force Do not overwrite files that already exist in target repo
USAGE
}

fail() {
  echo "[orchestrator] ERROR: $1" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --target)
      if [[ "$TARGET_SET" -eq 1 ]]; then
        fail "--target was provided more than once"
      fi
      shift || true
      [[ $# -gt 0 ]] || fail "--target requires a value"
      [[ "${1:-}" != --* ]] || fail "--target requires a path value"
      TARGET="$1"
      TARGET_SET=1
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --backup)
      BACKUP=1
      ;;
    --no-force)
      FORCE=0
      ;;
    --force)
      FORCE=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift || true
done

if [[ "$TARGET_SET" -ne 1 ]]; then
  fail "--target is required"
fi

if [[ ! -d "$TARGET" ]]; then
  fail "target directory not found: $TARGET"
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 is required"
fi

TARGET="$(cd "$TARGET" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_KIT="$REPO_ROOT/kits/codex-bootstrap-kit"
TASKFLOW_KIT="$REPO_ROOT/kits/codex-taskflow-kit"
NORMALIZE_SCRIPT="$SCRIPT_DIR/normalize_bootstrap_config.sh"

if [[ ! -f "$BOOTSTRAP_KIT/bin/install.sh" ]]; then
  fail "missing bundled bootstrap kit: $BOOTSTRAP_KIT"
fi

if [[ ! -f "$TASKFLOW_KIT/bin/install.sh" ]]; then
  fail "missing bundled taskflow kit: $TASKFLOW_KIT"
fi

if [[ ! -f "$NORMALIZE_SCRIPT" ]]; then
  fail "missing normalize script: $NORMALIZE_SCRIPT"
fi

if [[ ! -d "$TARGET/.git" ]]; then
  echo "[orchestrator] WARNING: target does not look like a git repository (.git not found): $TARGET" >&2
fi

INSTALL_ARGS=(--target "$TARGET")
NORMALIZE_ARGS=(--target "$TARGET")
if [[ "$FORCE" -eq 1 ]]; then
  INSTALL_ARGS+=(--force)
fi
if [[ "$DRY_RUN" -eq 1 ]]; then
  INSTALL_ARGS+=(--dry-run)
fi
if [[ "$BACKUP" -eq 1 ]]; then
  INSTALL_ARGS+=(--backup)
  NORMALIZE_ARGS+=(--backup)
fi

bash "$BOOTSTRAP_KIT/bin/install.sh" "${INSTALL_ARGS[@]}"
bash "$TASKFLOW_KIT/bin/install.sh" "${INSTALL_ARGS[@]}"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[orchestrator] dry-run: would normalize bootstrap config: $TARGET/.codex_bootstrap/config.json"
  echo "[orchestrator] dry-run: skipped strict verification"
  echo "[orchestrator] dry-run complete: reviewed bundled kit install and normalization actions"
  exit 0
fi

bash "$NORMALIZE_SCRIPT" "${NORMALIZE_ARGS[@]}"

cd "$TARGET"
CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh

echo "[orchestrator] done: bundled kits installed, config normalized, and strict verification passed"
