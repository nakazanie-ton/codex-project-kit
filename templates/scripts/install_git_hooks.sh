#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRE_COMMIT_HOOK="$ROOT_DIR/.githooks/pre-commit"
SYNC_SCRIPT="$ROOT_DIR/scripts/git_pre_commit_sync.sh"

cd "$ROOT_DIR"

if ! command -v git >/dev/null 2>&1; then
  echo "[hooks] ERROR: git is not available" >&2
  exit 1
fi

if [[ ! -f "$PRE_COMMIT_HOOK" ]]; then
  echo "[hooks] ERROR: pre-commit hook not found: $PRE_COMMIT_HOOK" >&2
  exit 1
fi

if [[ ! -f "$SYNC_SCRIPT" ]]; then
  echo "[hooks] ERROR: sync script not found: $SYNC_SCRIPT" >&2
  exit 1
fi

chmod +x "$PRE_COMMIT_HOOK" "$SYNC_SCRIPT"
git config core.hooksPath .githooks

echo "[hooks] Installed: core.hooksPath=.githooks"
echo "[hooks] Active hook: .githooks/pre-commit"
