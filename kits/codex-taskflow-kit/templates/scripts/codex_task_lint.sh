#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$ROOT_DIR/work/taskflow"
TASK_DIR=""
MODE="scaffold"

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/codex_task_lint.sh [--task-dir <path> | --latest] [--mode scaffold|complete]

Modes:
  scaffold  Validate generated taskflow structure and unresolved template tokens.
  complete  Validate scaffold checks plus unresolved placeholders in handoff content.
USAGE
}

fail() {
  echo "[taskflow-lint] ERROR: $1" >&2
  exit 1
}

resolve_task_dir() {
  local latest

  if [[ -n "$TASK_DIR" ]]; then
    [[ -d "$TASK_DIR" ]] || fail "task directory not found: $TASK_DIR"
    TASK_DIR="$(cd "$TASK_DIR" && pwd)"
    return
  fi

  [[ -d "$WORK_DIR" ]] || fail "taskflow work directory not found: $WORK_DIR"
  latest="$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1)"
  [[ -n "$latest" ]] || fail "no taskflow directories found under: $WORK_DIR"
  TASK_DIR="$latest"
}

check_required_files() {
  local required=(
    "$TASK_DIR/00_intake.md"
    "$TASK_DIR/10_scope.md"
    "$TASK_DIR/20_plan.md"
    "$TASK_DIR/30_execution_log.md"
    "$TASK_DIR/40_verification.md"
    "$TASK_DIR/50_handoff.md"
    "$TASK_DIR/taskflow.json"
  )
  local file

  for file in "${required[@]}"; do
    [[ -s "$file" ]] || fail "required file missing or empty: $file"
  done
}

check_unresolved_tokens() {
  local file
  for file in "$TASK_DIR"/*.md; do
    if grep -Eq '\{\{[A-Z0-9_]+\}\}' "$file"; then
      fail "unresolved template token detected: $file"
    fi
  done
}

check_complete_mode() {
  local file
  local placeholder_pattern='^-[[:space:]]*$|^1\.[[:space:]]*$|TODO: add task details|^-[[:space:]]*(Decision|Why|Tradeoff|Symptom|Observed behavior|Expected behavior|Time|Risk tolerance|Non-functional requirements|Components/files likely affected|Dependencies/external systems|Command|Result):[[:space:]]*$'

  for file in "$TASK_DIR"/*.md; do
    if grep -Eq "$placeholder_pattern" "$file"; then
      fail "placeholder-style content remains in complete mode: $file"
    fi
  done
}

while (( $# > 0 )); do
  case "$1" in
    --task-dir)
      shift
      TASK_DIR="${1:-}"
      ;;
    --latest)
      TASK_DIR=""
      ;;
    --mode)
      shift
      MODE="${1:-}"
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

case "$MODE" in
  scaffold|complete) ;;
  *)
    fail "--mode must be scaffold or complete"
    ;;
esac

resolve_task_dir
check_required_files
check_unresolved_tokens

if [[ "$MODE" == "complete" ]]; then
  check_complete_mode
fi

echo "[taskflow-lint] PASS mode=$MODE task_dir=$TASK_DIR"
