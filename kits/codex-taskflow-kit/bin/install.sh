#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATES_DIR="$KIT_ROOT/templates"

TARGET=""
TARGET_SET=0
FORCE=0
DRY_RUN=0
BACKUP=0
BACKUP_ROOT=""
BACKUP_STAMP=""

usage() {
  cat <<'USAGE'
Usage:
  bash bin/install.sh --target <repo_path> [--force] [--dry-run] [--backup]

Options:
  --target   Target repository root where taskflow files will be installed
  --force    Overwrite existing files
  --dry-run  Print planned actions without writing files
  --backup   Backup overwritten files under .codex_install_backups/
USAGE
}

fail() {
  echo "[install] ERROR: $1" >&2
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
    --force)
      FORCE=1
      ;;
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
      fail "unknown argument: $1"
      ;;
  esac
  shift || true
done

if [[ "$TARGET_SET" -ne 1 ]]; then
  fail "--target is required"
fi

[[ -d "$TARGET" ]] || fail "target directory not found: $TARGET"
TARGET="$(cd "$TARGET" && pwd)"

ensure_path_within_target() {
  local abs_path="$1"
  if [[ "$abs_path" != "$TARGET" && "$abs_path" != "$TARGET/"* ]]; then
    echo "[install] ERROR: resolved path escapes target root: $abs_path" >&2
    exit 1
  fi
}

ensure_no_symlink_components() {
  local abs_path="$1"
  local rel_path current part

  ensure_path_within_target "$abs_path"
  [[ "$abs_path" == "$TARGET" ]] && return

  rel_path="${abs_path#"$TARGET"/}"
  current="$TARGET"
  IFS='/' read -r -a parts <<< "$rel_path"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    current="$current/$part"
    if [[ -L "$current" ]]; then
      echo "[install] ERROR: refusing to write through symlink path: $current" >&2
      exit 1
    fi
  done
}

ensure_safe_write_destination() {
  local dst="$1"
  local dst_dir

  dst_dir="$(dirname "$dst")"
  ensure_no_symlink_components "$dst_dir"
  if [[ -L "$dst" ]]; then
    echo "[install] ERROR: refusing to overwrite symlink destination: $dst" >&2
    exit 1
  fi
}

backup_file() {
  local rel="$1"
  local src="$2"
  local clean_rel backup_path

  [[ "$BACKUP" -eq 1 ]] || return 0
  [[ -f "$src" ]] || return 0

  if [[ -z "$BACKUP_STAMP" ]]; then
    BACKUP_STAMP="$(date -u +%Y%m%d-%H%M%S)"
  fi

  if [[ -z "$BACKUP_ROOT" ]]; then
    BACKUP_ROOT="$TARGET/.codex_install_backups/codex-taskflow-kit/$BACKUP_STAMP"
  fi

  clean_rel="${rel#./}"
  backup_path="$BACKUP_ROOT/$clean_rel"
  ensure_safe_write_destination "$backup_path"
  mkdir -p "$(dirname "$backup_path")"
  cp "$src" "$backup_path"
  echo "[install] backup: $clean_rel -> ${backup_path#"$TARGET"/}"
}

ensure_gitignore_block() {
  local gitignore_file="$TARGET/.gitignore"
  local start_marker="# >>> codex-taskflow-kit (local-only)"
  local end_marker="# <<< codex-taskflow-kit (local-only)"
  local tmp_file
  local source_file="$gitignore_file"
  local managed_regex='^(\.codex_taskflow/|scripts/codex_task\.sh|scripts/codex_task_lint\.sh|work/taskflow/)$'

  ensure_safe_write_destination "$gitignore_file"

  if [[ ! -f "$gitignore_file" ]]; then
    if [[ "$DRY_RUN" -eq 1 ]]; then
      source_file="/dev/null"
      echo "[install] dry-run: create .gitignore"
    else
      touch "$gitignore_file"
    fi
  fi

  # Normalize by removing any previous managed markers/entries first.
  # This is resilient even when older installs left malformed marker pairs.
  tmp_file="$(mktemp)"
  awk -v start="$start_marker" -v end="$end_marker" -v managed_regex="$managed_regex" '
    $0 == start || $0 == end {next}
    $0 ~ managed_regex {next}
    {print}
  ' "$source_file" > "$tmp_file"

  {
    printf "\n%s\n" "$start_marker"
    printf "%s\n" ".codex_taskflow/"
    printf "%s\n" "scripts/codex_task.sh"
    printf "%s\n" "scripts/codex_task_lint.sh"
    printf "%s\n" "work/taskflow/"
    printf "%s\n" "$end_marker"
  } >> "$tmp_file"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    rm -f "$tmp_file"
    echo "[install] dry-run: synchronized .gitignore block: codex-taskflow-kit"
    return
  fi

  backup_file ".gitignore" "$gitignore_file"
  mv "$tmp_file" "$gitignore_file"

  echo "[install] synchronized .gitignore block: codex-taskflow-kit"
}

copy_file() {
  local rel="$1"
  local src="$TEMPLATES_DIR/$rel"
  local dst="$TARGET/$rel"

  if [[ ! -f "$src" ]]; then
    echo "[install] ERROR: template file not found: $src" >&2
    exit 1
  fi

  if [[ -f "$dst" && "$FORCE" -ne 1 ]]; then
    echo "[install] skip (exists): $rel"
    return
  fi

  if [[ "$DRY_RUN" -eq 1 ]]; then
    if [[ -f "$dst" ]]; then
      echo "[install] dry-run: overwrite: $rel"
    else
      echo "[install] dry-run: write: $rel"
    fi
    return
  fi

  ensure_safe_write_destination "$dst"
  mkdir -p "$(dirname "$dst")"
  backup_file "$rel" "$dst"
  cp "$src" "$dst"
  echo "[install] write: $rel"
}

FILES=(
  "scripts/codex_task.sh"
  "scripts/codex_task_lint.sh"
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

ensure_gitignore_block

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[install] dry-run: chmod +x scripts and engine"
else
  chmod +x \
    "$TARGET/scripts/codex_task.sh" \
    "$TARGET/scripts/codex_task_lint.sh" \
    "$TARGET/.codex_taskflow/taskflow_engine.py"
fi

echo "[install] done"
echo "[install] next: bash $TARGET/scripts/codex_task.sh --help"
