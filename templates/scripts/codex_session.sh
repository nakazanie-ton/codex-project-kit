#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${CODEX_SESSION_CMD:-}" ]]; then
  read -r -a SESSION_CMD <<<"$CODEX_SESSION_CMD"
elif command -v acodex >/dev/null 2>&1; then
  SESSION_CMD=(acodex)
else
  SESSION_CMD=(codex)
fi

"$SCRIPT_DIR/codex_bootstrap.sh" "${SESSION_CMD[@]}" "$@"
