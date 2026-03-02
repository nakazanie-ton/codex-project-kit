#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_SCRIPT="$ROOT_DIR/scripts/codex_bootstrap.sh"
CHECKLIST="$ROOT_DIR/.local_codex/CODEX_LOCAL_CHECKLIST.md"
STATE_JSON="$ROOT_DIR/.local_codex/PROJECT_AGENT_STATE.json"
NAV_FILE="$ROOT_DIR/.local_codex/PROJECT_NAVIGATION.md"
DEP_FILE="$ROOT_DIR/.local_codex/PROJECT_DEPENDENCY_GRAPH.md"
TREE_FILE="$ROOT_DIR/.local_codex/PROJECT_TREE.txt"
AGENT_STATE_FILE="$ROOT_DIR/.local_codex/AGENT_STATE.md"

RUN_BOOTSTRAP=1
MAX_AGE_SECONDS="${CODEX_VERIFY_MAX_AGE_SECONDS:-1800}"
QUIET=0

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/codex_verify_session.sh [--skip-bootstrap] [--max-age-seconds N] [--quiet]

Checks:
- strict bootstrap execution (unless --skip-bootstrap)
- checklist status PASS
- required local context files exist and are non-empty
- timestamps are fresh (default <= 1800s old)
- startup_read_order in PROJECT_AGENT_STATE.json contains mandatory entries
USAGE
}

log() {
  if [[ "$QUIET" != "1" ]]; then
    echo "$1"
  fi
}

fail() {
  echo "[verify] ERROR: $1" >&2
  exit 1
}

require_nonempty_file() {
  local path="$1"
  [[ -s "$path" ]] || fail "required file missing or empty: $path"
}

while (( $# > 0 )); do
  case "$1" in
    --skip-bootstrap)
      RUN_BOOTSTRAP=0
      ;;
    --max-age-seconds)
      shift
      MAX_AGE_SECONDS="${1:-}"
      ;;
    --quiet)
      QUIET=1
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

if ! [[ "$MAX_AGE_SECONDS" =~ ^[0-9]+$ ]]; then
  fail "--max-age-seconds must be a non-negative integer"
fi

if (( RUN_BOOTSTRAP == 1 )); then
  [[ -x "$BOOTSTRAP_SCRIPT" ]] || fail "bootstrap script not executable: $BOOTSTRAP_SCRIPT"
  log "[verify] running bootstrap in strict mode"
  CODEX_BOOTSTRAP_REQUIRED=1 bash "$BOOTSTRAP_SCRIPT" >/dev/null
fi

require_nonempty_file "$CHECKLIST"
require_nonempty_file "$STATE_JSON"
require_nonempty_file "$NAV_FILE"
require_nonempty_file "$DEP_FILE"
require_nonempty_file "$TREE_FILE"
require_nonempty_file "$AGENT_STATE_FILE"

if ! grep -Eq "status:[[:space:]]*PASS" "$CHECKLIST"; then
  fail "checklist status is not PASS: $CHECKLIST"
fi

BOOTSTRAP_AT="$(sed -n 's/^- bootstrap_at:[[:space:]]*//p' "$CHECKLIST" | head -n1 | tr -d '\r')"
[[ -n "$BOOTSTRAP_AT" ]] || fail "bootstrap_at missing in checklist"

GENERATED_AT="$(
  python3 - "$STATE_JSON" <<'PY'
import json
import sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
print(data.get("generated_at", "").strip())
PY
)"
[[ -n "$GENERATED_AT" ]] || fail "generated_at missing in PROJECT_AGENT_STATE.json"

if ! python3 - "$BOOTSTRAP_AT" "$GENERATED_AT" "$MAX_AGE_SECONDS" <<'PY'
import datetime as dt
import sys

bootstrap_at = sys.argv[1]
generated_at = sys.argv[2]
max_age = int(sys.argv[3])

def parse_iso(value: str) -> dt.datetime:
    return dt.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc)

now = dt.datetime.now(tz=dt.timezone.utc)
bootstrap_ts = parse_iso(bootstrap_at)
generated_ts = parse_iso(generated_at)

age_bootstrap = int((now - bootstrap_ts).total_seconds())
age_generated = int((now - generated_ts).total_seconds())

if age_bootstrap < 0 or age_generated < 0:
    raise SystemExit("timestamps are in the future")

if age_bootstrap > max_age or age_generated > max_age:
    raise SystemExit(
        f"stale context detected (bootstrap_age={age_bootstrap}s, generated_age={age_generated}s, limit={max_age}s)"
    )
PY
then
  fail "timestamps are stale or invalid"
fi

if ! python3 - "$STATE_JSON" <<'PY'
import json
import sys

required = [
    "scripts/codex_bootstrap.sh",
    ".local_codex/CODEX_LOCAL_CHECKLIST.md",
    ".local_codex/PROJECT_AGENT_STATE.json",
    ".local_codex/PROJECT_NAVIGATION.md",
    ".local_codex/PROJECT_DEPENDENCY_GRAPH.md",
]

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)

order = data.get("navigation", {}).get("startup_read_order", [])
missing = [item for item in required if item not in order]
if missing:
    raise SystemExit("missing startup_read_order entries: " + ", ".join(missing))
PY
then
  fail "startup_read_order contract failed"
fi

log "[verify] checklist status: PASS"
log "[verify] bootstrap_at: $BOOTSTRAP_AT"
log "[verify] generated_at: $GENERATED_AT"
log "[verify] session context verification passed"
