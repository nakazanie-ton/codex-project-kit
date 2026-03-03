#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/one_click_install.sh /absolute/path/to/target-repo" >&2
  exit 1
fi

TARGET="$1"
if [[ ! -d "$TARGET" ]]; then
  echo "[orchestrator] ERROR: target directory not found: $TARGET" >&2
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BOOTSTRAP_KIT="$REPO_ROOT/kits/codex-bootstrap-kit"
TASKFLOW_KIT="$REPO_ROOT/kits/codex-taskflow-kit"

if [[ ! -f "$BOOTSTRAP_KIT/bin/install.sh" ]]; then
  echo "[orchestrator] ERROR: missing bundled bootstrap kit: $BOOTSTRAP_KIT" >&2
  exit 1
fi

if [[ ! -f "$TASKFLOW_KIT/bin/install.sh" ]]; then
  echo "[orchestrator] ERROR: missing bundled taskflow kit: $TASKFLOW_KIT" >&2
  exit 1
fi

bash "$BOOTSTRAP_KIT/bin/install.sh" --target "$TARGET" --force
bash "$TASKFLOW_KIT/bin/install.sh" --target "$TARGET" --force
bash "$SCRIPT_DIR/normalize_bootstrap_config.sh" "$TARGET"

cd "$TARGET"
CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh

echo "[orchestrator] done: bundled kits installed, config normalized, and strict verification passed"
