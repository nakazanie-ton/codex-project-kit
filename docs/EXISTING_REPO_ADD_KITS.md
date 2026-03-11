# Existing Repository Runbook (Install Both Kits)

Use this runbook when a repository does not yet have bootstrap/taskflow kits.

## 1. One-Click Install
From the `codex-project-kit` root, run:

```bash
bash scripts/one_click_install.sh --target /absolute/path/to/target-repo
# or legacy positional target:
bash scripts/one_click_install.sh /absolute/path/to/target-repo
```

Optional safety flags:
- `--dry-run` to preview all actions
- `--backup` to back up overwritten files/config
- `--no-force` to preserve existing files
- `--skip-normalize` to preserve existing `.codex_bootstrap/config.json`
- `--skip-verify` to skip strict post-install verification
- `--verify-max-age-seconds N` to tune freshness threshold for verification checks

By default this installer normalizes `.codex_bootstrap/config.json` to a project-agnostic baseline (empty `entry_points` and `task_routing`, no preselected skills).
It uses bundled kit sources under `kits/` and does not clone external repositories.

## 2. CLI Connection
Primary command:

```bash
bash scripts/codex_session.sh
```

Taskflow command:

```bash
bash scripts/codex_task.sh
```

## 3. Codex App Connection
Set Local Environment setup script:

```bash
set -euo pipefail
CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh --quiet
```

Recommended App actions:

1. `Refresh Context`
```bash
bash scripts/codex_verify_session.sh
```

2. `Check Context`
```bash
bash scripts/codex_verify_session.sh --skip-bootstrap --quiet
```

3. `Start Taskflow From Clipboard` (Codex App for Mac)
```bash
bash scripts/codex_task_from_clipboard.sh
```

Avoid wiring `bash scripts/codex_task.sh` directly as a static App action with no task input.
It now refuses empty requests by default to prevent junk `Untitled Task` scaffolds.

## 4. AGENTS/Skills Connection
Add this mandatory startup sequence to `AGENTS.md`:

1. `bash scripts/codex_bootstrap.sh`
2. `cat .local_codex/CODEX_LOCAL_CHECKLIST.md`
3. Continue only if `status: PASS`

Also keep a dedicated `required skills` list in `AGENTS.md` to stabilize process behavior between sessions.

## 5. Post-Install Verification
Run:

```bash
bash scripts/codex_verify_session.sh
```

Expected result:
- Strict verification passes.
- Local artifacts are ignored by git via managed `.gitignore` blocks.
