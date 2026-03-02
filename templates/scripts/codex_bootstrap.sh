#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE="$ROOT_DIR/.codex_bootstrap/bootstrap/codex_bootstrap_core.sh"
STRICT="${CODEX_BOOTSTRAP_REQUIRED:-1}"

if [[ -x "$CORE" ]]; then
  "$CORE"
else
  echo "[codex-bootstrap] WARNING: bootstrap core not found or not executable: $CORE" >&2
  if [[ "$STRICT" == "1" ]]; then
    echo "[codex-bootstrap] Set CODEX_BOOTSTRAP_REQUIRED=0 to continue without bootstrap." >&2
    exit 1
  fi
  echo "[codex-bootstrap] Continue without bootstrap." >&2
fi

if (( $# > 0 )); then
  "$@"
fi
