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
  --target   Target repository root where bootstrap files will be installed
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
    BACKUP_ROOT="$TARGET/.codex_install_backups/codex-bootstrap-kit/$BACKUP_STAMP"
  fi

  clean_rel="${rel#./}"
  backup_path="$BACKUP_ROOT/$clean_rel"
  mkdir -p "$(dirname "$backup_path")"
  cp "$src" "$backup_path"
  echo "[install] backup: $clean_rel -> ${backup_path#"$TARGET"/}"
}

if [[ ! -d "$TARGET/.git" ]]; then
  echo "[install] WARNING: $TARGET does not look like a git repository (.git not found)" >&2
fi

ensure_gitignore_block() {
  local gitignore_file="$TARGET/.gitignore"
  local start_marker="# >>> codex-bootstrap-kit (local-only)"
  local end_marker="# <<< codex-bootstrap-kit (local-only)"
  local tmp_file
  local source_file="$gitignore_file"
  local managed_regex='^(\.local_codex/|\.codex_bootstrap/|\.githooks/pre-commit|scripts/codex_bootstrap\.sh|scripts/codex_session\.sh|scripts/codex_verify_session\.sh|scripts/git_pre_commit_sync\.sh|scripts/install_git_hooks\.sh)$'

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
    printf "%s\n" ".local_codex/"
    printf "%s\n" ".codex_bootstrap/"
    printf "%s\n" ".githooks/pre-commit"
    printf "%s\n" "scripts/codex_bootstrap.sh"
    printf "%s\n" "scripts/codex_session.sh"
    printf "%s\n" "scripts/codex_verify_session.sh"
    printf "%s\n" "scripts/git_pre_commit_sync.sh"
    printf "%s\n" "scripts/install_git_hooks.sh"
    printf "%s\n" "$end_marker"
  } >> "$tmp_file"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    rm -f "$tmp_file"
    echo "[install] dry-run: synchronized .gitignore block: codex-bootstrap-kit"
    return
  fi

  backup_file ".gitignore" "$gitignore_file"
  mv "$tmp_file" "$gitignore_file"

  echo "[install] synchronized .gitignore block: codex-bootstrap-kit"
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

  mkdir -p "$(dirname "$dst")"
  backup_file "$rel" "$dst"
  cp "$src" "$dst"
  echo "[install] write: $rel"
}

FILES=(
  "scripts/codex_bootstrap.sh"
  "scripts/codex_session.sh"
  "scripts/codex_verify_session.sh"
  "scripts/git_pre_commit_sync.sh"
  "scripts/install_git_hooks.sh"
  ".githooks/pre-commit"
  ".codex_bootstrap/bootstrap/codex_bootstrap_core.sh"
  ".codex_bootstrap/bootstrap/generate_codex_state.py"
  ".codex_bootstrap/config.json"
  ".local_codex/AGENT_STATE.md"
  ".local_codex/SESSION_PRIMER.md"
)

for rel in "${FILES[@]}"; do
  copy_file "$rel"
done

ensure_gitignore_block

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "[install] dry-run: chmod +x scripts and hooks"
else
  chmod +x \
    "$TARGET/scripts/codex_bootstrap.sh" \
    "$TARGET/scripts/codex_session.sh" \
    "$TARGET/scripts/codex_verify_session.sh" \
    "$TARGET/scripts/git_pre_commit_sync.sh" \
    "$TARGET/scripts/install_git_hooks.sh" \
    "$TARGET/.githooks/pre-commit" \
    "$TARGET/.codex_bootstrap/bootstrap/codex_bootstrap_core.sh"
fi

echo "[install] done"
echo "[install] next: bash $TARGET/scripts/codex_bootstrap.sh"
