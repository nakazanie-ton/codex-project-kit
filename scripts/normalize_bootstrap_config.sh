#!/usr/bin/env bash
set -euo pipefail

TARGET=""
TARGET_SET=0
DRY_RUN=0
BACKUP=0
CHECK_ONLY=0
DRY_RUN_SET=0
BACKUP_SET=0
CHECK_SET=0

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/normalize_bootstrap_config.sh --target /absolute/path/to/target-repo [--check] [--dry-run] [--backup]

Options:
  --target   Absolute path to target repository root
  --check    Validate existing bootstrap config and exit without rewriting
  --dry-run  Print planned action without rewriting config
  --backup   Backup existing config under .codex_install_backups/
USAGE
}

fail() {
  echo "[orchestrator] ERROR: $1" >&2
  exit 1
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR_SCRIPT="$SCRIPT_DIR/validate_json.sh"

validate_bootstrap_config() {
  local config_file="$1"
  bash "$VALIDATOR_SCRIPT" \
    --file "$config_file" \
    --required project_name \
    --required required_skills \
    --required startup_read_order \
    --required required_files \
    --required exclude_paths \
    --required entry_points \
    --required task_routing \
    --type project_name:string \
    --type required_skills:array \
    --type startup_read_order:array \
    --type required_files:array \
    --type exclude_paths:array \
    --type entry_points:object \
    --type task_routing:object
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
    --check)
      [[ "$CHECK_SET" -eq 0 ]] || fail "--check was provided more than once"
      CHECK_ONLY=1
      CHECK_SET=1
      ;;
    --dry-run)
      [[ "$DRY_RUN_SET" -eq 0 ]] || fail "--dry-run was provided more than once"
      DRY_RUN=1
      DRY_RUN_SET=1
      ;;
    --backup)
      [[ "$BACKUP_SET" -eq 0 ]] || fail "--backup was provided more than once"
      BACKUP=1
      BACKUP_SET=1
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

TARGET="$(cd "$TARGET" && pwd)"
CONFIG_PATH="$TARGET/.codex_bootstrap/config.json"
if [[ ! -f "$CONFIG_PATH" ]]; then
  fail "bootstrap config not found: $CONFIG_PATH"
fi

if ! command -v python3 >/dev/null 2>&1; then
  fail "python3 is required"
fi

if [[ ! -x "$VALIDATOR_SCRIPT" ]]; then
  fail "validator script is missing or not executable: $VALIDATOR_SCRIPT"
fi

if [[ "$CHECK_ONLY" -eq 1 && "$DRY_RUN" -eq 1 ]]; then
  fail "--check cannot be used together with --dry-run"
fi

if [[ "$CHECK_ONLY" -eq 1 && "$BACKUP" -eq 1 ]]; then
  fail "--check cannot be used together with --backup"
fi

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  validate_bootstrap_config "$CONFIG_PATH"
  echo "[orchestrator] check: bootstrap config is valid: $CONFIG_PATH"
  exit 0
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
  echo "[orchestrator] backup: .codex_bootstrap/config.json -> ${BACKUP_PATH#"$TARGET"/}"
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
    ".hg",
    ".svn",
    "node_modules",
    ".pnpm-store",
    ".yarn",
    ".turbo",
    ".parcel-cache",
    ".venv",
    "venv",
    "env",
    ".direnv",
    ".tox",
    ".nox",
    "__pypackages__",
    ".eggs",
    ".ipynb_checkpoints",
    ".next",
    ".nuxt",
    ".svelte-kit",
    ".terraform",
    ".terragrunt-cache",
    ".serverless",
    ".aws-sam",
    ".idea",
    ".vscode",
    ".gradle",
    ".dart_tool",
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

validate_bootstrap_config "$CONFIG_PATH"
echo "[orchestrator] applied project-agnostic bootstrap config: $CONFIG_PATH"
