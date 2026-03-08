#!/usr/bin/env python3
"""
Prompt Cue UI token validator.

This script keeps false positives manageable by default:
- It validates only changed UI Swift files when git metadata is available.
- It skips known design-system files where raw values are expected to live.
- It supports local escape hatches for one-off cases:
  - `// promptcue-ui-token: ignore-file`
  - `// promptcue-ui-token: ignore-line`
  - `// promptcue-ui-token: ignore-next-line`

Run with `--all` to audit the entire UI layer.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
UI_ROOTS = (Path("PromptCue/UI"), Path("PromptCue/App"))
DESIGN_SYSTEM_ROOT = Path("PromptCue/UI/DesignSystem")
DESIGN_SYSTEM_ALLOWLIST = {Path("PromptCue/App/AppUIConstants.swift")}
IGNORE_FILE_MARKER = "promptcue-ui-token: ignore-file"
IGNORE_LINE_MARKER = "promptcue-ui-token: ignore-line"
IGNORE_NEXT_LINE_MARKER = "promptcue-ui-token: ignore-next-line"


@dataclass(frozen=True)
class Rule:
    name: str
    pattern: re.Pattern[str]
    message: str


RULES = (
    Rule(
        name="color-nscolor",
        pattern=re.compile(r"Color\s*\(\s*nsColor\s*:"),
        message="Use semantic color tokens instead of inline Color(nsColor: ...).",
    ),
    Rule(
        name="system-font",
        pattern=re.compile(r"\.font\(\s*\.system\s*\("),
        message="Use typography tokens instead of .font(.system(...)) in UI files.",
    ),
    Rule(
        name="corner-radius",
        pattern=re.compile(
            r"(?:cornerRadius\s*:\s*-?\d+(?:\.\d+)?|\.cornerRadius\(\s*-?\d+(?:\.\d+)?)"
        ),
        message="Use a radius token instead of a raw cornerRadius number.",
    ),
    Rule(
        name="inline-shadow",
        pattern=re.compile(r"\.shadow\s*\("),
        message="Use a design-system shadow token or helper instead of inline .shadow(...).",
    ),
    Rule(
        name="padding-magic-number",
        pattern=re.compile(
            r"\.padding\(\s*(?:\.[A-Za-z_]+\s*,\s*)?-?\d+(?:\.\d+)?\s*\)"
        ),
        message="Use spacing tokens instead of raw numeric padding in UI files.",
    ),
    Rule(
        name="frame-magic-number",
        pattern=re.compile(
            r"\.frame\([^)]*(?:width|minWidth|maxWidth|height|minHeight|maxHeight|minLength)\s*:\s*-?\d+(?:\.\d+)?"
        ),
        message="Use layout tokens/constants instead of raw numeric frame or minLength values in UI files.",
    ),
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate changed Prompt Cue UI Swift files for hardcoded design values."
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Scan all UI Swift files instead of only changed files.",
    )
    args = parser.parse_args()

    files = ui_files_to_scan(scan_all=args.all)
    if not files:
        if args.all:
            print("UI token validation skipped: no UI Swift files found.")
        elif (REPO_ROOT / ".git").exists():
            print("UI token validation skipped: no changed UI files found.")
        return 0

    violations: list[str] = []
    for path in files:
        violations.extend(validate_file(path))

    if violations:
        print("UI token validation failed.\n")
        print("\n".join(violations))
        return 1

    print(f"UI token validation passed for {len(files)} file(s).")
    return 0


def ui_files_to_scan(*, scan_all: bool) -> list[Path]:
    if scan_all:
        return all_ui_files()

    changed = changed_ui_files()
    if changed is None:
        print(
            "UI token validation skipped: git history is unavailable. "
            "Run with --all for a full local audit."
        )
        return []

    return changed


def all_ui_files() -> list[Path]:
    files: list[Path] = []
    for root in UI_ROOTS:
        absolute_root = REPO_ROOT / root
        if not absolute_root.exists():
            continue
        for path in absolute_root.rglob("*.swift"):
            relative = path.relative_to(REPO_ROOT)
            if is_scannable_ui_file(relative):
                files.append(relative)
    return sorted(files)


def changed_ui_files() -> list[Path] | None:
    if not (REPO_ROOT / ".git").exists():
        return None

    diff_range = git_diff_range()
    if diff_range is None:
        return None

    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMRTUXB", *diff_range],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None

    files = []
    for raw_path in result.stdout.splitlines():
        path = Path(raw_path.strip())
        if is_scannable_ui_file(path):
            files.append(path)
    return sorted(set(files))


def git_diff_range() -> list[str] | None:
    base_ref = os.environ.get("GITHUB_BASE_REF")
    if base_ref:
        return [f"origin/{base_ref}...HEAD"]

    before_sha = os.environ.get("GITHUB_EVENT_BEFORE")
    current_sha = os.environ.get("GITHUB_SHA", "HEAD")
    if before_sha and not set(before_sha) == {"0"}:
        return [before_sha, current_sha]

    parent_check = subprocess.run(
        ["git", "rev-parse", "--verify", "HEAD~1"],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    if parent_check.returncode == 0:
        return ["HEAD~1", "HEAD"]

    return None


def is_scannable_ui_file(path: Path) -> bool:
    if path.suffix != ".swift":
        return False
    if path in DESIGN_SYSTEM_ALLOWLIST:
        return False
    if path.is_relative_to(DESIGN_SYSTEM_ROOT):
        return False
    return any(path.is_relative_to(root) for root in UI_ROOTS)


def validate_file(path: Path) -> list[str]:
    text = (REPO_ROOT / path).read_text(encoding="utf-8")
    lines = text.splitlines()
    if any(IGNORE_FILE_MARKER in line for line in lines):
        return []

    violations: list[str] = []
    ignore_next_line = False
    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()

        if ignore_next_line:
            ignore_next_line = False
            continue
        if IGNORE_NEXT_LINE_MARKER in stripped:
            ignore_next_line = True
            continue
        if IGNORE_LINE_MARKER in stripped or stripped.startswith("//"):
            continue

        for rule in RULES:
            if rule.pattern.search(line):
                violations.append(
                    f"{path}:{line_number}: [{rule.name}] {rule.message}\n    {stripped}"
                )

    return violations


if __name__ == "__main__":
    sys.exit(main())
