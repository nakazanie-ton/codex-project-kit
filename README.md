# codex-bootstrap-kit

Portable bootstrap kit for Codex projects.

This repository extracts the full "start Codex session -> generate local context -> reach ready state" flow into reusable scripts that can be installed into any git project.

## What it installs

- `scripts/codex_bootstrap.sh`
- `scripts/codex_session.sh`
- `scripts/git_pre_commit_sync.sh`
- `scripts/install_git_hooks.sh`
- `.githooks/pre-commit`
- `.codex_bootstrap/bootstrap/codex_bootstrap_core.sh`
- `.codex_bootstrap/bootstrap/generate_codex_state.py`
- `.codex_bootstrap/config.json`
- `.local_codex/AGENT_STATE.md`

## Install Into Any Repo

```bash
bash bin/install.sh --target /path/to/repo
```

Use `--force` to overwrite existing files.

## First Run In Target Repo

```bash
bash scripts/codex_bootstrap.sh
cat .local_codex/CODEX_LOCAL_CHECKLIST.md
```

When checklist shows `status: PASS`, the repo is ready for Codex work.

## Start Session Command

```bash
bash scripts/codex_session.sh
```

Resolution order:
- `CODEX_SESSION_CMD` env var (if set)
- `acodex` (if installed)
- `codex` (fallback)

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

## Extract As Separate GitHub Repo

If this kit is currently vendored inside another repository:

```bash
cd codex-bootstrap-kit
git init
git add .
git commit -m "init codex bootstrap kit"
```

Then push to a dedicated remote and use it as a standalone source.
