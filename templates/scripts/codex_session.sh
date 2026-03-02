#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CODEX_BOOTSTRAP_REQUIRED="${CODEX_BOOTSTRAP_REQUIRED:-1}"

if (( $# > 0 )); then
  # Explicit command was passed by caller (for example: acodex -> codex_session.sh codex ...)
  "$SCRIPT_DIR/codex_bootstrap.sh" "$@"
  exit 0
fi

if [[ -n "${CODEX_SESSION_CMD:-}" ]]; then
  read -r -a SESSION_CMD <<<"$CODEX_SESSION_CMD"
else
  # Use codex by default to avoid recursion with wrappers that call codex_session.sh.
  SESSION_CMD=(codex)
fi

"$SCRIPT_DIR/codex_bootstrap.sh" "${SESSION_CMD[@]}"
