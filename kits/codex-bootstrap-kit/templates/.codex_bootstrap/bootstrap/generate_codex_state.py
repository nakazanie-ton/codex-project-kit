#!/usr/bin/env python3
"""Generate Codex local state snapshots for any repository."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_REQUIRED_FILES = [
    ".local_codex/AGENT_STATE.md",
    ".local_codex/PROJECT_AGENT_STATE.json",
    ".local_codex/PROJECT_TREE.txt",
    ".local_codex/PROJECT_NAVIGATION.md",
    ".local_codex/PROJECT_DEPENDENCY_GRAPH.md",
]

DEFAULT_STARTUP_ORDER = [
    "scripts/codex_bootstrap.sh",
    ".local_codex/CODEX_LOCAL_CHECKLIST.md",
    "AGENTS.md",
    ".local_codex/PROJECT_AGENT_STATE.json",
    ".local_codex/PROJECT_NAVIGATION.md",
    ".local_codex/PROJECT_DEPENDENCY_GRAPH.md",
    ".local_codex/PROJECT_TREE.txt",
]

DEFAULT_EXCLUDE_PATHS = {
    ".git",
    ".hg",
    ".svn",
    "node_modules",
    ".pnpm-store",
    ".yarn",
    ".turbo",
    ".parcel-cache",
    ".venv",
    "venv",
    "env",
    ".direnv",
    ".tox",
    ".nox",
    "__pypackages__",
    ".eggs",
    ".ipynb_checkpoints",
    ".next",
    ".nuxt",
    ".svelte-kit",
    ".terraform",
    ".terragrunt-cache",
    ".serverless",
    ".aws-sam",
    ".idea",
    ".vscode",
    ".gradle",
    ".dart_tool",
    ".cache",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    "dist",
    "build",
    "out",
    "target",
    "coverage",
}

API_DECORATOR_PATTERN = re.compile(r"@router\.(get|post|put|delete|patch)\(")
TEST_FILE_PATTERN = re.compile(r"(^|/)test_[^/]+\.py$|\.test\.(ts|tsx|js)$")


@dataclass
class BootstrapConfig:
    project_name: str
    required_skills: list[str]
    startup_read_order: list[str]
    required_files: list[str]
    exclude_paths: set[str]
    entry_points: dict[str, str]
    task_routing: dict[str, list[str]]


def now_utc() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def normalize_rel_path(path: str) -> str:
    normalized = path.strip().replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized.strip("/")


def build_exclude_matchers(exclude_paths: set[str]) -> tuple[set[str], set[str]]:
    exact_paths: set[str] = set()
    dir_names: set[str] = set()
    for item in exclude_paths:
        normalized = normalize_rel_path(item)
        if not normalized:
            continue
        exact_paths.add(normalized)
        if "/" not in normalized:
            dir_names.add(normalized)
    return exact_paths, dir_names


def is_path_excluded(
    rel_path: str,
    exclude_exact_paths: set[str],
    exclude_dir_names: set[str],
) -> bool:
    normalized = normalize_rel_path(rel_path)
    if not normalized:
        return False

    parts = normalized.split("/")
    if "__pycache__" in parts:
        return True
    if any(part in exclude_dir_names for part in parts):
        return True

    return any(
        normalized == excluded or normalized.startswith(f"{excluded}/")
        for excluded in exclude_exact_paths
    )


def add_file_with_parents(entries: set[str], rel_file: str) -> None:
    normalized = normalize_rel_path(rel_file)
    if not normalized:
        return

    parts = normalized.split("/")
    for depth in range(1, len(parts)):
        entries.add(f"./{'/'.join(parts[:depth])}")
    entries.add(f"./{normalized}")


def build_tree_snapshot_from_git(
    root: Path,
    exclude_exact_paths: set[str],
    exclude_dir_names: set[str],
) -> list[str] | None:
    if not (root / ".git").exists():
        return None

    try:
        probe = subprocess.run(
            ["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"],
            check=True,
            capture_output=True,
            text=True,
        )
        if probe.stdout.strip() != "true":
            return None

        listed = subprocess.run(
            ["git", "-C", str(root), "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
            check=True,
            capture_output=True,
        )
    except (OSError, subprocess.CalledProcessError):
        return None

    entries: set[str] = {"."}
    for raw in listed.stdout.split(b"\0"):
        if not raw:
            continue
        rel_file = normalize_rel_path(raw.decode("utf-8", errors="surrogateescape"))
        if is_path_excluded(rel_file, exclude_exact_paths=exclude_exact_paths, exclude_dir_names=exclude_dir_names):
            continue
        add_file_with_parents(entries, rel_file)

    return sorted(entries)


def require_list_of_strings(value: Any, field: str) -> list[str]:
    if not isinstance(value, list):
        raise SystemExit(f"Invalid config: '{field}' must be a list of strings")

    result: list[str] = []
    for idx, item in enumerate(value):
        if not isinstance(item, str):
            raise SystemExit(f"Invalid config: '{field}[{idx}]' must be a string")
        stripped = item.strip()
        if stripped:
            result.append(stripped)
    return result


def require_dict_of_strings(value: Any, field: str) -> dict[str, str]:
    if not isinstance(value, dict):
        raise SystemExit(f"Invalid config: '{field}' must be an object with string values")

    result: dict[str, str] = {}
    for key, item in value.items():
        if not isinstance(item, str):
            raise SystemExit(f"Invalid config: '{field}.{key}' must be a string")
        stripped = item.strip()
        if stripped:
            result[str(key)] = stripped
    return result


def require_task_routing(value: Any, field: str) -> dict[str, list[str]]:
    if not isinstance(value, dict):
        raise SystemExit(f"Invalid config: '{field}' must be an object of string arrays")

    result: dict[str, list[str]] = {}
    for key, items in value.items():
        result[str(key)] = require_list_of_strings(items, f"{field}.{key}")
    return result


def load_config(root: Path, config_path: Path) -> BootstrapConfig:
    raw: dict[str, Any] = {}
    if config_path.exists():
        try:
            raw = json.loads(config_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise SystemExit(f"Invalid JSON in {config_path}: {exc}") from exc

    project_name = str(raw.get("project_name") or root.name)

    required_skills = require_list_of_strings(raw.get("required_skills", []), "required_skills")

    startup_read_order = require_list_of_strings(
        raw.get("startup_read_order", DEFAULT_STARTUP_ORDER),
        "startup_read_order",
    )
    if not startup_read_order:
        startup_read_order = DEFAULT_STARTUP_ORDER.copy()

    required_files = require_list_of_strings(raw.get("required_files", DEFAULT_REQUIRED_FILES), "required_files")
    if not required_files:
        required_files = DEFAULT_REQUIRED_FILES.copy()

    exclude_paths_raw = require_list_of_strings(raw.get("exclude_paths", []), "exclude_paths")
    exclude_paths = set(DEFAULT_EXCLUDE_PATHS)
    exclude_paths.update(normalize_rel_path(str(x)) for x in exclude_paths_raw)

    entry_points = require_dict_of_strings(raw.get("entry_points", {}), "entry_points")
    task_routing = require_task_routing(raw.get("task_routing", {}), "task_routing")

    return BootstrapConfig(
        project_name=project_name,
        required_skills=required_skills,
        startup_read_order=startup_read_order,
        required_files=required_files,
        exclude_paths=exclude_paths,
        entry_points=entry_points,
        task_routing=task_routing,
    )


def build_tree_snapshot(root: Path, exclude_paths: set[str]) -> list[str]:
    exclude_exact_paths, exclude_dir_names = build_exclude_matchers(exclude_paths)

    git_entries = build_tree_snapshot_from_git(
        root,
        exclude_exact_paths=exclude_exact_paths,
        exclude_dir_names=exclude_dir_names,
    )
    if git_entries is not None:
        return git_entries

    entries: set[str] = {"."}
    for current, dirs, files in os.walk(root):
        current_path = Path(current)
        rel_dir = "." if current_path == root else current_path.relative_to(root).as_posix()

        kept_dirs: list[str] = []
        for dir_name in dirs:
            rel_dir_path = normalize_rel_path(f"{rel_dir}/{dir_name}" if rel_dir != "." else dir_name)
            if is_path_excluded(
                rel_dir_path,
                exclude_exact_paths=exclude_exact_paths,
                exclude_dir_names=exclude_dir_names,
            ):
                continue
            kept_dirs.append(dir_name)
        dirs[:] = kept_dirs

        for file_name in files:
            rel_file = normalize_rel_path(f"{rel_dir}/{file_name}" if rel_dir != "." else file_name)
            if is_path_excluded(rel_file, exclude_exact_paths=exclude_exact_paths, exclude_dir_names=exclude_dir_names):
                continue
            add_file_with_parents(entries, rel_file)

    return sorted(entries)


def count_matching(entries: list[str], predicate) -> int:
    return sum(1 for item in entries if predicate(item))


def get_top_level_counts(entries: list[str]) -> Counter[str]:
    counter: Counter[str] = Counter()
    for item in entries:
        if item == ".":
            continue
        stripped = item[2:] if item.startswith("./") else item
        if not stripped:
            continue
        top = stripped.split("/", 1)[0]
        counter[top] += 1
    return counter


def safe_count(root: Path, rel_dir: str, pattern: str) -> int:
    base = root / rel_dir
    if not base.exists():
        return 0
    return sum(1 for _ in base.rglob(pattern))


def count_api_decorators(root: Path) -> int:
    api_dir = root / "app" / "api"
    if not api_dir.exists():
        return 0

    total = 0
    for py_file in api_dir.rglob("*.py"):
        try:
            text = py_file.read_text(encoding="utf-8")
        except OSError:
            continue
        total += len(API_DECORATOR_PATTERN.findall(text))
    return total


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def ensure_agent_state(path: Path, project_name: str, root: Path) -> None:
    if path.exists():
        content = path.read_text(encoding="utf-8")
        replaced = (
            content.replace("{{PROJECT_NAME}}", project_name)
            .replace("{{PROJECT_ROOT}}", str(root))
        )
        if replaced != content:
            path.write_text(replaced, encoding="utf-8")
        return

    content = f"""# Codex Agent State

## Scope
- Project: {project_name}
- Root: {root}
- Context: local Codex development only

## Startup Bootstrap
Run once at session start:
`bash scripts/codex_bootstrap.sh`

Session entrypoint:
`bash scripts/codex_session.sh`

## Where To Read First
1) AGENTS.md (if present)
2) .local_codex/PROJECT_AGENT_STATE.json
3) .local_codex/PROJECT_NAVIGATION.md
4) .local_codex/PROJECT_DEPENDENCY_GRAPH.md
5) .local_codex/PROJECT_TREE.txt
"""
    write_text(path, content)


def render_navigation_md(
    generated_at: str,
    total_paths: int,
    python_files: int,
    ts_files: int,
    sql_files: int,
    test_files: int,
    top_levels: Counter[str],
    startup_read_order: list[str],
    entry_points: dict[str, str],
    task_routing: dict[str, list[str]],
) -> str:
    lines: list[str] = [
        "# Project Navigation Guide",
        "",
        f"- generated_at: {generated_at}",
        "- source_tree: .local_codex/PROJECT_TREE.txt",
        f"- indexed_paths: {total_paths}",
        f"- python_files: {python_files}",
        f"- ts_tsx_files: {ts_files}",
        f"- sql_files: {sql_files}",
        f"- test_files: {test_files}",
        "",
        "## Purpose",
        "This file is the fast orientation map for Codex agents in this repository.",
        "Goal: route each task directly to the minimal set of files.",
        "",
        "## Mandatory Startup Read Order",
    ]

    for index, item in enumerate(startup_read_order, start=1):
        lines.append(f"{index}. {item}")

    lines.extend(["", "## Top-level Path Density"])
    for top in sorted(top_levels):
        lines.append(f"- `{top}`: {top_levels[top]} path(s)")

    lines.extend(["", "## Architecture Quick Map"])
    if entry_points:
        for key in sorted(entry_points):
            lines.append(f"- {key.replace('_', ' ')}: `{entry_points[key]}`")
    else:
        lines.append("- No entry points configured.")

    lines.extend(["", "## Configured Task Routing (Task -> Files)"])
    if task_routing:
        for route in sorted(task_routing):
            lines.append(f"### `{route}`")
            files = task_routing[route]
            if files:
                lines.extend(f"- `{file_path}`" for file_path in files)
            else:
                lines.append("- none")
            lines.append("")
    else:
        lines.append("- No task routing configured.")

    return "\n".join(lines)


def render_dependency_md(
    generated_at: str,
    api_endpoint_count: int,
    task_module_count: int,
    frontend_route_count: int,
    crud_module_count: int,
    entry_points: dict[str, str],
    task_routing: dict[str, list[str]],
) -> str:
    lines: list[str] = [
        "# Project Dependency Graph",
        "",
        f"- generated_at: {generated_at}",
        f"- detected_http_route_decorators: {api_endpoint_count}",
        f"- detected_task_modules: {task_module_count}",
        f"- detected_frontend_pages: {frontend_route_count}",
        f"- detected_crud_modules: {crud_module_count}",
        "",
        "## Purpose",
        "Use this map when task scope spans multiple layers (frontend -> API -> service -> CRUD -> model).",
        "",
        "## Runtime Entry Graph",
    ]

    browser_entry = entry_points.get("frontend_home")
    frontend_api = entry_points.get("frontend_api")
    backend_router = entry_points.get("backend_router")
    backend_entry = entry_points.get("backend_entry")
    worker_entry = entry_points.get("worker_entry")

    runtime_rows_added = 0
    if browser_entry and frontend_api and backend_router:
        lines.append(f"- Browser -> `{browser_entry}` -> `{frontend_api}` -> backend routes from `{backend_router}`")
        runtime_rows_added += 1
    if backend_entry and backend_router:
        lines.append(f"- Backend runtime -> `{backend_entry}` -> router aggregation `{backend_router}`")
        runtime_rows_added += 1
    if worker_entry:
        lines.append(f"- Background workloads -> `{worker_entry}`")
        runtime_rows_added += 1
    if runtime_rows_added == 0:
        lines.append("- No runtime entries configured.")

    lines.extend(["", "## Configured Task Impact Map"])
    if task_routing:
        for route in sorted(task_routing):
            files = task_routing[route]
            rendered = ", ".join(f"`{item}`" for item in files) if files else "`none`"
            lines.append(f"- `{route}` -> {rendered}")
    else:
        lines.append("- No task routing configured.")

    return "\n".join(lines)


def build_state_json(
    generated_at: str,
    root: Path,
    config: BootstrapConfig,
) -> dict[str, Any]:
    return {
        "generated_at": generated_at,
        "context": "local_codex_development_only",
        "project_root": str(root),
        "project_name": config.project_name,
        "goal": "Codex memory bootstrap and structure persistence",
        "state_files": [
            ".local_codex/AGENT_STATE.md",
            ".local_codex/SESSION_PRIMER.md",
            ".local_codex/PROJECT_AGENT_STATE.json",
            ".local_codex/PROJECT_TREE.txt",
            ".local_codex/PROJECT_NAVIGATION.md",
            ".local_codex/PROJECT_DEPENDENCY_GRAPH.md",
            ".local_codex/CODEX_LOCAL_CHECKLIST.md",
            "scripts/codex_bootstrap.sh",
            "scripts/codex_session.sh",
            ".codex_bootstrap/config.json",
        ],
        "entry_points": config.entry_points,
        "navigation": {
            "guide_file": ".local_codex/PROJECT_NAVIGATION.md",
            "startup_read_order": config.startup_read_order,
            "task_routing": config.task_routing,
        },
        "required_skills": config.required_skills,
        "tooling": {
            "bootstrap_mode": "strict_default",
            "bootstrap_strict_env": "CODEX_BOOTSTRAP_REQUIRED=1",
            "session_command_env": "CODEX_SESSION_SH (preferred), CODEX_SESSION_CMD",
        },
    }


def render_checklist(
    generated_at: str,
    root: Path,
    required_files: list[str],
) -> tuple[str, bool]:
    checks: list[tuple[str, bool]] = []
    for rel in required_files:
        checks.append((rel, (root / rel).exists()))

    status_ok = all(ok for _, ok in checks)

    lines = [
        "# Codex Local Checklist",
        "",
        f"- bootstrap_at: {generated_at}",
        f"- repo: {root}",
        f"- state_files: {sum(1 for _, ok in checks if ok)}/{len(checks)} present",
        f"- tree_snapshot: {root / '.local_codex/PROJECT_TREE.txt'}",
        f"- navigation_snapshot: {root / '.local_codex/PROJECT_NAVIGATION.md'}",
        f"- dependency_snapshot: {root / '.local_codex/PROJECT_DEPENDENCY_GRAPH.md'}",
        "",
        "## Check items",
    ]

    for rel, ok in checks:
        mark = "x" if ok else " "
        lines.append(f"- [{mark}] {rel}")

    lines.extend(["", "## Health", f"- status: {'PASS' if status_ok else 'FAIL'}"])
    return "\n".join(lines), status_ok


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Codex local state files")
    parser.add_argument("--root", required=True, help="Repository root")
    parser.add_argument("--config", required=True, help="Path to .codex_bootstrap/config.json")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    config_path = Path(args.config).resolve()
    state_dir = root / ".local_codex"
    state_dir.mkdir(parents=True, exist_ok=True)

    config = load_config(root, config_path)
    generated_at = now_utc()

    ensure_agent_state(state_dir / "AGENT_STATE.md", project_name=config.project_name, root=root)

    tree_entries = build_tree_snapshot(root, exclude_paths=config.exclude_paths)
    write_text(state_dir / "PROJECT_TREE.txt", "\n".join(tree_entries))

    total_paths = len(tree_entries)
    python_files = count_matching(tree_entries, lambda item: item.endswith(".py"))
    ts_files = count_matching(tree_entries, lambda item: item.endswith(".ts") or item.endswith(".tsx"))
    sql_files = count_matching(tree_entries, lambda item: item.endswith(".sql"))
    test_files = count_matching(
        tree_entries,
        lambda item: bool(TEST_FILE_PATTERN.search(item[2:] if item.startswith("./") else item)),
    )
    top_levels = get_top_level_counts(tree_entries)

    api_endpoint_count = count_api_decorators(root)
    task_module_count = safe_count(root, "app/tasks", "*.py")
    frontend_route_count = safe_count(root, "frontend/app", "page.tsx")
    crud_module_count = safe_count(root, "app/crud", "*.py")

    navigation_md = render_navigation_md(
        generated_at=generated_at,
        total_paths=total_paths,
        python_files=python_files,
        ts_files=ts_files,
        sql_files=sql_files,
        test_files=test_files,
        top_levels=top_levels,
        startup_read_order=config.startup_read_order,
        entry_points=config.entry_points,
        task_routing=config.task_routing,
    )
    write_text(state_dir / "PROJECT_NAVIGATION.md", navigation_md)

    dependency_md = render_dependency_md(
        generated_at=generated_at,
        api_endpoint_count=api_endpoint_count,
        task_module_count=task_module_count,
        frontend_route_count=frontend_route_count,
        crud_module_count=crud_module_count,
        entry_points=config.entry_points,
        task_routing=config.task_routing,
    )
    write_text(state_dir / "PROJECT_DEPENDENCY_GRAPH.md", dependency_md)

    state_json = build_state_json(generated_at=generated_at, root=root, config=config)
    write_text(
        state_dir / "PROJECT_AGENT_STATE.json",
        json.dumps(state_json, ensure_ascii=True, indent=2),
    )

    checklist_md, _ = render_checklist(
        generated_at=generated_at,
        root=root,
        required_files=config.required_files,
    )
    write_text(state_dir / "CODEX_LOCAL_CHECKLIST.md", checklist_md)


if __name__ == "__main__":
    main()
