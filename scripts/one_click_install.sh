#!/usr/bin/env bash
set -euo pipefail

TARGET=""
TARGET_SET=0
FORCE=1
DRY_RUN=0
BACKUP=0
SKIP_NORMALIZE=0
SKIP_VERIFY=0
VERIFY_MAX_AGE_SECONDS=""
VERIFY_MAX_AGE_SET=0

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/one_click_install.sh --target /absolute/path/to/target-repo [--dry-run] [--backup] [--no-force] [--skip-normalize] [--skip-verify] [--verify-max-age-seconds N]
  bash scripts/one_click_install.sh /absolute/path/to/target-repo [--dry-run] [--backup] [--no-force] [--skip-normalize] [--skip-verify] [--verify-max-age-seconds N]

Options:
  --target   Absolute path to target repository root
            (legacy positional target is also accepted for compatibility)
  --dry-run  Preview installation and normalization actions without writing files
  --backup   Backup overwritten files/config under .codex_install_backups/
  --no-force Do not overwrite files that already exist in target repo
  --skip-normalize            Skip project-agnostic rewrite of .codex_bootstrap/config.json
  --skip-verify               Skip strict verification after install
  --verify-max-age-seconds N  Override freshness limit used by codex_verify_session.sh (default 1800)
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
    --skip-normalize)
      SKIP_NORMALIZE=1
      ;;
    --skip-verify)
      SKIP_VERIFY=1
      ;;
    --verify-max-age-seconds)
      [[ "$VERIFY_MAX_AGE_SET" -eq 0 ]] || fail "--verify-max-age-seconds was provided more than once"
      shift || true
      [[ $# -gt 0 ]] || fail "--verify-max-age-seconds requires a value"
      [[ "${1:-}" != --* ]] || fail "--verify-max-age-seconds requires a numeric value"
      VERIFY_MAX_AGE_SECONDS="$1"
      VERIFY_MAX_AGE_SET=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "$1" == --* ]]; then
        fail "unknown argument: $1"
      fi
      if [[ "$TARGET_SET" -eq 1 ]]; then
        fail "target was provided more than once"
      fi
      TARGET="$1"
      TARGET_SET=1
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

if [[ "$VERIFY_MAX_AGE_SET" -eq 1 ]] && ! [[ "$VERIFY_MAX_AGE_SECONDS" =~ ^[0-9]+$ ]]; then
  fail "--verify-max-age-seconds must be a non-negative integer"
fi

if [[ "$SKIP_VERIFY" -eq 1 && "$VERIFY_MAX_AGE_SET" -eq 1 ]]; then
  fail "--verify-max-age-seconds cannot be used with --skip-verify"
fi

TARGET="$(cd "$TARGET" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_KIT="$REPO_ROOT/kits/codex-bootstrap-kit"
TASKFLOW_KIT="$REPO_ROOT/kits/codex-taskflow-kit"
NORMALIZE_SCRIPT="$SCRIPT_DIR/normalize_bootstrap_config.sh"
KIT_SOURCE_FILE_REL=".codex_bootstrap/KIT_SOURCE_REPO"

write_kit_source_marker() {
  local marker="$TARGET/$KIT_SOURCE_FILE_REL"
  mkdir -p "$(dirname "$marker")"
  printf "%s\n" "$REPO_ROOT" >"$marker"
  echo "[orchestrator] recorded kit source repo marker: $KIT_SOURCE_FILE_REL"
}

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
  if [[ "$SKIP_NORMALIZE" -eq 1 ]]; then
    echo "[orchestrator] dry-run: would skip bootstrap config normalization"
  else
    echo "[orchestrator] dry-run: would normalize bootstrap config: $TARGET/.codex_bootstrap/config.json"
  fi
  echo "[orchestrator] dry-run: would record kit source repo marker: $TARGET/$KIT_SOURCE_FILE_REL"
  if [[ "$SKIP_VERIFY" -eq 1 ]]; then
    echo "[orchestrator] dry-run: would skip strict verification"
  elif [[ "$VERIFY_MAX_AGE_SET" -eq 1 ]]; then
    echo "[orchestrator] dry-run: would run strict verification with --max-age-seconds $VERIFY_MAX_AGE_SECONDS"
  else
    echo "[orchestrator] dry-run: would run strict verification"
  fi
  echo "[orchestrator] dry-run complete: reviewed bundled kit install and normalization actions"
  exit 0
fi

if [[ "$SKIP_NORMALIZE" -eq 1 ]]; then
  echo "[orchestrator] skipped bootstrap normalization (--skip-normalize): preserving current config"
else
  bash "$NORMALIZE_SCRIPT" "${NORMALIZE_ARGS[@]}"
fi

write_kit_source_marker

cd "$TARGET"
if [[ "$SKIP_VERIFY" -eq 1 ]]; then
  echo "[orchestrator] skipped strict verification (--skip-verify)"
else
  if [[ "$VERIFY_MAX_AGE_SET" -eq 1 ]]; then
    CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh --max-age-seconds "$VERIFY_MAX_AGE_SECONDS"
  else
    CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh
  fi
fi

if [[ "$SKIP_NORMALIZE" -eq 1 && "$SKIP_VERIFY" -eq 1 ]]; then
  echo "[orchestrator] done: bundled kits installed; normalization skipped; verification skipped"
elif [[ "$SKIP_NORMALIZE" -eq 1 ]]; then
  echo "[orchestrator] done: bundled kits installed; normalization skipped; strict verification passed"
elif [[ "$SKIP_VERIFY" -eq 1 ]]; then
  echo "[orchestrator] done: bundled kits installed; config normalized; verification skipped"
else
  echo "[orchestrator] done: bundled kits installed; config normalized; strict verification passed"
fi
