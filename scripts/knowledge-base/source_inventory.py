#!/usr/bin/env python3
"""Build a deterministic inventory of repository-canonical knowledge sources.

This script intentionally reads only committed Git content. It does not write to
an Obsidian vault and has no third-party dependencies, so a Pi sync prompt or a
future read-only drift check can use the same source identity calculation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path


SPEC_MIRRORS = {
    "specs/backend_system_design.md": "50 Sources/Specifications/Backend System Design.md",
    "specs/game_design.md": "50 Sources/Specifications/Game Design.md",
    "specs/game_engine_spec.md": "50 Sources/Specifications/Game Engine Specification.md",
    "specs/glossary.md": "50 Sources/Specifications/Glossary Source.md",
}

ADR_MIRROR_TITLES = {
    "0001": "Bounded Contexts and Ledger Authority",
    "0002": "Persistence and Consistency",
    "0003": "API Edge SSE and Idempotency",
    "0004": "Identity and Auth",
    "0005": "System Triggers Scheduler and Feed",
    "0006": "Deployment and Observability",
    "0007": "Security Posture",
    "0008": "Package Layout",
    "0009": "Scaling Strategy",
    "0010": "Fixed-Point Money",
    "0011": "Typed Error Model",
    "0012": "Configuration Management",
}


def run_git(repo: Path, *args: str, check: bool = True) -> bytes:
    completed = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and completed.returncode != 0:
        detail = completed.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"git {' '.join(args)} failed: {detail}")
    return completed.stdout


def source_type(path: str) -> str:
    if path == "CONTEXT.md":
        return "context"
    if path == "specs/glossary.md":
        return "glossary"
    if path.startswith("specs/"):
        return "specification"
    return "adr"


def mirror_path(path: str) -> str | None:
    if path == "CONTEXT.md":
        # CONTEXT.md is a synchronization trigger/dependency, not a full mirror
        # in the initial vault design.
        return None
    if path in SPEC_MIRRORS:
        return SPEC_MIRRORS[path]
    if path.startswith("docs/adr/"):
        filename = Path(path).name
        number = filename[:4]
        title = ADR_MIRROR_TITLES.get(number)
        if title:
            return f"50 Sources/ADRs/ADR-{number} {title}.md"
    return None


def source_paths(repo: Path, revision: str) -> list[str]:
    raw = run_git(repo, "ls-tree", "-r", "--name-only", revision, "--", "CONTEXT.md", "specs", "docs/adr")
    paths = raw.decode("utf-8").splitlines()
    return sorted(
        path
        for path in paths
        if path == "CONTEXT.md"
        or (path.startswith("specs/") and path.endswith(".md"))
        or (path.startswith("docs/adr/") and path.endswith(".md"))
    )


def inventory(repo: Path, source_ref: str, require_clean: bool) -> dict[str, object]:
    repo = repo.resolve()
    if not (repo / ".git").exists():
        raise RuntimeError(f"not a Git repository: {repo}")

    revision = run_git(repo, "rev-parse", "--verify", f"{source_ref}^{{commit}}").decode().strip()
    if require_clean:
        dirty = run_git(repo, "status", "--porcelain", "--untracked-files=all").decode().splitlines()
        if dirty:
            raise RuntimeError("working tree is dirty; use a committed source ref or omit --require-clean")
    else:
        dirty = run_git(repo, "status", "--porcelain", "--untracked-files=all").decode().splitlines()

    records: list[dict[str, object]] = []
    for path in source_paths(repo, source_ref):
        content = run_git(repo, "show", f"{source_ref}:{path}")
        last_changed = run_git(repo, "log", source_ref, "-1", "--format=%H", "--", path).decode().strip()
        digest = hashlib.sha256(content).hexdigest()
        records.append(
            {
                "source_path": path,
                "source_type": source_type(path),
                "source_ref": source_ref,
                "source_revision": revision,
                "last_changed_revision": last_changed or revision,
                "source_hash": digest,
                "source_sha256": digest,
                "source_byte_count": len(content),
                "mirror_required": path != "CONTEXT.md",
                "expected_mirror_path": mirror_path(path),
            }
        )

    return {
        "repository": str(repo),
        "source_ref": source_ref,
        "source_revision": revision,
        "working_tree_dirty": bool(dirty),
        "sources": records,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path.cwd(), help="backend repository root")
    parser.add_argument("--source-ref", default="HEAD", help="committed Git ref to inspect")
    parser.add_argument("--require-clean", action="store_true", help="fail when the working tree is dirty")
    parser.add_argument("--pretty", action="store_true", help="indent JSON output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        result = inventory(args.repo, args.source_ref, args.require_clean)
    except (OSError, RuntimeError) as exc:
        print(f"source-inventory: error: {exc}", file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2 if args.pretty else None, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
