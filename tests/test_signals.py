import datetime, importlib.machinery, importlib.util, json, pathlib, subprocess, sys, unittest
ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_loader("dw_signals", importlib.machinery.SourceFileLoader("dw_signals", str(ROOT / "bin" / "dw-signals")))
G = importlib.util.module_from_spec(spec); spec.loader.exec_module(G)


class Signals(unittest.TestCase):
    def test_parse_usage(self):
        now = datetime.datetime(2026, 9, 10, 0, 0, tzinfo=datetime.timezone.utc)
        d = {"limits": [{"label": "Session (5-hour)", "percent": 0.66, "resetsAt": "2026-09-10T01:59:59+00:00"}, {"label": "Weekly (7-day)", "percent": 0.46, "resetsAt": "x"}, {"label": "Fable Weekly", "percent": 0.58}]}
        u = G.parse_usage(d, now)
        self.assertEqual((u["session"], u["weekly"], u["resetInMin"], u["label"]), (66, 46, 119, "Session (5-hour)"))
        self.assertEqual(G.parse_usage({"limits": [{"label": "Session", "percent": 42}]}, now)["session"], 42)
        self.assertEqual(G.parse_usage(None)["session"], None); self.assertEqual(G.parse_usage({"limits": [{"label": "Session", "percent": "?"}]}, now)["session"], None)

    def test_count_agents(self):
        self.assertEqual(G.count_agents("bash\nclaude\n/usr/bin/codex\nclaude\nhermes\nvim\n"), 4)
        self.assertEqual(G.count_agents(""), 0)

    def test_live_shape(self):
        out = json.loads(subprocess.run([sys.executable, str(ROOT / "bin" / "dw-signals")], capture_output=True, text=True, timeout=10).stdout)
        for k in ("t", "claude", "battery", "agents", "cpu", "mem", "gpu", "hour"): self.assertIn(k, out)
        self.assertIn("session", out["claude"]); self.assertIn("active", out["agents"])

    def test_custom_signals(self):
        got = G.custom_signals(["n=echo 12", "f=echo 3.5", "t=printf 'YouTube — Firefox'", "bad=exit 3", "slow=sleep 3", "noeq", "empty=true"], timeout=0.5)
        self.assertEqual(got["n"], 12); self.assertIsInstance(got["n"], int)
        self.assertEqual(got["f"], 3.5); self.assertEqual(got["t"], "YouTube — Firefox")
        self.assertIsNone(got["bad"]); self.assertIsNone(got["slow"]); self.assertNotIn("noeq", got); self.assertEqual(got["empty"], "")
        out = json.loads(subprocess.run([sys.executable, str(ROOT / "bin" / "dw-signals"), "--command", "x=echo 7"], capture_output=True, text=True, timeout=10).stdout)
        self.assertEqual(out["custom"]["x"], 7)


if __name__ == "__main__":
    unittest.main()
