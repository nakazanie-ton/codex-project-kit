# codex-bootstrap-kit

Portable bootstrap kit for Codex projects.

This repository extracts the full "start Codex session -> generate local context -> reach ready state" flow into reusable scripts that can be installed into any git project.

## What it installs

- `scripts/codex_bootstrap.sh`
- `scripts/codex_session.sh`
- `scripts/codex_verify_session.sh`
- `scripts/git_pre_commit_sync.sh`
- `scripts/install_git_hooks.sh`
- `.githooks/pre-commit`
- `.codex_bootstrap/bootstrap/codex_bootstrap_core.sh`
- `.codex_bootstrap/bootstrap/generate_codex_state.py`
- `.codex_bootstrap/config.json`
- `.local_codex/AGENT_STATE.md`
- `.local_codex/SESSION_PRIMER.md`

## Install Into Any Repo

```bash
bash bin/install.sh --target /path/to/repo
```

Use `--force` to overwrite existing files.
Use `--dry-run` to preview actions without writing files.
Use `--backup` to save overwritten files under `.codex_install_backups/codex-bootstrap-kit/<timestamp>/`.
Installer also adds a managed local-only block to target `.gitignore` so bootstrap files are not tracked.
Strict mode is enabled by default (`CODEX_BOOTSTRAP_REQUIRED=1` unless explicitly overridden).
Bootstrap output can be tuned with `CODEX_BOOTSTRAP_LOG_LEVEL`:
- `full` (default): print checklist + state excerpts
- `summary`: print checklist + loaded file names only
- `quiet`: suppress non-error output

## First Run In Target Repo

```bash
bash scripts/codex_bootstrap.sh
cat .local_codex/CODEX_LOCAL_CHECKLIST.md
bash scripts/codex_verify_session.sh
```

When checklist shows `status: PASS`, the repo is ready for Codex work.

## Start Session Command

```bash
bash scripts/codex_session.sh
```

Resolution order:
- `CODEX_SESSION_SH` env var (full shell command string; evaluated by `bash -lc`)
- `CODEX_SESSION_CMD` env var (single executable path/name, including paths with spaces)
- `codex` (default)

If both env vars are set, `CODEX_SESSION_SH` takes precedence.

`scripts/codex_session.sh` also accepts an explicit command and arguments:

```bash
bash scripts/codex_session.sh codex --help
```

Automatic context primer (enabled by default):
- `CODEX_SESSION_PRIME_CONTEXT=1` appends a first prompt to `codex` sessions
- primer source order:
  - `CODEX_SESSION_PRIMER_TEXT` (if set)
  - `.local_codex/SESSION_PRIMER.md` (if present)
  - built-in default primer
- default primer also includes taskflow routing hints (`scripts/codex_task.sh`, `work/taskflow/*`, `scripts/codex_task_lint.sh`) when those scripts exist in repo
- set `CODEX_SESSION_PRIME_CONTEXT=0` to disable

## Hook Integration

```bash
bash scripts/install_git_hooks.sh
```

Pre-commit hook runs `scripts/codex_bootstrap.sh` and blocks commit when checklist status is not `PASS`.

## Config

Edit `.codex_bootstrap/config.json` in the target repository to define:
- startup read order
- entry points
- task routing
- required files for checklist
- required skills list

Default template values are intentionally project-agnostic:
- no preselected required skills
- empty `entry_points` and `task_routing`
- generic `exclude_paths` (not tied to a specific backend/frontend stack)
- tree snapshot respects `.gitignore` automatically when running inside a git repository
- `exclude_paths` entries without `/` (for example `node_modules`, `.venv`) are treated as directory-name excludes anywhere in the tree snapshot

## Extract As Separate GitHub Repo

If this kit is currently vendored inside another repository:

```bash
cd codex-bootstrap-kit
git init
git add .
git commit -m "init codex bootstrap kit"
```

Then push to a dedicated remote and use it as a standalone source.
