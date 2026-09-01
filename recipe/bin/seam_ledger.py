#!/usr/bin/env python3
"""Machine-written seam ledger. Deterministic; no LLM."""
from __future__ import annotations

import re

_ERROR_LINE = re.compile(
    r"^(?:[A-Za-z_][\w.]*Error|ERROR|Error|FAILED|fatal:)\s*:?\s*.+$",
    re.M,
)


def extract_last_error(tool_output: str) -> str | None:
    text = tool_output or ""
    matches = _ERROR_LINE.findall(text)
    if not matches:
        return None
    line = matches[-1].strip()
    return line[:240]


def render_ledger(
    goal: str,
    verified: list[str],
    open_items: list[str],
    next_action: str,
    last_error: str | None,
    model_opinion: str | None = None,
) -> str:
    del model_opinion  # never rendered — opinions are not state
    lines = [
        f"Goal: {goal}",
        "Verified:",
    ]
    if verified:
        lines.extend(f"  - {item}" for item in verified)
    else:
        lines.append("  - (none)")
    lines.append("Open:")
    if open_items:
        lines.extend(f"  - {item}" for item in open_items)
    else:
        lines.append("  - (none)")
    lines.append(f"Next: {next_action}")
    lines.append(f"LastError: {last_error or 'none'}")
    return "\n".join(lines) + "\n"


def retry_decision(history_fingerprints: list[str], new_fp: str) -> str:
    n = sum(1 for fp in history_fingerprints if fp == new_fp)
    if n == 0:
        return "none"
    if n == 1:
        return "retry"
    return "stop"
