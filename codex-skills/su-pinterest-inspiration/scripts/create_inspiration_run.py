#!/usr/bin/env python3
"""Create a standardized run folder for SU Pinterest inspiration workflows."""

from __future__ import annotations

import argparse
import json
import re
import shutil
from datetime import datetime
from pathlib import Path


def slugify(value: str, fallback: str) -> str:
    value = value.strip().lower()
    value = re.sub(r"[^a-z0-9._-]+", "-", value)
    value = re.sub(r"-{2,}", "-", value).strip("-._")
    return value or fallback


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a timestamped folder and manifest for an SU Pinterest inspiration run."
    )
    parser.add_argument("--root", default="su-pinterest-runs", help="Root output directory.")
    parser.add_argument("--project", default="project", help="Project/client slug or name.")
    parser.add_argument("--view", default="view", help="SketchUp view or camera name.")
    parser.add_argument("--target-count", type=int, default=10, help="Target inspiration count.")
    parser.add_argument(
        "--source-screenshot",
        help="Optional existing white-model screenshot to copy into the input folder.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.target_count < 1:
        raise SystemExit("--target-count must be at least 1")

    root = Path(args.root).expanduser().resolve()
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    project_slug = slugify(args.project, "project")
    view_slug = slugify(args.view, "view")
    run_dir = root / f"{timestamp}-{project_slug}-{view_slug}"

    subdirs = ["input", "inspiration", "prompts", "outputs", "review"]
    for subdir in subdirs:
        (run_dir / subdir).mkdir(parents=True, exist_ok=False)

    copied_source = None
    if args.source_screenshot:
        source = Path(args.source_screenshot).expanduser().resolve()
        if not source.is_file():
            raise SystemExit(f"Source screenshot not found: {source}")
        destination = run_dir / "input" / f"white-model{source.suffix.lower() or '.png'}"
        shutil.copy2(source, destination)
        copied_source = str(destination)

    manifest = {
        "schema": "su-pinterest-inspiration-run-v1",
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "project": args.project,
        "view": args.view,
        "target_count": args.target_count,
        "status": "created",
        "source_screenshot": copied_source,
        "folders": {name: str(run_dir / name) for name in subdirs},
        "inspiration": [],
        "prompts": [],
        "outputs": [],
        "notes": [],
    }

    manifest_path = run_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(str(run_dir))
    print(str(manifest_path))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
