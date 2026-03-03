#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_PATHS=()
VALIDATE_JSON_SCRIPT="$ROOT_DIR/scripts/validate_json.sh"

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

run_shell_and_json_gates() {
  log "Running shell and JSON gates"

  local shell_files=()
  while IFS= read -r file; do
    shell_files+=("$file")
  done < <(find "$ROOT_DIR/kits" "$ROOT_DIR/scripts" -type f \( -name "*.sh" -o -path "*/.githooks/pre-commit" \) | sort)
  [[ "${#shell_files[@]}" -gt 0 ]] || fail "no shell files discovered"
  bash -n "${shell_files[@]}"

  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "${shell_files[@]}"
  else
    log "shellcheck not found; skipping shellcheck gate"
  fi

  bash "$VALIDATE_JSON_SCRIPT" \
    --file "$ROOT_DIR/kits/codex-bootstrap-kit/templates/.codex_bootstrap/config.json" \
    --required project_name \
    --required required_skills \
    --required startup_read_order \
    --required required_files \
    --required exclude_paths \
    --required entry_points \
    --required task_routing \
    --type project_name:string \
    --type required_skills:array \
    --type startup_read_order:array \
    --type required_files:array \
    --type exclude_paths:array \
    --type entry_points:object \
    --type task_routing:object

  bash "$VALIDATE_JSON_SCRIPT" \
    --file "$ROOT_DIR/kits/codex-taskflow-kit/templates/.codex_taskflow/config.json" \
    --required workflow_name \
    --required version \
    --required out_dir \
    --required steps \
    --required artifacts \
    --type workflow_name:string \
    --type version:string \
    --type out_dir:string \
    --type steps:array \
    --type artifacts:object
}

run_python_compile_gates() {
  log "Running python compile gates"

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

run_non_destructive_mode_checks() {
  log "Running non-destructive mode checks"

  local backup_repo dry_run_repo backup_root backup_file_path config_backup_count

  backup_repo="$(mktemp -d /tmp/codex-backup-mode-test.XXXXXX)"
  dry_run_repo="$(mktemp -d /tmp/codex-dry-run-mode-test.XXXXXX)"
  TMP_PATHS+=("$backup_repo" "$dry_run_repo")

  git -C "$backup_repo" init -q
  mkdir -p "$backup_repo/scripts" "$backup_repo/.codex_bootstrap"
  cat >"$backup_repo/scripts/codex_session.sh" <<'EOF'
#!/usr/bin/env bash
echo ORIGINAL_SESSION
EOF
  cat >"$backup_repo/.codex_bootstrap/config.json" <<'EOF'
{"project_name":"before-normalize"}
EOF
  chmod +x "$backup_repo/scripts/codex_session.sh"

  bash "$ROOT_DIR/kits/codex-bootstrap-kit/bin/install.sh" --target "$backup_repo" --force --backup >/dev/null
  assert_grep '^#!/usr/bin/env bash$' "$backup_repo/scripts/codex_session.sh" "bootstrap install did not overwrite target file"

  backup_root="$(find "$backup_repo/.codex_install_backups/codex-bootstrap-kit" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "${backup_root:-}" ]] || fail "backup directory was not created for bootstrap installer"
  backup_file_path="$backup_root/scripts/codex_session.sh"
  assert_file "$backup_file_path"
  assert_grep '^echo ORIGINAL_SESSION$' "$backup_file_path" "backup file does not contain original script content"

  sleep 1
  bash "$ROOT_DIR/scripts/normalize_bootstrap_config.sh" --target "$backup_repo" --backup >/dev/null
  assert_grep '"project_name":[[:space:]]*""' "$backup_repo/.codex_bootstrap/config.json" "normalize script did not rewrite config"
  config_backup_count="$(find "$backup_repo/.codex_install_backups/codex-bootstrap-kit" -type f -path '*/.codex_bootstrap/config.json' | wc -l | tr -d ' ')"
  if [[ "$config_backup_count" -lt 2 ]]; then
    fail "expected config backups from installer + normalize step, found $config_backup_count"
  fi

  git -C "$dry_run_repo" init -q
  bash "$ROOT_DIR/scripts/one_click_install.sh" --target "$dry_run_repo" --dry-run >"$dry_run_repo/dry-run.log"
  if [[ -e "$dry_run_repo/scripts/codex_bootstrap.sh" ]]; then
    fail "one_click_install --dry-run unexpectedly wrote files"
  fi
  assert_grep 'dry-run: skipped strict verification' "$dry_run_repo/dry-run.log" "dry-run output missing verification skip message"
}

run_config_validation_checks() {
  log "Running config validation checks"

  local validation_repo bootstrap_json_status bootstrap_required_status bootstrap_status taskflow_json_status taskflow_status
  validation_repo="$(mktemp -d /tmp/codex-config-validation-test.XXXXXX)"
  TMP_PATHS+=("$validation_repo")
  git -C "$validation_repo" init -q

  bash "$ROOT_DIR/scripts/one_click_install.sh" --target "$validation_repo" >/dev/null

  cat >"$validation_repo/.codex_bootstrap/config.json" <<'EOF'
{
EOF
  set +e
  bash "$ROOT_DIR/scripts/normalize_bootstrap_config.sh" --target "$validation_repo" --check >"$validation_repo/bootstrap-check-invalid-json.out" 2>"$validation_repo/bootstrap-check-invalid-json.err"
  bootstrap_json_status=$?
  set -e
  [[ "$bootstrap_json_status" -ne 0 ]] || fail "bootstrap --check unexpectedly passed invalid JSON"
  assert_grep 'invalid JSON' "$validation_repo/bootstrap-check-invalid-json.err" "bootstrap invalid JSON message missing"

  cat >"$validation_repo/.codex_bootstrap/config.json" <<'EOF'
{
  "project_name": ""
}
EOF
  set +e
  bash "$ROOT_DIR/scripts/normalize_bootstrap_config.sh" --target "$validation_repo" --check >"$validation_repo/bootstrap-check-required.out" 2>"$validation_repo/bootstrap-check-required.err"
  bootstrap_required_status=$?
  set -e
  [[ "$bootstrap_required_status" -ne 0 ]] || fail "bootstrap --check unexpectedly passed missing required fields"
  assert_grep "missing required field: 'required_skills'" "$validation_repo/bootstrap-check-required.err" "bootstrap missing-required message missing"

  cat >"$validation_repo/.codex_bootstrap/config.json" <<'EOF'
{
  "startup_read_order": "not-a-list"
}
EOF
  set +e
  (
    cd "$validation_repo"
    bash scripts/codex_bootstrap.sh >"$validation_repo/bootstrap-invalid.out" 2>"$validation_repo/bootstrap-invalid.err"
  )
  bootstrap_status=$?
  set -e
  [[ "$bootstrap_status" -ne 0 ]] || fail "invalid bootstrap config unexpectedly passed"
  assert_grep "startup_read_order' must be a list of strings|expected array" "$validation_repo/bootstrap-invalid.err" "bootstrap config validation message missing"

  bash "$ROOT_DIR/scripts/normalize_bootstrap_config.sh" --target "$validation_repo" >/dev/null

  cat >"$validation_repo/.codex_taskflow/config.json" <<'EOF'
{
EOF
  set +e
  (
    cd "$validation_repo"
    bash scripts/codex_task.sh --title "Invalid taskflow json" --text "must fail" >"$validation_repo/taskflow-invalid-json.out" 2>"$validation_repo/taskflow-invalid-json.err"
  )
  taskflow_json_status=$?
  set -e
  [[ "$taskflow_json_status" -ne 0 ]] || fail "invalid taskflow JSON unexpectedly passed"
  assert_grep "Invalid JSON config .*\\.codex_taskflow/config\\.json" "$validation_repo/taskflow-invalid-json.err" "taskflow invalid JSON message missing"

  cat >"$validation_repo/.codex_taskflow/config.json" <<'EOF'
{
  "workflow_name": "bad-taskflow",
  "version": "1.0.0",
  "out_dir": "work/taskflow",
  "steps": [],
  "artifacts": {}
}
EOF
  set +e
  (
    cd "$validation_repo"
    bash scripts/codex_task.sh --title "Invalid taskflow config" --text "must fail" >"$validation_repo/taskflow-invalid.out" 2>"$validation_repo/taskflow-invalid.err"
  )
  taskflow_status=$?
  set -e
  [[ "$taskflow_status" -ne 0 ]] || fail "invalid taskflow config unexpectedly passed"
  assert_grep "missing required step id\\(s\\)|missing required artifact key\\(s\\)" "$validation_repo/taskflow-invalid.err" "taskflow config validation message missing"
}

run_surface_smoke_checks() {
  log "Running surface smoke checks (CLI / Codex App / Agent Skills)"

  local target_repo cli_cmd task_json codex_prime_dir
  target_repo="$(mktemp -d /tmp/codex-surface-smoke.XXXXXX)"
  TMP_PATHS+=("$target_repo")
  git -C "$target_repo" init -q

  bash "$ROOT_DIR/scripts/one_click_install.sh" --target "$target_repo" >"$target_repo/install.log"

  assert_file "$target_repo/scripts/codex_session.sh"
  assert_file "$target_repo/scripts/codex_verify_session.sh"
  assert_file "$target_repo/scripts/codex_task.sh"
  assert_file "$target_repo/scripts/codex_task_lint.sh"
  assert_file "$target_repo/.local_codex/SESSION_PRIMER.md"
  assert_grep 'scripts/codex_task\.sh' "$target_repo/.local_codex/SESSION_PRIMER.md" "session primer missing taskflow bootstrap routing"
  assert_grep 'scripts/codex_task_lint\.sh --latest --mode complete' "$target_repo/.local_codex/SESSION_PRIMER.md" "session primer missing taskflow lint routing"

  # Bootstrap output control surface.
  (
    cd "$target_repo"
    CODEX_BOOTSTRAP_LOG_LEVEL=summary bash scripts/codex_bootstrap.sh >"$target_repo/bootstrap-summary.out" 2>"$target_repo/bootstrap-summary.err"
    CODEX_BOOTSTRAP_LOG_LEVEL=quiet bash scripts/codex_bootstrap.sh >"$target_repo/bootstrap-quiet.out" 2>"$target_repo/bootstrap-quiet.err"
  )
  assert_grep '^- loaded: AGENT_STATE\.md$' "$target_repo/bootstrap-summary.out" "summary log level did not emit loaded file names"
  if grep -Eq '^## Scope$' "$target_repo/bootstrap-summary.out"; then
    fail "summary log level leaked full state file content"
  fi
  if [[ -s "$target_repo/bootstrap-quiet.out" ]]; then
    fail "quiet log level unexpectedly emitted stdout"
  fi

  # Session primer surface: codex session should inject first prompt by default.
  codex_prime_dir="$(mktemp -d /tmp/codex-prime-bin.XXXXXX)"
  TMP_PATHS+=("$codex_prime_dir")
  cat >"$codex_prime_dir/codex" <<'EOF'
#!/usr/bin/env bash
echo "ARGC:$#"
echo "ARG1:${1:-}"
EOF
  chmod +x "$codex_prime_dir/codex"

  (
    cd "$target_repo"
    CODEX_BOOTSTRAP_LOG_LEVEL=quiet \
    CODEX_SESSION_CMD="$codex_prime_dir/codex" \
    CODEX_SESSION_PRIMER_TEXT="PRIMER_TOKEN_X1" \
    bash scripts/codex_session.sh >"$target_repo/primer-on.out" 2>"$target_repo/primer-on.err"

    CODEX_BOOTSTRAP_LOG_LEVEL=quiet \
    CODEX_SESSION_CMD="$codex_prime_dir/codex" \
    CODEX_SESSION_PRIME_CONTEXT=0 \
    CODEX_SESSION_PRIMER_TEXT="PRIMER_TOKEN_X1" \
    bash scripts/codex_session.sh >"$target_repo/primer-off.out" 2>"$target_repo/primer-off.err"
  )
  assert_grep '^ARGC:1$' "$target_repo/primer-on.out" "session primer did not pass prompt argument by default"
  assert_grep '^ARG1:PRIMER_TOKEN_X1$' "$target_repo/primer-on.out" "session primer text mismatch"
  assert_grep '^ARGC:0$' "$target_repo/primer-off.out" "session primer disable flag did not suppress injected prompt"

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

  (
    cd "$target_repo"
    bash scripts/codex_task_lint.sh --latest --mode scaffold >"$target_repo/taskflow-lint-scaffold.out"
  )
  assert_grep 'PASS mode=scaffold' "$target_repo/taskflow-lint-scaffold.out" "taskflow scaffold lint did not pass"

  set +e
  (
    cd "$target_repo"
    bash scripts/codex_task_lint.sh --latest --mode complete >"$target_repo/taskflow-lint-complete.out" 2>"$target_repo/taskflow-lint-complete.err"
  )
  local lint_complete_status=$?
  set -e
  [[ "$lint_complete_status" -ne 0 ]] || fail "taskflow complete lint unexpectedly passed on scaffold artifacts"
  assert_grep 'placeholder-style content remains in complete mode' "$target_repo/taskflow-lint-complete.err" "taskflow complete lint missing expected failure signal"

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
  assert_grep 'scripts/one_click_install\.sh --target /absolute/path/to/target-repo' "$ROOT_DIR/README.md" "README missing --target usage for one_click_install"
  assert_grep '\[LICENSE\]\(LICENSE\)' "$ROOT_DIR/README.md" "README missing LICENSE link"
  assert_grep '\[SECURITY\.md\]\(SECURITY\.md\)' "$ROOT_DIR/README.md" "README missing SECURITY link"
}

main() {
  run_shell_and_json_gates
  run_python_compile_gates
  run_gitignore_resilience_checks
  run_non_destructive_mode_checks
  run_config_validation_checks
  run_surface_smoke_checks
  run_docs_surface_checks
  log "All checks passed"
}

main "$@"
