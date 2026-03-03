#!/usr/bin/env bash
set -euo pipefail

TARGET=""
DRY_RUN=0
BACKUP=0

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/normalize_bootstrap_config.sh /absolute/path/to/target-repo [--dry-run] [--backup]

Options:
  --dry-run  Print planned action without rewriting config
  --backup   Backup existing config under .codex_install_backups/
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
CONFIG_PATH="$TARGET/.codex_bootstrap/config.json"
if [[ ! -f "$CONFIG_PATH" ]]; then
  echo "[orchestrator] ERROR: bootstrap config not found: $CONFIG_PATH" >&2
  exit 1
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[orchestrator] dry-run: would rewrite bootstrap config: $CONFIG_PATH"
  exit 0
fi

if [[ "$BACKUP" -eq 1 ]]; then
  BACKUP_STAMP="$(date -u +%Y%m%d-%H%M%S)"
  BACKUP_PATH="$TARGET/.codex_install_backups/codex-bootstrap-kit/$BACKUP_STAMP/.codex_bootstrap/config.json"
  mkdir -p "$(dirname "$BACKUP_PATH")"
  cp "$CONFIG_PATH" "$BACKUP_PATH"
  echo "[orchestrator] backup: .codex_bootstrap/config.json -> ${BACKUP_PATH#$TARGET/}"
fi

cat >"$CONFIG_PATH" <<'JSON'
{
  "project_name": "",
  "required_skills": [],
  "startup_read_order": [
    "scripts/codex_bootstrap.sh",
    ".local_codex/CODEX_LOCAL_CHECKLIST.md",
    "AGENTS.md",
    ".local_codex/PROJECT_AGENT_STATE.json",
    ".local_codex/PROJECT_NAVIGATION.md",
    ".local_codex/PROJECT_DEPENDENCY_GRAPH.md",
    ".local_codex/PROJECT_TREE.txt"
  ],
  "required_files": [
    ".local_codex/AGENT_STATE.md",
    ".local_codex/PROJECT_AGENT_STATE.json",
    ".local_codex/PROJECT_TREE.txt",
    ".local_codex/PROJECT_NAVIGATION.md",
    ".local_codex/PROJECT_DEPENDENCY_GRAPH.md"
  ],
  "exclude_paths": [
    ".git",
    "node_modules",
    ".venv",
    ".cache",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "dist",
    "build",
    "out",
    "target",
    "coverage"
  ],
  "entry_points": {},
  "task_routing": {}
}
JSON

echo "[orchestrator] applied project-agnostic bootstrap config: $CONFIG_PATH"
