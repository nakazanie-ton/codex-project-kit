#!/usr/bin/env bash
set -euo pipefail

TARGET=""
FORCE=1
DRY_RUN=0
BACKUP=0

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/one_click_install.sh /absolute/path/to/target-repo [--dry-run] [--backup] [--no-force]

Options:
  --dry-run  Preview installation and normalization actions without writing files
  --backup   Backup overwritten files/config under .codex_install_backups/
  --no-force Do not overwrite files that already exist in target repo
USAGE
}

while (( $# > 0 )); do
  case "$1" in
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
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
      else
        echo "[orchestrator] ERROR: unknown argument: $1" >&2
        usage
        exit 1
      fi
      ;;
  esac
  shift || true
done

if [[ -z "$TARGET" ]]; then
  echo "[orchestrator] ERROR: target repository path is required" >&2
  usage
  exit 1
fi

if [[ ! -d "$TARGET" ]]; then
  echo "[orchestrator] ERROR: target directory not found: $TARGET" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_KIT="$REPO_ROOT/kits/codex-bootstrap-kit"
TASKFLOW_KIT="$REPO_ROOT/kits/codex-taskflow-kit"

if [[ ! -f "$BOOTSTRAP_KIT/bin/install.sh" ]]; then
  echo "[orchestrator] ERROR: missing bundled bootstrap kit: $BOOTSTRAP_KIT" >&2
  exit 1
fi

if [[ ! -f "$TASKFLOW_KIT/bin/install.sh" ]]; then
  echo "[orchestrator] ERROR: missing bundled taskflow kit: $TASKFLOW_KIT" >&2
  exit 1
fi

INSTALL_ARGS=(--target "$TARGET")
NORMALIZE_ARGS=("$TARGET")
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

bash "$SCRIPT_DIR/normalize_bootstrap_config.sh" "${NORMALIZE_ARGS[@]}"

cd "$TARGET"
CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh

echo "[orchestrator] done: bundled kits installed, config normalized, and strict verification passed"
