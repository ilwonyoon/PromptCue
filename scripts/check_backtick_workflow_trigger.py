#!/usr/bin/env python3
"""
Verify whether a natural-language Backtick execution request actually routes
through Backtick workflow guidance.

This harness runs two probes against a chosen BacktickMCP helper:

1. Direct helper probe:
   - initialize
   - prompts/get(name=workflow)
   - tools/call(name=backtick_workflow)
   Confirms prompt telemetry is observable and the portable workflow tool is callable.

2. Codex CLI probe:
   - runs `codex exec` with a natural-language request
   - inspects the resulting activity delta
   Confirms whether the client actually chose workflow guidance or stayed on a
   generic tool-first path.

The script does not patch product behavior. It only produces evidence.
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any


DEFAULT_PROMPT = (
    "백틱 노트 불러와서 실행해줘. 다만 실제 코드 수정이나 저장은 하지 말고, "
    "어떤 Backtick workflow를 탔는지와 무엇을 읽었는지만 짧게 보고해."
)


def load_activity_state(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"schemaVersion": 1, "activities": []}
    return json.loads(path.read_text())


def matching_entries(
    state: dict[str, Any],
    *,
    helper_path: str,
    recorded_after: str,
) -> list[dict[str, Any]]:
    activities = state.get("activities", [])
    return [
        activity
        for activity in activities
        if activity.get("launchCommand") == helper_path
        and activity.get("recordedAt", "") >= recorded_after
    ]


def run_direct_prompt_probe(helper_path: str, connector_client: str) -> subprocess.CompletedProcess[str]:
    requests = [
        {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": {
                "protocolVersion": "2025-03-26",
                "clientInfo": {"name": "workflow-harness", "version": "1.0"},
            },
        },
        {
            "jsonrpc": "2.0",
            "id": 2,
            "method": "prompts/get",
            "params": {"name": "workflow"},
        },
        {
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": {"name": "backtick_workflow", "arguments": {}},
        },
    ]
    payload = "\n".join(json.dumps(request) for request in requests) + "\n"
    env = {"BACKTICK_CONNECTOR_CLIENT": connector_client}
    return subprocess.run(
        [helper_path],
        input=payload,
        text=True,
        capture_output=True,
        timeout=30,
        env=env,
    )


def ensure_git_repo(temp_dir: Path) -> None:
    subprocess.run(["git", "init", "-q"], cwd=temp_dir, check=True)
    (temp_dir / "README.md").write_text("workflow harness\n")
    subprocess.run(["git", "add", "README.md"], cwd=temp_dir, check=True)
    subprocess.run(
        ["git", "-c", "user.name=Harness", "-c", "user.email=harness@example.com", "commit", "-q", "-m", "init"],
        cwd=temp_dir,
        check=True,
    )


def run_codex_probe(helper_path: str, connector_client: str, workdir: Path, prompt: str) -> subprocess.CompletedProcess[str]:
    command = [
        "codex",
        "exec",
        "--skip-git-repo-check",
        "--ephemeral",
        "-C",
        str(workdir),
        "-c",
        f'mcp_servers.backtick.command="{helper_path}"',
        "-c",
        f'mcp_servers.backtick.env.BACKTICK_CONNECTOR_CLIENT="{connector_client}"',
        "--json",
        prompt,
    ]
    return subprocess.run(
        command,
        text=True,
        capture_output=True,
        timeout=240,
    )


def print_entries(label: str, entries: list[dict[str, Any]]) -> None:
    print(f"\n{label}")
    if not entries:
        print("  (none)")
        return
    for entry in entries:
        print(
            "  -",
            entry.get("recordedAt"),
            entry.get("targetKind"),
            entry.get("targetName"),
            entry.get("toolName"),
            entry.get("requestedToolName"),
        )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--helper-path", required=True, help="Path to the BacktickMCP helper to test")
    parser.add_argument(
        "--activity-file",
        default=str(Path.home() / "Library/Application Support/PromptCue/BacktickMCPConnectionActivity.json"),
        help="Path to BacktickMCPConnectionActivity.json",
    )
    parser.add_argument(
        "--connector-client",
        default="codex",
        help="Value to set for BACKTICK_CONNECTOR_CLIENT during probes",
    )
    parser.add_argument(
        "--prompt",
        default=DEFAULT_PROMPT,
        help="Natural-language request to send through codex exec",
    )
    parser.add_argument(
        "--workdir",
        help="Optional existing git repo to use for codex exec. If omitted, a temporary harness repo is created.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    helper_path = str(Path(args.helper_path).resolve())
    activity_file = Path(args.activity_file).expanduser()
    start_marker = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    print("Backtick workflow harness")
    print("helper:", helper_path)
    print("activity:", activity_file)
    print("start:", start_marker)

    direct = run_direct_prompt_probe(helper_path, args.connector_client)
    if args.workdir:
        workdir = Path(args.workdir).resolve()
    else:
        workdir = Path(tempfile.mkdtemp(prefix="backtick-workflow-harness."))
        ensure_git_repo(workdir)

    codex = run_codex_probe(helper_path, args.connector_client, workdir, args.prompt)
    state = load_activity_state(activity_file)
    entries = matching_entries(state, helper_path=helper_path, recorded_after=start_marker)

    prompt_entries = [entry for entry in entries if entry.get("toolName") == "prompt:workflow"]
    workflow_tool_entries = [
        entry for entry in entries if entry.get("targetKind") == "tool" and entry.get("targetName") == "backtick_workflow"
    ]
    tool_entries = [entry for entry in entries if entry.get("targetKind") == "tool"]

    print("\nDirect helper probe exit:", direct.returncode)
    print("Codex probe exit:", codex.returncode)
    print("\nDirect helper stdout:")
    print(direct.stdout.strip() or "(empty)")
    print("\nDirect helper stderr:")
    print(direct.stderr.strip() or "(empty)")
    print("\nCodex stdout (truncated):")
    print(codex.stdout[:12000].strip() or "(empty)")
    print("\nCodex stderr (truncated):")
    print(codex.stderr[:4000].strip() or "(empty)")

    print_entries("New activity entries", entries)

    print("\nSummary")
    codex_used_workflow_prompt = any(
        entry.get("clientName") == "codex-mcp-client" and entry.get("toolName") == "prompt:workflow"
        for entry in entries
    )
    codex_used_workflow_tool = any(
        entry.get("clientName") == "codex-mcp-client"
        and entry.get("targetKind") == "tool"
        and entry.get("targetName") == "backtick_workflow"
        for entry in entries
    )
    print("  direct_prompt_observable:", bool(prompt_entries))
    print("  direct_workflow_tool_observable:", bool(workflow_tool_entries))
    print("  codex_used_workflow_prompt:", codex_used_workflow_prompt)
    print("  codex_used_workflow_tool:", codex_used_workflow_tool)
    print("  codex_tool_calls_observed:", bool(tool_entries))

    if not prompt_entries:
        print("  diagnosis: prompt observability did not appear; inspect helper/activity wiring first.")
    elif not workflow_tool_entries:
        print("  diagnosis: workflow tool observability did not appear; inspect tool surface wiring first.")
    elif not (codex_used_workflow_prompt or codex_used_workflow_tool):
        print("  diagnosis: observability works, but natural-language Codex routing stayed on generic tools.")
    else:
        print("  diagnosis: Codex used workflow guidance in this run.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
