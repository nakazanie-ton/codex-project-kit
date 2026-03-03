#!/usr/bin/env python3
"""Universal taskflow artifact generator (stack-agnostic)."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def now_utc() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def now_stamp() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y%m%d-%H%M%S")


def slugify(text: str) -> str:
    ascii_text = text.lower().encode("ascii", "ignore").decode("ascii")
    ascii_text = re.sub(r"[^a-z0-9]+", "-", ascii_text).strip("-")
    return ascii_text[:48] or "task"


def read_task_text(args: argparse.Namespace) -> str:
    if args.text:
        return args.text.strip()
    if args.file:
        return Path(args.file).read_text(encoding="utf-8").strip()
    if not sys.stdin.isatty():
        return sys.stdin.read().strip()
    return ""


def load_config(config_path: Path) -> dict[str, Any]:
    if not config_path.exists():
        raise SystemExit(f"Config not found: {config_path}")
    try:
        return json.loads(config_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Invalid JSON config {config_path}: {exc}") from exc


def checklist_status(root: Path) -> str:
    checklist = root / ".local_codex" / "CODEX_LOCAL_CHECKLIST.md"
    if not checklist.exists():
        return "UNKNOWN"
    text = checklist.read_text(encoding="utf-8")
    match = re.search(r"status:\s*([A-Z]+)", text)
    return match.group(1).strip() if match else "UNKNOWN"


def render_template(template_path: Path, data: dict[str, str]) -> str:
    template = template_path.read_text(encoding="utf-8")
    out = template
    for key, value in data.items():
        out = out.replace("{{" + key + "}}", value)
    return out


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content.rstrip() + "\n", encoding="utf-8")


def resolve_title(args: argparse.Namespace, task_text: str) -> str:
    if args.title.strip():
        return args.title.strip()
    if task_text:
        return task_text.splitlines()[0].strip()
    return "Untitled Task"


def resolve_output_base(root: Path, out_dir_arg: str, out_dir_rel: str) -> Path:
    if out_dir_arg:
        return Path(out_dir_arg).resolve()
    return root / out_dir_rel


def build_template_data(
    workflow_name: str,
    version: str,
    task_id: str,
    created_at: str,
    title: str,
    task_text: str,
    bootstrap_state: str,
) -> dict[str, str]:
    return {
        "WORKFLOW_NAME": workflow_name,
        "WORKFLOW_VERSION": version,
        "TASK_ID": task_id,
        "CREATED_AT": created_at,
        "TASK_TITLE": title,
        "TASK_TEXT": task_text or "TODO: add task details",
        "BOOTSTRAP_STATUS": bootstrap_state,
    }


def generate_artifacts(
    template_dir: Path,
    task_dir: Path,
    artifacts: dict[str, str],
    template_data: dict[str, str],
) -> dict[str, str]:
    artifact_paths: dict[str, str] = {}
    template_files = {
        "intake": "intake.md",
        "scope": "scope.md",
        "plan": "plan.md",
        "execute": "execution_log.md",
        "verify": "verification.md",
        "handoff": "handoff.md",
    }

    for key, output_name in artifacts.items():
        template_name = template_files.get(key)
        if not template_name:
            continue
        src_template = template_dir / template_name
        if not src_template.exists():
            raise SystemExit(f"Template not found: {src_template}")
        dst = task_dir / output_name
        content = render_template(src_template, template_data)
        write_text(dst, content)
        artifact_paths[key] = str(dst)

    return artifact_paths


def build_taskflow_json(
    workflow_name: str,
    version: str,
    task_id: str,
    created_at: str,
    title: str,
    task_text: str,
    bootstrap_state: str,
    root: Path,
    task_dir: Path,
    steps: list[dict[str, Any]],
    artifact_paths: dict[str, str],
) -> dict[str, Any]:
    return {
        "workflow_name": workflow_name,
        "workflow_version": version,
        "task_id": task_id,
        "created_at": created_at,
        "task_title": title,
        "task_text": task_text,
        "bootstrap_status": bootstrap_state,
        "root": str(root),
        "task_dir": str(task_dir),
        "steps": steps,
        "artifacts": artifact_paths,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate universal taskflow artifacts")
    parser.add_argument("--root", required=True, help="Repository root")
    parser.add_argument("--title", default="", help="Short task title")
    parser.add_argument("--text", default="", help="Task description text")
    parser.add_argument("--file", default="", help="Read task description from file")
    parser.add_argument("--out-dir", default="", help="Override output directory")
    parser.add_argument(
        "--json-path-only",
        action="store_true",
        help="Print only taskflow.json absolute path",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    task_text = read_task_text(args)

    config_path = root / ".codex_taskflow" / "config.json"
    config = load_config(config_path)

    workflow_name = str(config.get("workflow_name", "codex-universal-taskflow"))
    version = str(config.get("version", "1.0.0"))
    out_dir_rel = str(config.get("out_dir", "work/taskflow"))

    title = resolve_title(args, task_text)
    task_id = f"{now_stamp()}-{slugify(title)}"

    out_base = resolve_output_base(root, args.out_dir, out_dir_rel)
    task_dir = out_base / task_id
    task_dir.mkdir(parents=True, exist_ok=True)

    steps = config.get("steps", [])
    artifacts = config.get("artifacts", {})

    created_at = now_utc()
    bootstrap_state = checklist_status(root)

    template_data = build_template_data(
        workflow_name=workflow_name,
        version=version,
        task_id=task_id,
        created_at=created_at,
        title=title,
        task_text=task_text,
        bootstrap_state=bootstrap_state,
    )
    template_dir = root / ".codex_taskflow" / "templates"

    artifact_paths = generate_artifacts(
        template_dir=template_dir,
        task_dir=task_dir,
        artifacts=artifacts,
        template_data=template_data,
    )

    taskflow_json = build_taskflow_json(
        workflow_name=workflow_name,
        version=version,
        task_id=task_id,
        created_at=created_at,
        title=title,
        task_text=task_text,
        bootstrap_state=bootstrap_state,
        root=root,
        task_dir=task_dir,
        steps=steps,
        artifact_paths=artifact_paths,
    )

    json_path = task_dir / "taskflow.json"
    write_text(json_path, json.dumps(taskflow_json, ensure_ascii=True, indent=2))

    if args.json_path_only:
        print(str(json_path))
        return

    print(f"Taskflow created: {task_id}")
    print(f"Directory: {task_dir}")
    print(f"Bootstrap status: {bootstrap_state}")
    print("Artifacts:")
    for key in ("intake", "scope", "plan", "execute", "verify", "handoff"):
        if key in artifact_paths:
            print(f"- {key}: {artifact_paths[key]}")
    print(f"- metadata: {json_path}")


if __name__ == "__main__":
    main()
