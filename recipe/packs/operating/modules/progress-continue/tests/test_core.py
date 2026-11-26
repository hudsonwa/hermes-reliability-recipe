import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "plugin"))
import core  # noqa: E402


class Clock:
    def __init__(self): self.t = 1000.0
    def __call__(self): return self.t


def mk(**cfg):
    clk = Clock()
    return core.Tracker("s1", core.Config(**cfg), now=clk), clk


def test_novel_calls_continue():
    t, _ = mk()
    for i in range(10):
        t.observe("read_file", {"path": f"f{i}"}, f"content {i}")
    d = t.decide("")
    assert d["action"] == "continue" and "new calls" in d["reason"]


def test_repeated_identical_calls_stop():
    t, _ = mk()
    t.observe("read_file", {"path": "a"}, "same")
    t.decide("")
    for _ in range(10):
        t.observe("read_file", {"path": "a"}, "same")
    d = t.decide("")
    assert d["action"] == "stop" and "no progress" in d["reason"]
    assert "read_file" in d["stuck_on"]


def test_file_write_is_hard_progress_even_with_low_novelty():
    t, _ = mk()
    for _ in range(10):
        t.observe("terminal", {"command": "ls"}, "x")
    t.decide("")
    for _ in range(10):
        t.observe("terminal", {"command": "ls"}, "x")
    t.observe("write_file", {"path": "out.txt", "content": "v1"}, '{"ok": true}')
    d = t.decide("")
    assert d["action"] == "continue" and "file" in d["reason"]
    # same content again is not a change
    for _ in range(10):
        t.observe("terminal", {"command": "ls"}, "x")
    t.observe("write_file", {"path": "out.txt", "content": "v1"}, '{"ok": true}')
    assert t.decide("")["action"] == "stop"


def test_plan_ticks_count(tmp_path):
    plan = tmp_path / "plans" / "job" / "plan.md"
    plan.parent.mkdir(parents=True)
    plan.write_text("- [ ] a\n- [ ] b\n- [ ] c\n")
    t, _ = mk()
    t.baseline_plans(str(tmp_path))
    for _ in range(5):
        t.observe("terminal", {"command": "ls"}, "x")
    plan.write_text("- [x] a\n- [ ] b\n- [ ] c\n")
    d = t.decide(str(tmp_path))
    assert d["action"] == "continue" and d["signals"]["plan_ticks_new"] == 1
    for _ in range(5):
        t.observe("terminal", {"command": "ls"}, "x")
    d = t.decide(str(tmp_path))
    assert d["action"] == "stop" and "plan item 'job: b'" in d["stuck_on"]


def test_repeated_failure_stop():
    t, _ = mk()
    for i in range(6):
        t.observe("read_file", {"path": f"n{i}"}, f"ok{i}")
    for _ in range(4):
        t.observe("terminal", {"command": "make"}, "Error: boom", status="error")
    d = t.decide("")
    assert d["action"] == "stop" and "same failure repeated 4x" in d["reason"]


def test_guardrail_hits_without_hard_progress_stop():
    t, _ = mk()
    for i in range(8):
        t.observe("web_search", {"q": i}, f"r{i}")
    t.observe("web_search", {"q": 0}, "web_search returned the same result 3 times. x")
    t.observe("web_search", {"q": 0}, "Blocked web_search: This looks like a loop")
    d = t.decide("")
    assert d["action"] == "stop" and "guardrail" in d["reason"]


def test_continuation_cap():
    t, _ = mk(max_continuations=2)
    acts = []
    for r in range(4):
        for i in range(5):
            t.observe("read_file", {"path": f"{r}-{i}"}, f"{r}-{i}")
        acts.append(t.decide("")["action"])
    assert acts == ["continue", "continue", "stop", "stop"]


def test_wall_clock_cap():
    t, clk = mk(wall_clock_cap_s=60)
    for i in range(5):
        t.observe("read_file", {"path": i}, i)
    assert t.decide("")["action"] == "continue"
    clk.t += 120
    for i in range(5):
        t.observe("read_file", {"path": f"x{i}"}, i)
    d = t.decide("")
    assert d["action"] == "stop" and "wall-clock" in d["reason"]


def test_state_roundtrip(tmp_path):
    t, _ = mk()
    t.observe("read_file", {"path": "a"}, "A")
    t.decide("")
    core.save_state(tmp_path, t.state)
    st = core.load_state(tmp_path, "s1")
    t2 = core.Tracker("s1", core.Config(), st)
    t2.observe("read_file", {"path": "a"}, "A")  # already seen -> not novel
    assert t2.seg.novel_calls == 0 and st.continuations == 0 and st.last_decision["action"] == "stop"
    assert (tmp_path / "progress_continue" / "LAST_SESSION").read_text() == "s1"


def test_config_from_mapping():
    c = core.Config.from_mapping({"max_continuations": "7", "bogus": 1})
    assert c.max_continuations == 7


def _load_plugin():
    spec = importlib.util.spec_from_file_location(
        "pc_plugin", ROOT / "plugin" / "__init__.py",
        submodule_search_locations=[str(ROOT / "plugin")])
    mod = importlib.util.module_from_spec(spec)
    sys.modules["pc_plugin"] = mod
    spec.loader.exec_module(mod)
    return mod


class FakeCtx:
    def __init__(self, cwd): self.injected, self.posted, self.hooks, self.cwd = [], [], {}, cwd
    def register_hook(self, n, cb): self.hooks[n] = cb
    def get_config(self, k, d=None): return {"max_continuations": 1}.get(k, d)
    def session_cwd(self): return self.cwd
    def inject_message(self, m): self.injected.append(m); return True
    def post_message(self, m): self.posted.append(m)


def test_plugin_hooks_end_to_end(tmp_path, monkeypatch):
    monkeypatch.setenv("HERMES_HOME", str(tmp_path))
    monkeypatch.setitem(sys.modules, "hermes_constants", None)  # force env fallback
    p = _load_plugin()
    ctx = FakeCtx(str(tmp_path))
    p.register(ctx)
    assert set(ctx.hooks) == {"post_tool_call", "on_session_end"}
    for i in range(5):
        ctx.hooks["post_tool_call"](tool_name="read_file", args={"path": i}, result=i, session_id="S")
    ctx.hooks["on_session_end"](session_id="S", turn_exit_reason="completed")
    assert not ctx.injected  # not a limit hit -> untouched
    ctx.hooks["on_session_end"](session_id="S", turn_exit_reason="max_iterations_reached(5/5)")
    assert len(ctx.injected) == 1 and "Continue the task" in ctx.injected[0]
    for i in range(5):
        ctx.hooks["post_tool_call"](tool_name="read_file", args={"path": f"y{i}"}, result=i, session_id="S")
    ctx.hooks["on_session_end"](session_id="S", turn_exit_reason="max_iterations_reached(5/5)")
    assert len(ctx.injected) == 1 and "continuation cap" in ctx.posted[0]
    assert core.load_state(tmp_path, "S").last_decision["action"] == "stop"
