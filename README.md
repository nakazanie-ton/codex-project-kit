# codex-project-kit

Unified repository for Codex bootstrap and taskflow in one package.

This repo contains operator-grade instructions for three integration surfaces:
- Codex CLI
- Codex App
- AGENTS/Skills flow

## Bundled Kits
- `kits/codex-bootstrap-kit`
- `kits/codex-taskflow-kit`

## Runbooks
- `docs/NEW_REPO_WITH_PREINSTALLED_KITS.md`
- `docs/EXISTING_REPO_ADD_KITS.md`

## One-click installer (for existing repositories)
```bash
bash scripts/one_click_install.sh /absolute/path/to/target-repo
```

Optional flags:
- `--dry-run` preview install/normalize actions without writing files
- `--backup` backup overwritten files/config under `.codex_install_backups/`
- `--no-force` keep existing target files instead of overwriting

Installer behavior:
- installs both bundled kits (offline/local source, no git clone)
- rewrites `.codex_bootstrap/config.json` to project-agnostic defaults (no framework-specific entry points/routing)
- runs strict verification

## Quality Gates
Run the same validation bundle used in CI:

```bash
bash scripts/test_kits.sh
```

Coverage includes:
- syntax checks for shell/python sources
- installer `.gitignore` resilience and idempotency
- config validation failure checks for bootstrap/taskflow JSON
- taskflow lint checks (`scaffold` pass, `complete` fail-on-placeholders)
- CLI applicability (`codex_session.sh`)
- Codex App applicability (`codex_verify_session.sh`, `codex_task.sh`)
- AGENTS/Skills applicability (startup contract and checklist state)
