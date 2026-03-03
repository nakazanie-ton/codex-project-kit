#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_PATHS=()

log() {
  echo "[test-kits] $1"
}

fail() {
  echo "[test-kits] ERROR: $1" >&2
  exit 1
}

cleanup() {
  local path
  for path in "${TMP_PATHS[@]:-}"; do
    if [[ -e "$path" ]]; then
      rm -rf "$path"
    fi
  done
}

trap cleanup EXIT

assert_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "expected file not found: $path"
}

assert_grep() {
  local pattern="$1"
  local file="$2"
  local message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    fail "$message (pattern: $pattern, file: $file)"
  fi
}

assert_line_count() {
  local pattern="$1"
  local expected="$2"
  local file="$3"
  local message="$4"
  local actual
  actual="$(grep -Ec "$pattern" "$file" || true)"
  [[ "$actual" == "$expected" ]] || fail "$message (expected=$expected actual=$actual file=$file)"
}

run_syntax_gates() {
  log "Running syntax gates"

  local shell_files=()
  while IFS= read -r file; do
    shell_files+=("$file")
  done < <(find "$ROOT_DIR/kits" "$ROOT_DIR/scripts" -type f \( -name "*.sh" -o -path "*/.githooks/pre-commit" \) | sort)
  [[ "${#shell_files[@]}" -gt 0 ]] || fail "no shell files discovered"
  bash -n "${shell_files[@]}"

  local py_files=()
  while IFS= read -r file; do
    py_files+=("$file")
  done < <(find "$ROOT_DIR/kits" -type f -name "*.py" | sort)
  [[ "${#py_files[@]}" -gt 0 ]] || fail "no python files discovered"
  python3 -m py_compile "${py_files[@]}"
}

run_gitignore_resilience_checks() {
  log "Running .gitignore resilience checks"

  local bootstrap_repo taskflow_repo
  bootstrap_repo="$(mktemp -d /tmp/codex-bootstrap-gitignore-test.XXXXXX)"
  taskflow_repo="$(mktemp -d /tmp/codex-taskflow-gitignore-test.XXXXXX)"
  TMP_PATHS+=("$bootstrap_repo" "$taskflow_repo")

  git -C "$bootstrap_repo" init -q
  cat >"$bootstrap_repo/.gitignore" <<'EOF'
# keep-bootstrap-1
# >>> codex-bootstrap-kit (local-only)
.local_codex/
# keep-bootstrap-2
scripts/codex_session.sh
EOF
  bash "$ROOT_DIR/kits/codex-bootstrap-kit/bin/install.sh" --target "$bootstrap_repo" >/dev/null
  bash "$ROOT_DIR/kits/codex-bootstrap-kit/bin/install.sh" --target "$bootstrap_repo" >/dev/null

  assert_grep '^# keep-bootstrap-1$' "$bootstrap_repo/.gitignore" "bootstrap keep line 1 was removed"
  assert_grep '^# keep-bootstrap-2$' "$bootstrap_repo/.gitignore" "bootstrap keep line 2 was removed"
  assert_line_count '^scripts/codex_session\.sh$' "1" "$bootstrap_repo/.gitignore" "bootstrap managed entry duplicated"
  assert_line_count '^# >>> codex-bootstrap-kit \(local-only\)$' "1" "$bootstrap_repo/.gitignore" "bootstrap marker duplicated"

  git -C "$taskflow_repo" init -q
  cat >"$taskflow_repo/.gitignore" <<'EOF'
# keep-taskflow-1
# >>> codex-taskflow-kit (local-only)
.codex_taskflow/
# keep-taskflow-2
work/taskflow/
EOF
  bash "$ROOT_DIR/kits/codex-taskflow-kit/bin/install.sh" --target "$taskflow_repo" >/dev/null
  bash "$ROOT_DIR/kits/codex-taskflow-kit/bin/install.sh" --target "$taskflow_repo" >/dev/null

  assert_grep '^# keep-taskflow-1$' "$taskflow_repo/.gitignore" "taskflow keep line 1 was removed"
  assert_grep '^# keep-taskflow-2$' "$taskflow_repo/.gitignore" "taskflow keep line 2 was removed"
  assert_line_count '^work/taskflow/$' "1" "$taskflow_repo/.gitignore" "taskflow managed entry duplicated"
  assert_line_count '^# >>> codex-taskflow-kit \(local-only\)$' "1" "$taskflow_repo/.gitignore" "taskflow marker duplicated"
}

run_surface_smoke_checks() {
  log "Running surface smoke checks (CLI / Codex App / Agent Skills)"

  local target_repo cli_cmd task_json
  target_repo="$(mktemp -d /tmp/codex-surface-smoke.XXXXXX)"
  TMP_PATHS+=("$target_repo")
  git -C "$target_repo" init -q

  bash "$ROOT_DIR/scripts/one_click_install.sh" "$target_repo" >"$target_repo/install.log"

  assert_file "$target_repo/scripts/codex_session.sh"
  assert_file "$target_repo/scripts/codex_verify_session.sh"
  assert_file "$target_repo/scripts/codex_task.sh"

  # CLI surface: run session with executable path containing spaces.
  cli_cmd="/tmp/codex cli smoke shim.sh"
  TMP_PATHS+=("$cli_cmd")
  cat >"$cli_cmd" <<'EOF'
#!/usr/bin/env bash
echo CLI_SMOKE_OK
EOF
  chmod +x "$cli_cmd"
  CODEX_SESSION_CMD="$cli_cmd" bash "$target_repo/scripts/codex_session.sh" >"$target_repo/cli.out" 2>"$target_repo/cli.err"
  assert_grep '^CLI_SMOKE_OK$' "$target_repo/cli.out" "CLI surface failed to execute CODEX_SESSION_CMD"

  # Codex App surface: setup script + verify action + taskflow action.
  (
    cd "$target_repo"
    CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh --quiet
    bash scripts/codex_verify_session.sh --skip-bootstrap --quiet
  )
  task_json="$(
    cd "$target_repo"
    bash scripts/codex_task.sh --title "Codex App Smoke" --text "Validate codex app surface" --json-path-only | tail -n 1
  )"
  task_json="$(echo "$task_json" | tr -d '\r')"
  assert_file "$task_json"

  # Agent Skills surface: AGENTS startup contract + generated startup order + PASS checklist.
  cat >"$target_repo/AGENTS.md" <<'EOF'
# AGENTS
1. Run `bash scripts/codex_bootstrap.sh`.
2. Confirm `.local_codex/CODEX_LOCAL_CHECKLIST.md` contains `status: PASS`.
3. Continue work after a successful check.
EOF
  (
    cd "$target_repo"
    bash scripts/codex_bootstrap.sh >/dev/null
  )
  assert_grep 'status:[[:space:]]*PASS' "$target_repo/.local_codex/CODEX_LOCAL_CHECKLIST.md" "agent checklist is not PASS"

  python3 - "$target_repo/.local_codex/PROJECT_AGENT_STATE.json" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as fh:
    data = json.load(fh)

required = [
    "scripts/codex_bootstrap.sh",
    ".local_codex/CODEX_LOCAL_CHECKLIST.md",
    "AGENTS.md",
]
order = data.get("navigation", {}).get("startup_read_order", [])
missing = [item for item in required if item not in order]
if missing:
    raise SystemExit("missing startup_read_order entries: " + ", ".join(missing))
PY
}

run_docs_surface_checks() {
  log "Running docs surface checks"
  assert_grep '^- Codex CLI$' "$ROOT_DIR/README.md" "README missing Codex CLI surface"
  assert_grep '^- Codex App$' "$ROOT_DIR/README.md" "README missing Codex App surface"
  assert_grep '^- AGENTS/Skills flow$' "$ROOT_DIR/README.md" "README missing AGENTS/Skills surface"
}

main() {
  run_syntax_gates
  run_gitignore_resilience_checks
  run_surface_smoke_checks
  run_docs_surface_checks
  log "All checks passed"
}

main "$@"
