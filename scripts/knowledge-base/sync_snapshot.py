#!/usr/bin/env python3
"""Persist and retrieve compact local state for knowledge-base sync runs.

Snapshots are deliberately local, ignored state. They contain source metadata and
path classifications, never source bodies or credentials. They let later workflow
modes consume an exact check/plan result without rebuilding context.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
import tempfile
from pathlib import Path
from typing import Any


ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,80}$")
KINDS = {"check", "plan"}
FORBIDDEN_KEYS = {"content", "content_base64", "body", "artifact_body", "source_text"}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def validate_identifier(value: str) -> str:
    if not ID_RE.fullmatch(value):
        raise ValueError(f"invalid snapshot id: {value!r}")
    return value


def reject_content(value: Any, location: str = "payload") -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key.lower() in FORBIDDEN_KEYS:
                raise ValueError(f"{location}.{key} would persist source content; snapshots are metadata-only")
            reject_content(child, f"{location}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            reject_content(child, f"{location}[{index}]")


def validate_payload(payload: dict[str, Any], kind: str, snapshot_id: str) -> dict[str, Any]:
    reject_content(payload)
    required = {"source_ref", "source_revision", "sources"}
    missing = sorted(required - payload.keys())
    if missing:
        raise ValueError(f"payload is missing required fields: {', '.join(missing)}")
    if not isinstance(payload["sources"], list):
        raise ValueError("payload.sources must be a list")
    for index, source in enumerate(payload["sources"]):
        if not isinstance(source, dict):
            raise ValueError(f"payload.sources[{index}] must be an object")
        for field in ("source_path", "source_hash"):
            if not source.get(field):
                raise ValueError(f"payload.sources[{index}] is missing {field}")
    return {
        "schema": 1,
        "kind": kind,
        "snapshot_id": snapshot_id,
        "created_at": payload.get("created_at", utc_now()),
        "saved_at": utc_now(),
        **payload,
    }


def snapshot_path(state_dir: Path, kind: str, snapshot_id: str) -> Path:
    validate_identifier(snapshot_id)
    if kind not in KINDS:
        raise ValueError(f"kind must be one of: {', '.join(sorted(KINDS))}")
    return state_dir / f"{kind}-{snapshot_id}.json"


def write_snapshot(state_dir: Path, kind: str, snapshot_id: str, input_path: str) -> Path:
    if input_path == "-":
        payload = json.load(sys.stdin)
    else:
        payload = json.loads(Path(input_path).read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError("snapshot input must be a JSON object")
    result = validate_payload(payload, kind, snapshot_id)
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    target = snapshot_path(state_dir, kind, snapshot_id)
    fd, temporary = tempfile.mkstemp(prefix=f".{target.name}.", dir=state_dir, text=True)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(result, stream, indent=2, sort_keys=True)
            stream.write("\n")
        os.replace(temporary, target)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise
    return target


def read_snapshot(state_dir: Path, kind: str, snapshot_id: str) -> dict[str, Any]:
    target = snapshot_path(state_dir, kind, snapshot_id)
    if not target.is_file():
        raise FileNotFoundError(f"snapshot not found: {target}")
    payload = json.loads(target.read_text(encoding="utf-8"))
    if payload.get("schema") != 1 or payload.get("kind") != kind or payload.get("snapshot_id") != snapshot_id:
        raise ValueError(f"invalid snapshot metadata: {target}")
    reject_content(payload)
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    write = subparsers.add_parser("write", help="write a metadata-only snapshot")
    write.add_argument("--kind", choices=sorted(KINDS), required=True)
    write.add_argument("--id", dest="snapshot_id", required=True)
    write.add_argument("--input", default="-", help="JSON input file, or - for stdin")
    write.add_argument("--state-dir", type=Path, default=Path(".kb-sync"))

    read = subparsers.add_parser("read", help="read and validate a snapshot")
    read.add_argument("--kind", choices=sorted(KINDS), required=True)
    read.add_argument("--id", dest="snapshot_id", required=True)
    read.add_argument("--state-dir", type=Path, default=Path(".kb-sync"))

    listing = subparsers.add_parser("list", help="list available snapshots")
    listing.add_argument("--state-dir", type=Path, default=Path(".kb-sync"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if args.command == "write":
            print(write_snapshot(args.state_dir, args.kind, args.snapshot_id, args.input))
        elif args.command == "read":
            print(json.dumps(read_snapshot(args.state_dir, args.kind, args.snapshot_id), indent=2, sort_keys=True))
        else:
            if not args.state_dir.is_dir():
                return 0
            paths = sorted(path.name for path in args.state_dir.glob("*.json") if path.is_file())
            print("\n".join(paths))
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"sync-snapshot: error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
