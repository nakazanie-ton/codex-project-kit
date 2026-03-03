# codex-project-kit

Codex project bootstrap + taskflow kit in one package.

Legal and security:
- [LICENSE](LICENSE)
- [SECURITY.md](SECURITY.md)

This repo is designed to work across three integration surfaces:
- Codex CLI
- Codex App
- AGENTS/Skills flow

## What This Tool Is
`codex-project-kit` is an installer + runtime toolkit that makes Codex sessions reproducible in any git repository.

It combines two capabilities:
- session/bootstrap state management (`codex-bootstrap-kit`)
- deterministic task artifact workflow (`codex-taskflow-kit`)

## Problem It Solves
Without a standard bootstrap/taskflow layer, teams usually hit the same issues:
- each session starts with missing or inconsistent context
- CLI/App/AGENTS flows drift apart and behave differently
- task execution quality depends on prompt style instead of enforced checks
- generated local artifacts are easy to leak into git history

## How It Solves It
1. Install unified kit artifacts into target repos.
2. Bootstrap local state snapshots and checklist status before work.
3. Auto-prime Codex sessions with a first prompt that loads `.local_codex/*` context files and taskflow routing rules.
4. Verify freshness/integrity gates (`status: PASS`) before session/taskflow.
5. Generate structured task artifacts (intake -> handoff).
6. Lint artifacts (`scaffold`/`complete` modes) to catch unfinished output.
7. Keep local generated files out of git with managed `.gitignore` blocks.

## Analogues And Tradeoffs
Common alternatives:
- ad-hoc `bootstrap.sh` + team runbooks
- scaffolding tools like Cookiecutter/Copier
- pre-commit-only policy enforcement
- standalone task templates/checklists

Why this repo is better for Codex-heavy workflows:
- one integrated path for CLI, App, and AGENTS/Skills (instead of separate scripts)
- built-in verify + lint gates, not just documentation conventions
- install safety controls (`--dry-run`, `--backup`, `--no-force`)
- CI-ready test bundle that exercises actual temp-repo flows

When it is not better:
- if you only need static project scaffolding once (no ongoing session/taskflow gating)
- if your team does not use Codex across multiple surfaces

## Bundled Kits
- `kits/codex-bootstrap-kit`
- `kits/codex-taskflow-kit`

## Runbooks
- `docs/NEW_REPO_WITH_PREINSTALLED_KITS.md`
- `docs/EXISTING_REPO_ADD_KITS.md`

## One-click installer (for existing repositories)
```bash
bash scripts/one_click_install.sh --target /absolute/path/to/target-repo
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
