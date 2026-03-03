# New Repository Runbook (Kits Already Included)

Use this runbook when your repository already contains installed kit artifacts:
- `scripts/codex_bootstrap.sh`
- `scripts/codex_task.sh`
- `scripts/codex_verify_session.sh`
- `.codex_bootstrap/`
- `.codex_taskflow/`

If `.codex_bootstrap/config.json` contains framework-specific defaults, normalize it from this repo:

```bash
bash scripts/normalize_bootstrap_config.sh --target /absolute/path/to/target-repo
```

Optional safety flags:
- `--dry-run` to preview rewrite without changing the file
- `--backup` to keep a backup copy before rewrite

For a single-package source of truth, bundled kit code lives under:
- `kits/codex-bootstrap-kit`
- `kits/codex-taskflow-kit`

## 1. CLI Connection
Use strict startup as the default entrypoint:

```bash
bash scripts/codex_session.sh
```

Manual strict verification:

```bash
CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh
```

## 2. Codex App Connection
Configure one Local Environment setup script:

```bash
set -euo pipefail
CODEX_BOOTSTRAP_REQUIRED=1 bash scripts/codex_verify_session.sh
```

Recommended App actions:

1. `Verify Context`
```bash
bash scripts/codex_verify_session.sh --skip-bootstrap
```

2. `Start Taskflow`
```bash
bash scripts/codex_task.sh
```

## 3. AGENTS/Skills Connection
In `AGENTS.md`, enforce this startup contract:

1. Run `bash scripts/codex_bootstrap.sh`.
2. Confirm `.local_codex/CODEX_LOCAL_CHECKLIST.md` has `status: PASS`.
3. Continue work only after a successful check.

If your team uses local Codex skills, list required skills in `AGENTS.md` and keep them versioned outside the application runtime path.

## 4. Validation Gates
A repository is considered correctly connected when:
- `bash scripts/codex_verify_session.sh` exits with code `0`.
- `.local_codex/CODEX_LOCAL_CHECKLIST.md` contains `status: PASS`.
- `bash scripts/codex_task.sh` runs successfully and writes output under `work/taskflow/`.

## 5. Git Hygiene (local-only artifacts)
Ensure `.gitignore` includes managed blocks from both kits so generated local context and taskflow artifacts never enter git history.
