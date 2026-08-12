#!/usr/bin/env python3
"""Inventory a closed-issue workflow directory without writing to the vault.

The default output is metadata only. ``--include-content`` adds base64-encoded
artifact bytes for an Obsidian-side adapter; the resulting file belongs in the
ignored local ``.kb-sync`` state directory and must never be committed.
"""

from __future__ import annotations

import argparse
import base64
import datetime as dt
import hashlib
import json
import mimetypes
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def git(repo: Path, *args: str) -> str:
    result = subprocess.run(["git", "-C", str(repo), *args], check=True, text=True, stdout=subprocess.PIPE)
    return result.stdout.strip()


def artifact_type(path: Path) -> str:
    if path.suffix.lower() == ".md":
        return "text/markdown"
    if path.suffix.lower() == ".json":
        return "application/json"
    return mimetypes.guess_type(path.name)[0] or "application/octet-stream"


def inventory(repo: Path, issue: str, include_content: bool) -> dict[str, Any]:
    if not issue.isdigit() or int(issue) <= 0:
        raise ValueError("issue must be a positive integer")
    repo = repo.resolve()
    source_dir = repo / "docs" / "issue-workflows" / issue
    if not source_dir.is_dir():
        raise FileNotFoundError(f"workflow directory not found: {source_dir}")

    artifacts: list[dict[str, Any]] = []
    for path in sorted(source_dir.rglob("*")):
        if not path.is_file() or path.name == ".DS_Store":
            continue
        if path.is_symlink():
            raise ValueError(f"symlinked artifact is not supported: {path}")
        data = path.read_bytes()
        relative = path.relative_to(repo).as_posix()
        artifact: dict[str, Any] = {
            "source_path": relative,
            "relative_path": path.relative_to(source_dir).as_posix(),
            "source_byte_count": len(data),
            "source_hash": hashlib.sha256(data).hexdigest(),
            "media_type": artifact_type(path),
        }
        if include_content:
            artifact["content_encoding"] = "base64"
            artifact["content_base64"] = base64.b64encode(data).decode("ascii")
        artifacts.append(artifact)

    return {
        "schema": 1,
        "issue_number": int(issue),
        "source_directory": f"docs/issue-workflows/{issue}/",
        "source_revision": git(repo, "rev-parse", "HEAD"),
        "source_branch": git(repo, "branch", "--show-current"),
        "source_tree_dirty": bool(git(repo, "status", "--porcelain", "--untracked-files=all")),
        "generated_at": utc_now(),
        "content_included": include_content,
        "artifact_count": len(artifacts),
        "artifacts": artifacts,
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent, text=True)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2, sort_keys=True)
            stream.write("\n")
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd())
    parser.add_argument("--issue", required=True)
    parser.add_argument("--output", type=Path, help="write JSON to this local state path")
    parser.add_argument("--include-content", action="store_true", help="include base64 bytes for an Obsidian-side adapter")
    parser.add_argument("--pretty", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        payload = inventory(args.repo, args.issue, args.include_content)
        if args.output:
            write_json(args.output, payload)
            print(args.output)
        else:
            print(json.dumps(payload, indent=2 if args.pretty else None, sort_keys=True))
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"archive-inventory: error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
