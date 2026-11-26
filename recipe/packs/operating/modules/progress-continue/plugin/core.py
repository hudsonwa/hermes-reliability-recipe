"""progress-continue core: pure decision logic, no Hermes imports.

A *segment* is the stretch of tool calls between two hits of ``agent.max_turns``
(or from turn start to the first hit). At each hit we compare the segment that just
ended against what the session has already seen and decide CONTINUE or STOP.
"""
from __future__ import annotations

import hashlib
import json
import os
import re
import time
from collections import Counter
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Mapping, Optional

# Phrases Hermes' tool_guardrails puts into tool results when it warns/blocks/halts.
GUARDRAIL_MARKERS = (
    "returned the same result",
    "This looks like a loop",
    "Stop retrying",
    "Repeating the batch unchanged is not progress",
    "[hermes note: this is the",
    "[hermes note: the last",
    "looks like a runaway",
)
WRITE_TOOLS = {"write_file", "patch", "edit_file", "str_replace_editor", "apply_patch"}
_CHECKBOX = re.compile(r"^\s*[-*]\s*\[( |x|X)\]", re.M)


@dataclass
class Config:
    max_continuations: int = 5
    wall_clock_cap_s: float = 2 * 3600
    min_novel_ratio: float = 0.30      # share of calls in a segment that are new (call+result)
    min_novel_calls: int = 3           # ...and at least this many new ones
    repeat_failure_limit: int = 3      # same failing call this many times in a segment = stuck
    guardrail_hit_limit: int = 2       # guardrail interventions tolerated without hard progress
    plans_glob_root: str = "plans"     # <workdir>/plans/<slug>/plan.md

    @classmethod
    def from_mapping(cls, m: Optional[Mapping[str, Any]]) -> "Config":
        c = cls()
        for k, v in (m or {}).items():
            if hasattr(c, k) and v is not None:
                setattr(c, k, type(getattr(c, k))(v))
        return c


@dataclass
class Segment:
    calls: int = 0
    novel_calls: int = 0
    distinct_sigs: set = field(default_factory=set)
    files_changed: set = field(default_factory=set)
    failures: Counter = field(default_factory=Counter)
    guardrail_hits: int = 0
    sig_counts: Counter = field(default_factory=Counter)


@dataclass
class SessionState:
    session_id: str
    first_limit_at: float = 0.0
    continuations: int = 0
    seen: list = field(default_factory=list)          # sig|result hashes seen this session
    file_hashes: dict = field(default_factory=dict)   # path -> last content hash
    plan_ticks: dict = field(default_factory=dict)    # plan path -> ticked count at last check
    prev_failures: dict = field(default_factory=dict)
    history: list = field(default_factory=list)       # decisions
    last_decision: Optional[dict] = None


def _h(x: Any) -> str:
    if not isinstance(x, str):
        try:
            x = json.dumps(x, sort_keys=True, default=str)
        except Exception:
            x = repr(x)
    return hashlib.sha1(x.encode("utf-8", "replace")).hexdigest()[:16]


def is_failure(status: Any, result: Any) -> bool:
    if status not in (None, "", "ok", "success"):
        return True
    r = str(result or "")[:400].lower()
    return r.startswith('{"error"') or r.startswith("error") or '"success": false' in r


def is_guardrail(result: Any) -> bool:
    r = str(result or "")
    return any(m in r for m in GUARDRAIL_MARKERS)


def plan_ticks(workdir: str, root: str = "plans") -> dict[str, tuple[int, int]]:
    """{plan.md path: (ticked, total)} for <workdir>/plans/*/plan.md."""
    out: dict[str, tuple[int, int]] = {}
    if not workdir:
        return out
    base = Path(workdir) / root
    if not base.is_dir():
        return out
    for p in sorted(base.glob("*/plan.md")):
        try:
            txt = p.read_text(errors="replace")
        except OSError:
            continue
        boxes = _CHECKBOX.findall(txt)
        out[str(p)] = (sum(1 for b in boxes if b.lower() == "x"), len(boxes))
    return out


def next_open_item(workdir: str, root: str = "plans") -> str:
    base = Path(workdir or ".") / root
    if not base.is_dir():
        return ""
    for p in sorted(base.glob("*/plan.md")):
        for line in p.read_text(errors="replace").splitlines():
            if re.match(r"^\s*[-*]\s*\[ \]", line):
                return f"{p.parent.name}: {line.split(']', 1)[1].strip()}"
    return ""


class Tracker:
    """Per-session tracker. Feed it tool calls; ask it to decide at each limit hit."""

    def __init__(self, session_id: str, config: Config | None = None,
                 state: SessionState | None = None, now=time.time):
        self.cfg = config or Config()
        self.state = state or SessionState(session_id=session_id)
        self.seg = Segment()
        self._seen = set(self.state.seen)
        self.now = now

    # ---- observation -------------------------------------------------------------
    def observe(self, tool_name: str, args: Any, result: Any, status: Any = None) -> None:
        s = self.seg
        sig = f"{tool_name}:{_h(args)}"
        key = f"{sig}|{_h(result)}"
        s.calls += 1
        s.sig_counts[sig] += 1
        s.distinct_sigs.add(sig)
        if key not in self._seen:
            self._seen.add(key)
            s.novel_calls += 1
        if is_guardrail(result):
            s.guardrail_hits += 1
        if is_failure(status, result):
            s.failures[sig] += 1
        if tool_name in WRITE_TOOLS and isinstance(args, Mapping):
            path = args.get("path") or args.get("file_path")
            if path and not is_failure(status, result):
                content_h = _h(args.get("content") or args.get("new_string") or args)
                if self.state.file_hashes.get(path) != content_h:
                    self.state.file_hashes[path] = content_h
                    s.files_changed.add(path)

    # ---- decision ------------------------------------------------------------------
    def decide(self, workdir: str = "") -> dict:
        cfg, st, s = self.cfg, self.state, self.seg
        now = self.now()
        if not st.first_limit_at:
            st.first_limit_at = now
        ticks_now = plan_ticks(workdir, cfg.plans_glob_root)
        # Plans are baselined at the first observed call (baseline_plans); a plan created
        # during the window counts its ticked items as new.
        new_ticks = sum(max(0, t - st.plan_ticks.get(p, 0)) for p, (t, _) in ticks_now.items())
        novel_ratio = (s.novel_calls / s.calls) if s.calls else 0.0
        hard_progress = new_ticks > 0 or bool(s.files_changed)
        soft_progress = s.novel_calls >= cfg.min_novel_calls and novel_ratio >= cfg.min_novel_ratio
        worst_fail, worst_n = (s.failures.most_common(1)[0] if s.failures else ("", 0))
        repeated_from_before = worst_fail and st.prev_failures.get(worst_fail, 0) > 0

        signals = {
            "calls": s.calls, "novel_calls": s.novel_calls, "novel_ratio": round(novel_ratio, 2),
            "distinct_calls": len(s.distinct_sigs), "files_changed": sorted(s.files_changed),
            "plan_ticks_new": new_ticks, "guardrail_hits": s.guardrail_hits,
            "top_failure": worst_fail, "top_failure_count": worst_n,
            "continuations_so_far": st.continuations,
            "elapsed_s": round(now - st.first_limit_at, 1),
        }
        reason, action = "", "continue"
        if st.continuations >= cfg.max_continuations:
            action, reason = "stop", f"hit continuation cap ({cfg.max_continuations})"
        elif now - st.first_limit_at > cfg.wall_clock_cap_s:
            action, reason = "stop", f"hit wall-clock cap ({int(cfg.wall_clock_cap_s)}s)"
        elif worst_n >= cfg.repeat_failure_limit and (repeated_from_before or not hard_progress):
            action, reason = "stop", f"same failure repeated {worst_n}x: {worst_fail.split(':')[0]}"
        elif s.guardrail_hits >= cfg.guardrail_hit_limit and not hard_progress:
            action, reason = "stop", f"loop guardrail fired {s.guardrail_hits}x with no file/plan progress"
        elif not (hard_progress or soft_progress):
            action, reason = "stop", (f"no progress this window ({s.novel_calls}/{s.calls} new calls, "
                                      "no files changed, no plan items ticked)")
        else:
            why = []
            if new_ticks: why.append(f"{new_ticks} plan item(s) ticked")
            if s.files_changed: why.append(f"{len(s.files_changed)} file(s) changed")
            if soft_progress: why.append(f"{s.novel_calls}/{s.calls} new calls")
            reason = "progressing: " + ", ".join(why)

        stuck_on = ""
        if action == "stop":
            top_sig = s.sig_counts.most_common(1)[0][0] if s.sig_counts else ""
            stuck_on = (worst_fail or top_sig).split(":")[0]
            nxt = next_open_item(workdir, cfg.plans_glob_root)
            if nxt:
                stuck_on = f"{stuck_on} while on plan item '{nxt}'" if stuck_on else f"plan item '{nxt}'"
        decision = {"action": action, "reason": reason, "stuck_on": stuck_on,
                    "signals": signals, "at": now}

        # roll state forward
        if action == "continue":
            st.continuations += 1
        st.plan_ticks = {p: t for p, (t, _) in ticks_now.items()}
        st.prev_failures = dict(s.failures)
        st.seen = sorted(self._seen)[-5000:]
        st.history.append({k: decision[k] for k in ("action", "reason")})
        st.last_decision = decision
        self.seg = Segment()
        return decision

    def baseline_plans(self, workdir: str) -> None:
        """Record plan tick counts at turn start so the first window can count new ticks."""
        if not self.state.plan_ticks:
            self.state.plan_ticks = {p: t for p, (t, _) in plan_ticks(workdir, self.cfg.plans_glob_root).items()}


def continue_message(d: dict) -> str:
    sig = d["signals"]
    return ("[progress-continue] You hit the per-turn step limit but are making progress "
            f"({d['reason']}). Continue the task from where you left off (continuation "
            f"{sig['continuations_so_far'] + 1}). Do not repeat finished steps; tick plan items as you go.")


def stop_report(d: dict) -> str:
    s = d["signals"]
    return (f"[progress-continue] Stopped at the step limit: stuck on {d['stuck_on'] or 'unknown'}. "
            f"Reason: {d['reason']}. Last window: {s['calls']} calls, {s['novel_calls']} new, "
            f"{len(s['files_changed'])} files changed, {s['plan_ticks_new']} plan items ticked, "
            f"{s['guardrail_hits']} guardrail hits; {s['continuations_so_far']} auto-continues used.")


# ---- persistence ------------------------------------------------------------------
def state_path(home: str | os.PathLike, session_id: str) -> Path:
    safe = re.sub(r"[^A-Za-z0-9_.-]", "_", session_id or "unknown")
    return Path(home) / "progress_continue" / f"{safe}.json"


def save_state(home, st: SessionState) -> Path:
    p = state_path(home, st.session_id)
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(asdict(st), default=str, indent=1))
    os.replace(tmp, p)
    (p.parent / "LAST_SESSION").write_text(st.session_id)
    return p


def load_state(home, session_id: str) -> Optional[SessionState]:
    p = state_path(home, session_id)
    if not p.exists():
        return None
    try:
        return SessionState(**json.loads(p.read_text()))
    except Exception:
        return None
