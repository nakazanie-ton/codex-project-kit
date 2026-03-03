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

Installer behavior:
- installs both bundled kits (offline/local source, no git clone)
- rewrites `.codex_bootstrap/config.json` to project-agnostic defaults (no framework-specific entry points/routing)
- runs strict verification
