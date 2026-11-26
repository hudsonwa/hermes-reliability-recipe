"""progress-continue — dynamic step limit for Hermes bots (opt-in plugin, no core patch).

Hooks:
  post_tool_call  -> feed every tool call/result into a per-session Tracker
  on_session_end  -> when turn_exit_reason is ``max_iterations_reached(...)``, decide:
                       CONTINUE: queue a follow-up user turn via ctx.inject_message
                                 (gateway / classic REPL); one-shot CLI uses bin/pc-run
                       STOP:     post a "stuck on X" report, write it to state
Decisions + signals persist to $HERMES_HOME/progress_continue/<session>.json.
Config: plugins.entries.progress-continue.{max_continuations, wall_clock_cap_s, ...}
"""
from __future__ import annotations

import logging
import os
import threading
from pathlib import Path

from . import core

logger = logging.getLogger(__name__)
_lock = threading.Lock()
_trackers: dict[str, core.Tracker] = {}
_ctx = None


def _home() -> Path:
    try:
        from hermes_constants import get_hermes_home
        return Path(get_hermes_home())
    except Exception:
        return Path(os.environ.get("HERMES_HOME", str(Path.home() / ".hermes")))


def _config() -> core.Config:
    keys = core.Config.__dataclass_fields__.keys()
    m = {}
    if _ctx is not None:
        for k in keys:
            try:
                v = _ctx.get_config(k)
            except Exception:
                v = None
            if v is not None:
                m[k] = v
    for k in keys:  # env override, handy for tests: PC_MAX_CONTINUATIONS=2
        v = os.environ.get("PC_" + k.upper())
        if v:
            m[k] = v
    return core.Config.from_mapping(m)


def _workdir() -> str:
    try:
        if _ctx is not None:
            return _ctx.session_cwd() or os.getcwd()
    except Exception:
        pass
    return os.getcwd()


def _tracker(session_id: str) -> core.Tracker:
    with _lock:
        t = _trackers.get(session_id)
        if t is None:
            st = core.load_state(_home(), session_id)
            t = core.Tracker(session_id, _config(), st)
            t.baseline_plans(_workdir())
            _trackers[session_id] = t
        return t


def on_post_tool_call(tool_name=None, args=None, result=None, session_id=None, task_id=None,
                      status=None, **_):
    sid = session_id or task_id
    if not sid:
        return None
    try:
        t = _tracker(sid)
        with _lock:
            t.observe(tool_name or "?", args, result, status)
    except Exception:
        logger.debug("progress-continue observe failed", exc_info=True)
    return None


def on_session_end(session_id=None, task_id=None, turn_exit_reason=None, interrupted=False,
                   failed=False, **_):
    sid = session_id or task_id
    if not sid:
        return None
    reason = str(turn_exit_reason or "")
    if not reason.startswith("max_iterations_reached") or interrupted:
        return None
    try:
        t = _tracker(sid)
        with _lock:
            d = t.decide(_workdir())
            core.save_state(_home(), t.state)
        logger.warning("progress-continue %s: %s (%s)", sid, d["action"], d["reason"])
        if d["action"] == "continue":
            delivered = False
            if _ctx is not None:
                try:
                    delivered = bool(_ctx.inject_message(core.continue_message(d)))
                except Exception:
                    logger.debug("inject failed", exc_info=True)
            d["delivered"] = delivered  # False on one-shot CLI: bin/pc-run reads state instead
        else:
            if _ctx is not None:
                try:
                    _ctx.post_message(core.stop_report(d))
                except Exception:
                    pass
        with _lock:
            t.state.last_decision = d
            core.save_state(_home(), t.state)
    except Exception:
        logger.warning("progress-continue decide failed", exc_info=True)
    return None


def register(ctx):
    global _ctx
    _ctx = ctx
    ctx.register_hook("post_tool_call", on_post_tool_call)
    ctx.register_hook("on_session_end", on_session_end)
