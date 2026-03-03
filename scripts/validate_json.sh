#!/usr/bin/env bash
set -euo pipefail

JSON_FILE=""
FILE_SET=0
REQUIRED_FIELDS=()
TYPE_CHECKS=()

usage() {
  cat <<'USAGE'
Usage:
  bash scripts/validate_json.sh --file <path> [--required <field>]... [--type <field:string|array|object>]...

Examples:
  bash scripts/validate_json.sh --file .codex_bootstrap/config.json \
    --required project_name --required startup_read_order \
    --type project_name:string --type startup_read_order:array --type entry_points:object
USAGE
}

fail() {
  echo "[validate-json] ERROR: $1" >&2
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --file)
      if [[ "$FILE_SET" -eq 1 ]]; then
        fail "--file was provided more than once"
      fi
      shift || true
      [[ $# -gt 0 ]] || fail "--file requires a value"
      [[ "${1:-}" != --* ]] || fail "--file requires a path value"
      JSON_FILE="$1"
      FILE_SET=1
      ;;
    --required)
      shift || true
      [[ $# -gt 0 ]] || fail "--required requires a value"
      [[ "${1:-}" != --* ]] || fail "--required requires a field name"
      REQUIRED_FIELDS+=("$1")
      ;;
    --type)
      shift || true
      [[ $# -gt 0 ]] || fail "--type requires a value"
      [[ "${1:-}" != --* ]] || fail "--type requires a <field:type> value"
      TYPE_CHECKS+=("$1")
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
  shift || true
done

[[ "$FILE_SET" -eq 1 ]] || fail "--file is required"
[[ -f "$JSON_FILE" ]] || fail "JSON file not found: $JSON_FILE"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"

PY_ARGS=()
for field in "${REQUIRED_FIELDS[@]}"; do
  PY_ARGS+=("--required=$field")
done
for type_check in "${TYPE_CHECKS[@]}"; do
  PY_ARGS+=("--type=$type_check")
done

python3 - "$JSON_FILE" "${PY_ARGS[@]}" <<'PY'
import argparse
import json
import sys
from pathlib import Path


VALID_TYPES = {"string": str, "array": list, "object": dict}


def py_type_name(value: object) -> str:
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    return type(value).__name__


def fail(message: str) -> None:
    print(f"[validate-json] ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def main() -> None:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("json_file")
    parser.add_argument("--required", action="append", default=[])
    parser.add_argument("--type", dest="type_checks", action="append", default=[])
    args = parser.parse_args()

    path = Path(args.json_file)

    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc.msg} (line {exc.lineno}, column {exc.colno})")
    except OSError as exc:
        fail(f"failed to read {path}: {exc}")

    if not isinstance(data, dict):
        fail("root JSON value must be an object")

    for field in args.required:
        if field not in data:
            fail(f"missing required field: '{field}'")

    for spec in args.type_checks:
        field, sep, expected_type = spec.partition(":")
        if not sep or not field or not expected_type:
            fail(f"invalid --type value: '{spec}' (expected <field:string|array|object>)")
        if expected_type not in VALID_TYPES:
            fail(f"unsupported type '{expected_type}' in --type '{spec}'")
        if field not in data:
            fail(f"type check failed: field '{field}' is missing")
        if not isinstance(data[field], VALID_TYPES[expected_type]):
            fail(
                "type check failed for field "
                f"'{field}': expected {expected_type}, got {py_type_name(data[field])}"
            )

    print(f"[validate-json] OK: {path}")


if __name__ == "__main__":
    main()
PY
