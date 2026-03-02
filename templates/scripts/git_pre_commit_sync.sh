#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKLIST="$ROOT_DIR/.local_codex/CODEX_LOCAL_CHECKLIST.md"

cd "$ROOT_DIR"

echo "[pre-commit] running Codex bootstrap sync"
bash scripts/codex_bootstrap.sh

if [[ ! -f "$CHECKLIST" ]]; then
  echo "[pre-commit] ERROR: checklist not found: $CHECKLIST" >&2
  exit 1
fi

if ! grep -Eq "status:[[:space:]]*PASS" "$CHECKLIST"; then
  echo "[pre-commit] ERROR: checklist status is not PASS" >&2
  exit 1
fi

echo "[pre-commit] Codex sync status PASS"
