# codex-taskflow-kit

Universal, stack-agnostic task solving workflow for Codex projects.

This kit provides a deterministic process for any task:
1. Intake
2. Scope
3. Plan
4. Execute
5. Verify
6. Handoff

It does not depend on backend/frontend/framework specifics.

## Integration With codex-bootstrap-kit

Recommended setup in target repository:

```bash
bash ../codex-bootstrap-kit/bin/install.sh --target . --force
bash ../codex-taskflow-kit/bin/install.sh --target . --force
```

Then start any task:

```bash
bash scripts/codex_task.sh --title "fix auth bug" --text "Login returns 500 for valid credentials"
```

`codex_task.sh` runs `scripts/codex_bootstrap.sh` first (if present), requires checklist `status: PASS`, then creates taskflow artifacts.
Strict mode defaults are enabled:
- `CODEX_TASKFLOW_REQUIRE_BOOTSTRAP=1`
- `CODEX_BOOTSTRAP_REQUIRED=1`

## What it installs

- `scripts/codex_task.sh`
- `.codex_taskflow/config.json`
- `.codex_taskflow/taskflow_engine.py`
- `.codex_taskflow/templates/*.md`

## Output artifacts

Each task creates:

- `work/taskflow/<task_id>/00_intake.md`
- `work/taskflow/<task_id>/10_scope.md`
- `work/taskflow/<task_id>/20_plan.md`
- `work/taskflow/<task_id>/30_execution_log.md`
- `work/taskflow/<task_id>/40_verification.md`
- `work/taskflow/<task_id>/50_handoff.md`
- `work/taskflow/<task_id>/taskflow.json`

## Install Into Any Repo

```bash
bash bin/install.sh --target /path/to/repo
```

Use `--force` to overwrite existing files.
Installer also adds a managed local-only block to target `.gitignore` so taskflow files/artifacts are not tracked.
