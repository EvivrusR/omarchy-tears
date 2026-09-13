import importlib.machinery, importlib.util, io, json, os, pathlib, struct, sys, tempfile, unittest, zlib
from contextlib import redirect_stdout, redirect_stderr

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_loader("dw", importlib.machinery.SourceFileLoader("dw", str(ROOT / "bin" / "desktop-widgets")))
dw = importlib.util.module_from_spec(spec); spec.loader.exec_module(dw)
REGISTRY = dw.load_registry(str(ROOT / "widgets" / "registry.json"))


def _png(w, h, blank_cells=()):
    """Minimal RGBA PNG: opaque everywhere except the listed (row, col) 192×208 cells, which are fully transparent."""
    rows = []
    for y in range(h):
        line = bytearray([0])
        for x in range(w):
            a = 0 if (y // 208, x // 192) in blank_cells else 255
            line += bytes((255, 0, 0, a))
        rows.append(bytes(line))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b"")


class Corners(unittest.TestCase):
    def test_cli_corner_choices_match_registry(self):
        """`add --corner` / `move --corner` must accept every corner the registry allows (centre ones included)."""
        field = next(f for f in REGISTRY["common"] if f["key"] == "corner")
        self.assertEqual(list(dw.CORNERS), list(field["options"]))


class Fixtures(unittest.TestCase):
    def test_jsonc_fixtures(self):
        d = ROOT / "tests" / "fixtures" / "jsonc"
        for f in sorted(d.glob("*.jsonc")):
            with self.subTest(f.name):
                expected = json.loads(f.with_suffix(".json").read_text())
                self.assertEqual(json.loads(dw.strip_jsonc(f.read_text())), expected)

    def test_validate_fixtures(self):
        d = ROOT / "tests" / "fixtures" / "validate"
        for f in sorted(d.glob("*.json")):
            with self.subTest(f.name):
                fx = json.loads(f.read_text())
                widgets, msgs = dw.validate_config(fx["config"], REGISTRY)
                self.assertEqual(None if widgets is None else len(widgets), fx["expect"]["widgets"])
                self.assertEqual(sum(m["level"] == "error" for m in msgs), fx["expect"]["errors"], msgs)
                self.assertEqual(sum(m["level"] == "warning" for m in msgs), fx["expect"]["warnings"], msgs)
                texts = [(f"widget {m['widget']}: " if m["widget"] >= 0 else "") + m["message"] for m in msgs]
                for want in fx["expect"].get("messages", []):
                    self.assertIn(want, texts)

    def test_apply_defaults(self):
        e = dw.apply_defaults({"type": "clock", "x": 10}, REGISTRY)
        self.assertEqual((e["x"], e["y"], e["corner"], e["dateFormat"]), (10, 48, "top-right", "dddd d MMMM"))
        self.assertEqual(dw.apply_defaults({"type": "nope"}, REGISTRY), {"type": "nope"})


class CliCase(unittest.TestCase):
    """Temp HOME with a two-widget config; `run_cli` captures stdout/stderr."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = pathlib.Path(self.tmp.name)
        os.environ["HOME"] = str(self.home); os.environ.pop("XDG_CONFIG_HOME", None)
        self.cfg = self.home / ".config" / "omarchy" / "desktop-widgets.json"
        self.cfg.parent.mkdir(parents=True)
        self.cfg.write_text(json.dumps({"widgets": [
            {"type": "clock", "corner": "top-right"},
            {"type": "stats", "corner": "bottom-left", "enabled": False}]}))

    def tearDown(self): self.tmp.cleanup()

    def run_cli(self, *argv):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = dw.main(list(argv))
        return code, out.getvalue(), err.getvalue()

    def write_dropin(self, name, type_json='{"displayName":"Hello","fields":[{"key":"name","type":"string","label":"Name","default":"world"}]}', qml="WidgetCard {}"):
        d = self.home / ".config" / "omarchy" / "desktop-widgets.d" / name
        d.mkdir(parents=True, exist_ok=True)
        if type_json is not None: (d / "type.json").write_text(type_json)
        if qml is not None: (d / "Widget.qml").write_text(qml)
        return d


class Cli(CliCase):
    def test_path(self):
        code, out, _ = self.run_cli("path")
        self.assertEqual((code, out.strip()), (0, str(self.cfg)))

    def test_validate_ok_and_bad(self):
        self.assertEqual(self.run_cli("validate")[0], 0)
        self.cfg.write_text('{"widgets":[{"type":"clock","corner":"middle"}]}')
        code, out, err = self.run_cli("validate")
        self.assertEqual(code, 1); self.assertIn("corner must be one of", err)
        self.cfg.write_text("{ not json")
        self.assertEqual(self.run_cli("validate")[0], 1)

    def test_list(self):
        code, out, _ = self.run_cli("list")
        self.assertEqual(code, 0)
        self.assertIn("0  clock", out); self.assertIn("top-right", out)
        self.assertIn("1  stats", out); self.assertIn("off", out)

    def test_types(self):
        code, out, _ = self.run_cli("types")
        self.assertEqual(code, 0)
        for t in ("clock", "stats", "command", "agents"): self.assertIn(t, out)
        code, out, _ = self.run_cli("types", "stats")
        self.assertIn("intervalSec", out); self.assertIn("default 3", out)
        self.assertEqual(self.run_cli("types", "nope")[0], 2)

    def test_api_number_is_printed(self):
        code, out, _ = self.run_cli("registry", "--json")
        self.assertEqual(json.loads(out)["api"], 1)
        self.assertIn("kit api 1", self.run_cli("types")[1])
        self.assertIn("api:     1", self.run_cli("status")[1])

    def test_missing_config(self):
        self.cfg.unlink()
        code, out, err = self.run_cli("list")
        self.assertEqual(code, 0); self.assertIn("no config", out)

    def read(self):
        return json.loads(self.cfg.read_text())["widgets"]

    def test_add_and_bak(self):
        code, out, _ = self.run_cli("add", "command", "--corner", "bottom-right", "--set", "command=uptime -p", "--set", "intervalSec=30")
        self.assertEqual(code, 0)
        w = self.read()
        self.assertEqual(len(w), 3)
        self.assertEqual(w[2]["type"], "command"); self.assertEqual(w[2]["corner"], "bottom-right")
        self.assertEqual(w[2]["command"], "uptime -p"); self.assertEqual(w[2]["intervalSec"], 30)
        self.assertTrue(self.cfg.with_name("desktop-widgets.json.bak").exists())

    def test_add_rejects_bad_values(self):
        code, _, err = self.run_cli("add", "stats", "--set", "intervalSec=zero")
        self.assertEqual(code, 1); self.assertIn("integer", err)
        self.assertEqual(len(self.read()), 2)
        self.assertEqual(self.run_cli("add", "nope")[0], 2)

    def test_set_types_values(self):
        code, _, _ = self.run_cli("set", "1", "enabled=true", "show=cpu,mem", "intervalSec=5", "scale=1.5")
        self.assertEqual(code, 0)
        w = self.read()[1]
        self.assertEqual((w["enabled"], w["show"], w["intervalSec"], w["scale"]), (True, ["cpu", "mem"], 5, 1.5))
        self.assertEqual(self.run_cli("set", "9", "x=1")[0], 2)
        code, _, err = self.run_cli("set", "0", "corner=middle")
        self.assertEqual(code, 1); self.assertEqual(self.read()[0]["corner"], "top-right")

    def test_move_enable_disable_remove_duplicate(self):
        self.assertEqual(self.run_cli("move", "0", "--corner", "bottom-left", "--x", "10", "--y", "20")[0], 0)
        self.assertEqual((self.read()[0]["corner"], self.read()[0]["x"], self.read()[0]["y"]), ("bottom-left", 10, 20))
        self.assertEqual(self.run_cli("enable", "1")[0], 0); self.assertNotIn("enabled", self.read()[1])
        self.assertEqual(self.run_cli("disable", "1")[0], 0); self.assertFalse(self.read()[1]["enabled"])
        self.assertEqual(self.run_cli("duplicate", "0")[0], 0); self.assertEqual(len(self.read()), 3)
        self.assertEqual(self.read()[1]["corner"], "bottom-left")
        self.assertEqual(self.run_cli("remove", "1")[0], 0); self.assertEqual(len(self.read()), 2)

    def test_refuses_to_drop_comments_without_force(self):
        self.cfg.write_text('{ "widgets": [ // hello\n { "type": "clock" } ] }')
        code, _, err = self.run_cli("set", "0", "x=5")
        self.assertEqual(code, 2); self.assertIn("comments", err)
        self.assertEqual(self.run_cli("set", "0", "x=5", "--force")[0], 0)
        self.assertEqual(self.read()[0]["x"], 5)

    def test_add_creates_missing_config(self):
        self.cfg.unlink()
        self.assertEqual(self.run_cli("add", "clock")[0], 0)
        self.assertEqual(self.read()[0]["type"], "clock")
        self.assertFalse(self.cfg.with_name("desktop-widgets.json.bak").exists())

    def test_plugin_enabled_reads_shell_json(self):
        sj = self.home / ".config" / "omarchy" / "shell.json"
        sj.write_text('{"plugins":[{"id":"homelab.desktop-widgets"}]}')
        self.assertTrue(dw.plugin_enabled(str(sj)))
        sj.write_text('{"plugins":[]}')
        self.assertFalse(dw.plugin_enabled(str(sj)))
        self.assertFalse(dw.plugin_enabled(str(sj) + ".missing"))
        self.assertEqual(self.run_cli("status", "--enabled")[0], 1)

    def test_edit_keeps_text_verbatim_and_validates(self):
        os.environ["EDITOR"] = "python3 -c \"import sys,pathlib; p=pathlib.Path(sys.argv[1]); p.write_text('{ \\\"widgets\\\": [ // kept\\n { \\\"type\\\": \\\"clock\\\", \\\"x\\\": 7 } ] }\\n')\""
        code, out, err = self.run_cli("edit")
        self.assertEqual(code, 0, err)
        self.assertIn("// kept", self.cfg.read_text())
        self.assertTrue(self.cfg.with_name("desktop-widgets.json.bak").exists())
        os.environ["EDITOR"] = "python3 -c \"import sys,pathlib; pathlib.Path(sys.argv[1]).write_text('{ \\\"widgets\\\": [ { \\\"type\\\": \\\"clock\\\", \\\"corner\\\": \\\"middle\\\" } ] }')\""
        code, out, err = self.run_cli("edit")   # non-tty: refuses to save invalid
        self.assertEqual(code, 1); self.assertIn("corner must be one of", err)
        self.assertIn("// kept", self.cfg.read_text())
        os.environ["EDITOR"] = "true"
        code, out, err = self.run_cli("edit")
        self.assertEqual(code, 0); self.assertIn("no changes", out)

    def run_cli_stdin(self, text, *argv):
        out, err = io.StringIO(), io.StringIO()
        old = sys.stdin; sys.stdin = io.StringIO(text)
        try:
            with redirect_stdout(out), redirect_stderr(err):
                code = dw.main(list(argv))
        finally:
            sys.stdin = old
        return code, out.getvalue(), err.getvalue()

    def test_write_from_stdin_validates_and_backs_up(self):
        doc = {"version": 1, "widgets": [{"type": "agents", "corner": "top-left"}]}
        code, out, err = self.run_cli_stdin(json.dumps(doc), "write")
        self.assertEqual(code, 0, err)
        self.assertEqual(self.read()[0]["type"], "agents")
        self.assertIn('"type": "clock"', self.cfg.with_name("desktop-widgets.json.bak").read_text())
        code, _, err = self.run_cli_stdin('{"widgets":[{"type":"clock","corner":"middle"}]}', "write")
        self.assertEqual(code, 1); self.assertIn("corner must be one of", err)
        self.assertEqual(self.read()[0]["type"], "agents")
        code, _, err = self.run_cli_stdin('{ nope', "write")
        self.assertEqual(code, 1); self.assertIn("parse error", err)
        code, _, err = self.run_cli_stdin('[{"type":"clock"}]', "write")
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(self.cfg.read_text())["version"], 1)

    def test_arrange_reports_shell_answer(self):
        orig = dw.run_quiet
        try:
            dw.run_quiet = lambda cmd: "on\n"
            code, out, _ = self.run_cli("arrange", "on")
            self.assertEqual((code, out.strip()), (0, "on"))
            dw.run_quiet = lambda cmd: ""
            self.assertEqual(self.run_cli("arrange")[0], 2)
        finally:
            dw.run_quiet = orig

    def test_dropin_merges_into_registry_and_validates(self):
        d = self.write_dropin("hello")
        reg = dw.load_registry()
        self.assertIn("hello", reg["types"])
        self.assertEqual(reg["types"]["hello"]["source"], str(d / "Widget.qml"))
        self.assertTrue(reg["types"]["hello"]["dropIn"])
        self.assertEqual([f["key"] for f in dw.fields_for("hello", reg)][-1], "name")
        self.cfg.write_text('{"widgets":[{"type":"hello","name":"sir","corner":"top-left"}]}')
        self.assertEqual(self.run_cli("validate")[0], 0)
        code, out, _ = self.run_cli("types")
        self.assertEqual(code, 0); self.assertIn("hello", out); self.assertIn("drop-in", out)

    def test_dropin_problems_are_reported_not_fatal(self):
        self.write_dropin("Bad Name")
        self.write_dropin("nojson", type_json=None)
        self.write_dropin("noqml", qml=None)
        self.write_dropin("broken", type_json="{ nope")
        self.write_dropin("clock")   # shadows a built-in
        reg = dw.load_registry()
        for t in ("Bad Name", "nojson", "noqml", "broken"): self.assertNotIn(t, reg["types"])
        self.assertFalse(reg["types"]["clock"].get("dropIn", False))
        self.assertEqual(len(reg["problems"]), 5)
        code, out, err = self.run_cli("types")
        self.assertEqual(code, 0); self.assertIn("problem", err.lower())

    def test_dropin_requires_api(self):
        self.write_dropin("fresh", type_json='{"displayName":"F","requires":{"api":1},"fields":[]}')
        self.write_dropin("future", type_json='{"displayName":"F","requires":{"api":2},"fields":[]}')
        self.write_dropin("junk", type_json='{"displayName":"F","requires":{"api":"x"},"fields":[]}')
        self.write_dropin("junk2", type_json='{"displayName":"F","requires":[1],"fields":[]}')
        reg = dw.load_registry()
        self.assertIn("fresh", reg["types"]); self.assertIn("future", reg["types"]); self.assertNotIn("junk", reg["types"]); self.assertNotIn("junk2", reg["types"])
        self.assertEqual(reg["types"]["future"]["requires"], {"api": 2})
        self.assertNotIn("requires", reg["types"]["clock"])
        self.assertEqual(reg["warnings"], ["future wants api 2, plugin provides 1"])
        self.assertEqual(sum("requires.api must be a positive integer" in p for p in reg["problems"]), 2)
        for argv in (("types",), ("registry",), ("validate",)):
            code, out, err = self.run_cli(*argv)
            self.assertEqual(code, 0, err); self.assertIn("future wants api 2, plugin provides 1", err)
        self.assertNotIn("warnings", dw.load_registry(dropins=False))

    def test_sysinfo_custom_art_from_cli(self):
        code, out, err = self.run_cli("add", "sysinfo", "--set", "logo=custom", "--set", "art=/\\_/\\\\n( o.o )")
        self.assertEqual(code, 0, err)
        e = json.loads(self.cfg.read_text())["widgets"][-1]
        self.assertEqual(e["art"], "/\\_/\\\n( o.o )"); self.assertEqual(e["logo"], "custom")
        self.assertEqual(self.run_cli("set", "2", "logo=archlinux")[0], 1)

    def test_apps_listing_and_dock(self):
        data = self.home / ".local" / "share" / "applications"; data.mkdir(parents=True)
        (data / "Alacritty.desktop").write_text("[Desktop Entry]\nType=Application\nName=Alacritty\nIcon=Alacritty\n")
        (data / "hidden.desktop").write_text("[Desktop Entry]\nType=Application\nName=Hidden\nNoDisplay=true\n")
        (data / "link.desktop").write_text("[Desktop Entry]\nType=Link\nName=Link\n")
        (data / "btop.desktop").write_text("[Desktop Entry]\nType=Application\nName=btop++\n")
        os.environ["XDG_DATA_HOME"] = str(self.home / ".local" / "share"); os.environ["XDG_DATA_DIRS"] = str(self.home / "nowhere")
        try:
            apps = dw.list_apps(hides={"btop"})
            self.assertEqual(apps["Alacritty"], {"name": "Alacritty", "icon": "Alacritty", "hidden": False})
            self.assertTrue(apps["hidden"]["hidden"]); self.assertTrue(apps["btop"]["hidden"]); self.assertNotIn("link", apps)
            code, out, _ = self.run_cli("apps"); self.assertEqual(code, 0); self.assertIn("Alacritty", out); self.assertNotIn("Hidden", out)
            code, out, _ = self.run_cli("apps", "--json", "--all"); self.assertEqual({a["id"] for a in json.loads(out)["apps"]} >= {"Alacritty", "hidden"}, True)
        finally:
            os.environ.pop("XDG_DATA_HOME", None); os.environ.pop("XDG_DATA_DIRS", None)
        code, out, err = self.run_cli("add", "dock", "--set", "apps=Alacritty,chromium")
        self.assertEqual(code, 0, err)
        e = json.loads(self.cfg.read_text())["widgets"][-1]
        self.assertEqual(e["apps"], ["Alacritty", "chromium"]); self.assertNotIn("corner", e)   # default corner comes from the type
        self.assertEqual(dw.apply_defaults(e, REGISTRY)["corner"], "bottom-center")
        code, out, _ = self.run_cli("list"); self.assertIn("Alacritty,chromium", out); self.assertIn("bottom-center", out)
        code, out, _ = self.run_cli("types", "dock"); self.assertIn("bottom-center", out)
        self.assertEqual(self.run_cli("set", "2", "corner=middle")[0], 1)

    def test_grid_setting_round_trips_every_writer(self):
        code, out, err = self.run_cli("grid")
        self.assertEqual(code, 0); self.assertIn("off", out); self.assertIn("24", out)
        self.assertEqual(self.run_cli("grid", "on")[0], 0)
        self.assertEqual(json.loads(self.cfg.read_text())["grid"], {"enabled": True, "size": 24})
        self.assertEqual(self.run_cli("grid", "32")[0], 0)
        self.assertEqual(json.loads(self.cfg.read_text())["grid"], {"enabled": True, "size": 32})
        self.assertEqual(self.run_cli("grid", "2")[0], 2); self.assertEqual(self.run_cli("grid", "huge")[0], 2)
        # mutators keep it
        self.assertEqual(self.run_cli("add", "clock")[0], 0)
        self.assertEqual(self.run_cli("set", "0", "x=10")[0], 0)
        self.assertEqual(json.loads(self.cfg.read_text())["grid"]["size"], 32)
        # preset apply keeps it, and a preset never carries it
        self.assertEqual(self.run_cli("preset", "save", "g")[0], 0)
        user = self.home / ".config" / "omarchy" / "desktop-widgets.presets" / "g.jsonc"
        self.assertNotIn("grid", json.loads(user.read_text()))
        self.assertEqual(self.run_cli("preset", "apply", "minimal")[0], 0)
        self.assertEqual(json.loads(self.cfg.read_text())["grid"], {"enabled": True, "size": 32})
        # write (editor path) keeps it when the document omits it, honours it when present
        code, _, err = self.run_cli_stdin(json.dumps({"version": 1, "widgets": [{"type": "clock"}]}), "write")
        self.assertEqual(code, 0, err); self.assertEqual(json.loads(self.cfg.read_text())["grid"]["size"], 32)
        code, _, err = self.run_cli_stdin(json.dumps({"version": 1, "widgets": [], "grid": {"enabled": False, "size": 16}}), "write")
        self.assertEqual(code, 0, err); self.assertEqual(json.loads(self.cfg.read_text())["grid"], {"enabled": False, "size": 16})
        self.assertEqual(self.run_cli("grid", "off")[0], 0)
        code, out, _ = self.run_cli("validate")
        self.assertEqual(code, 0)
        self.cfg.write_text(json.dumps({"widgets": [], "grid": {"enabled": True, "size": 1}}))
        code, out, err = self.run_cli("validate"); self.assertEqual(code, 1); self.assertIn("grid", err)

    def test_shipped_presets_validate(self):
        names = sorted(p.stem for p in (ROOT / "presets").glob("*.jsonc"))
        self.assertEqual(names, ["column", "dashboard", "minimal", "ops"])
        for n in names:
            code, out, err = self.run_cli("validate", str(ROOT / "presets" / f"{n}.jsonc"))
            self.assertEqual(code, 0, f"{n}: {err}")
            self.assertIn("0 warning", out, n)

    def test_preset_list_apply_save_remove(self):
        code, out, _ = self.run_cli("preset", "list")
        self.assertEqual(code, 0); self.assertIn("minimal", out); self.assertIn("shipped", out)
        code, out, _ = self.run_cli("preset", "list", "--json")
        j = json.loads(out); self.assertEqual({p["name"] for p in j["presets"]} >= {"minimal", "dashboard", "column"}, True)
        self.assertTrue(all(p["origin"] == "shipped" and p["widgets"] > 0 and "description" in p for p in j["presets"]))
        code, out, _ = self.run_cli("preset", "show", "minimal")
        self.assertEqual(code, 0); self.assertIn('"clock"', out)
        # save current (2 widgets) as a user preset, apply minimal, then restore
        code, out, err = self.run_cli("preset", "save", "mine")
        self.assertEqual(code, 0, err)
        user = self.home / ".config" / "omarchy" / "desktop-widgets.presets" / "mine.jsonc"
        self.assertTrue(user.exists())
        self.assertEqual(self.run_cli("preset", "save", "mine")[0], 2)          # no overwrite without --force
        self.assertEqual(self.run_cli("preset", "save", "mine", "--force")[0], 0)
        code, out, err = self.run_cli("preset", "apply", "minimal")
        self.assertEqual(code, 0, err)
        cfg = json.loads(self.cfg.read_text())
        self.assertEqual([w["type"] for w in cfg["widgets"]], ["clock"]); self.assertEqual(cfg["widgets"][0]["scale"], 1.4)
        self.assertTrue(self.cfg.with_name("desktop-widgets.json.bak").exists())
        code, out, err = self.run_cli("preset", "apply", "mine")
        self.assertEqual(code, 0, err)
        self.assertEqual(len(json.loads(self.cfg.read_text())["widgets"]), 2)
        # user preset shadows a shipped name
        (user.parent / "minimal.jsonc").write_text('{"widgets": [{"type": "stats"}, {"type": "stats"}]}')
        code, out, _ = self.run_cli("preset", "list")
        self.assertIn("user", [l for l in out.splitlines() if l.startswith("minimal")][0])
        self.run_cli("preset", "apply", "minimal")
        self.assertEqual(len(json.loads(self.cfg.read_text())["widgets"]), 2)
        # errors
        self.assertEqual(self.run_cli("preset", "apply", "nope")[0], 2)
        self.assertEqual(self.run_cli("preset", "save", "Bad Name")[0], 2)
        (user.parent / "broken.jsonc").write_text('{"widgets": [{"type": "nope"}]}')
        self.assertEqual(self.run_cli("preset", "apply", "broken")[0], 1)
        code, out, _ = self.run_cli("preset", "list")
        self.assertIn("INVALID", [l for l in out.splitlines() if l.startswith("broken")][0])
        self.assertEqual(self.run_cli("preset", "remove", "mine")[0], 0); self.assertFalse(user.exists())
        self.assertEqual(self.run_cli("preset", "remove", "dashboard")[0], 2)  # shipped: never removed

    def test_shape_omits_common_and_list_shows_z(self):
        keys = [f["key"] for f in dw.fields_for("shape", dw.load_registry())]
        self.assertIn("kind", keys); self.assertIn("z", keys); self.assertNotIn("color", keys)
        code, out, err = self.run_cli("add", "shape", "--corner", "top-left", "--set", "z=-1", "--set", "width=300", "--set", "alpha=0.5")
        self.assertEqual(code, 0, err)
        code, out, _ = self.run_cli("list")
        self.assertEqual(code, 0)
        line = [l for l in out.splitlines() if "shape" in l][0]
        self.assertIn("z=-1", line); self.assertIn("rect 300", line); self.assertIn("background", line)
        self.assertEqual(self.run_cli("set", "0", "z=500")[0], 1)

    def test_registry_json_and_new_scaffold(self):
        code, out, _ = self.run_cli("registry", "--json")
        self.assertEqual(code, 0); self.assertIn("clock", json.loads(out)["types"])
        code, out, err = self.run_cli("new", "greeting")
        self.assertEqual(code, 0, err)
        d = self.home / ".config" / "omarchy" / "desktop-widgets.d" / "greeting"
        self.assertTrue((d / "type.json").exists() and (d / "Widget.qml").exists())
        self.assertIn("greeting", dw.load_registry()["types"])
        self.assertEqual(self.run_cli("new", "greeting")[0], 2)
        self.assertEqual(self.run_cli("new", "greeting", "--force")[0], 0)
        self.assertEqual(self.run_cli("new", "Bad")[0], 2)
        self.assertEqual(self.run_cli("new", "clock")[0], 2)

    def seed_omarchy_files(self, household=True, bindings="o.bind(\"SUPER + RETURN\", \"Terminal\", \"alacritty\")\n"):
        ext = self.home / ".config" / "omarchy" / "extensions"; ext.mkdir(parents=True, exist_ok=True)
        menu = ext / "omarchy-menu.jsonc"
        menu.write_text('{\n  // mine\n  "household": {"icon":"x","label":"Household"},\n  "household.vault": {"icon":"y","label":"Vault","action":"true"}\n}\n' if household
                        else '{\n  "learn": {"when":"false"}\n}\n')
        hypr = self.home / ".config" / "hypr"; hypr.mkdir(parents=True, exist_ok=True)
        (hypr / "bindings.lua").write_text(bindings)
        (self.home / ".local" / "bin").mkdir(parents=True, exist_ok=True)
        return menu, hypr / "bindings.lua"

    def test_install_is_idempotent_and_uninstall_restores(self):
        self.cfg.unlink()
        menu, binds = self.seed_omarchy_files()
        before_menu, before_binds = menu.read_text(), binds.read_text()
        code, out, err = self.run_cli("install")
        self.assertEqual(code, 0, err)
        link = self.home / ".local" / "bin" / "desktop-widgets"
        self.assertTrue(link.is_symlink()); self.assertEqual(os.path.realpath(link), os.path.realpath(ROOT / "bin" / "desktop-widgets"))
        self.assertTrue(self.cfg.exists())
        m = menu.read_text(); b = binds.read_text()
        self.assertIn("desktop-widgets:begin", m); self.assertIn('"style.widgets"', m); self.assertIn('"style.widgets.editor"', m)
        self.assertNotIn("household.widgets", m)   # Style is the default home even when Household exists
        self.assertIn("desktop-widgets:begin", b); self.assertIn("SUPER + ALT + W", b); self.assertIn("SUPER + ALT + A", b)
        self.assertIn('"household.vault"', m)   # untouched
        json.loads(dw.strip_jsonc(m))            # still valid JSONC
        self.assertTrue(menu.with_name(menu.name + ".desktop-widgets.bak").exists())
        code, out2, _ = self.run_cli("install")
        self.assertEqual(code, 0)
        self.assertEqual((menu.read_text(), binds.read_text()), (m, b))
        self.assertIn("already", out2)
        code, out3, err3 = self.run_cli("uninstall")
        self.assertEqual(code, 0, err3)
        self.assertFalse(link.exists())
        self.assertEqual(menu.read_text(), before_menu); self.assertEqual(binds.read_text(), before_binds)
        self.assertTrue(self.cfg.exists())       # config kept

    def test_install_without_household_and_existing_chord(self):
        menu, binds = self.seed_omarchy_files(household=False, bindings='o.bind("SUPER + ALT + W", "Something", "true")\n')
        code, out, err = self.run_cli("install", "--no-link")
        self.assertEqual(code, 0, err)
        m = menu.read_text(); b = binds.read_text()
        self.assertIn('"style.widgets": {', m); self.assertIn('"style.widgets.editor"', m); self.assertNotIn("household.widgets", m)
        json.loads(dw.strip_jsonc(m))
        self.assertEqual(b.count("SUPER + ALT + W"), 1); self.assertIn("SUPER + ALT + A", b)

    def test_install_menu_parent_override_and_hand_placed_rows(self):
        menu, _ = self.seed_omarchy_files()
        code, out, err = self.run_cli("install", "--no-link", "--no-keys", "--menu-parent", "household")
        self.assertEqual(code, 0, err)
        m = menu.read_text()
        self.assertIn('"household.widgets": {', m); self.assertIn('"household.widgets.arrange"', m); self.assertNotIn("style.widgets", m)
        json.loads(dw.strip_jsonc(m))
        code, out, _ = self.run_cli("install", "--no-link", "--no-keys", "--menu-parent", "")
        self.assertEqual(code, 0); self.assertIn("already", out)          # any *.widgets submenu counts as installed
        self.assertEqual(menu.read_text(), m)
        menu.write_text('{\n  "style.widgets": {"icon":"x","label":"Desktop widgets"}\n}\n')   # hand-placed, no markers
        code, out, _ = self.run_cli("install", "--no-link", "--no-keys")
        self.assertEqual(code, 0); self.assertIn("already", out)
        menu.write_text('{\n  "learn": {"when":"false"}\n}\n')
        code, out, err = self.run_cli("install", "--no-link", "--no-keys", "--menu-parent", "")
        self.assertEqual(code, 0, err); m = menu.read_text()
        self.assertIn('"widgets": {', m); self.assertIn('"widgets.editor"', m); self.assertNotIn('"style.widgets"', m)
        json.loads(dw.strip_jsonc(m))

    def test_init_refuses_overwrite_without_force(self):
        code, out, err = self.run_cli("init")
        self.assertEqual(code, 2); self.assertIn("exists", err)
        self.assertEqual(self.run_cli("init", "--force")[0], 0)
        self.assertIn('"type": "template"', self.cfg.read_text())
        self.assertTrue(self.cfg.with_name("desktop-widgets.json.bak").exists())

    def test_pet_expand_and_check(self):
        self.cfg.write_text(json.dumps({"widgets": [{"type": "pet", "sheet": "/nowhere/spritesheet.webp", "watch": "battery", "name": "jill"},
                                                    {"type": "pet", "sheet": "/nowhere/b.webp", "watch": "custom", "rules": [
                                                        {"kind": "range", "signal": "nope", "min": 1, "look": "failed"},
                                                        {"kind": "pet", "pet": "jill", "look": "failed", "then": "waving"}]}]}))
        code, out, err = self.run_cli("pet", "expand", "0")
        self.assertEqual(code, 0, err)
        w = json.loads(self.cfg.read_text())["widgets"][0]
        self.assertEqual(w["watch"], "custom"); self.assertEqual(w["rules"], dw.PET_WATCH["battery"])
        code, out, err = self.run_cli("pet", "expand", "0")
        self.assertEqual(code, 2); self.assertIn("already custom", err)
        code, out, _ = self.run_cli("pet", "check", "1")
        self.assertEqual(code, 0); self.assertIn("row 0: unknown signal 'nope'", out); self.assertNotIn("row 1", out)
        code, out, _ = self.run_cli("pet", "check", "--json")
        self.assertEqual(json.loads(out)["widgets"]["1"][0]["row"], 0)
        self.assertEqual(json.loads(out)["widgets"].get("0", []), [])

    def test_pet_check_null_widgets_and_bad_index(self):
        self.cfg.write_text(json.dumps({"widgets": None}))
        code, out, err = self.run_cli("pet", "check")
        self.assertEqual(code, 1)
        self.assertIn("ERROR   config must be a list of widgets or an object with a widgets list", err)
        self.cfg.write_text(json.dumps({"widgets": [
            {"type": "clock", "corner": "top-right"},
            {"type": "stats", "corner": "bottom-left", "enabled": False}]}))
        code, out, err = self.run_cli("pet", "check", "9")
        self.assertEqual(code, 2)

    def test_pets_looks_listing(self):
        pets = self.home / ".config" / "omarchy" / "desktop-widgets.pets" / "boba"; pets.mkdir(parents=True)
        (pets / "spritesheet.png").write_bytes(_png(1536, 1872, blank_cells={(4, c) for c in range(8)}))
        (pets / "pet.json").write_text(json.dumps({"id": "boba", "displayName": "Boba", "source": {"site": "petdex", "license": "CC0"}}))
        code, out, _ = self.run_cli("pets", "--looks", "boba")
        self.assertEqual(code, 0); self.assertIn("boba", out); self.assertIn("looks:", out); self.assertIn("idle", out)
        code, out, _ = self.run_cli("pets", "--json")
        p = [x for x in json.loads(out)["pets"] if x["slug"] == "boba"][0]
        self.assertEqual(p["license"], "CC0"); self.assertEqual(p["source"], "petdex")

    def test_pet_fetch_cli_add_and_widget(self):
        fx = ROOT / "tests" / "fixtures" / "petdex"
        pages = {"https://petdex.dev/install/boba": (fx / "install-curated.sh").read_bytes(),
                 "https://petdex.dev/pets/boba": b'<script type="application/ld+json">' + json.dumps({"@type": "CreativeWork", "license": "https://creativecommons.org/publicdomain/zero/1.0/"}).encode() + b'</script>',
                 "https://assets.petdex.dev/curated/boba/petjson-v2.json": json.dumps({"id": "boba", "displayName": "Boba", "spritesheetPath": "spritesheet.webp"}).encode(),
                 "https://assets.petdex.dev/curated/boba/sprite-v2.webp": _png(1536, 1872)}
        old = dw.HTTP_GET; dw.HTTP_GET = lambda url, headers=None, limit=None: pages[url]
        try:
            code, out, err = self.run_cli("pet", "fetch", "https://petdex.dev/pets/boba", "--json", "--add")
            self.assertEqual(code, 0, err); r = json.loads(out)
            self.assertEqual(r["slug"], "boba"); self.assertTrue(r["path"].startswith(str(self.home)))
            w = json.loads(self.cfg.read_text())["widgets"][-1]
            self.assertEqual((w["type"], w["name"], w["sheet"]), ("pet", "boba", str(self.home / ".config" / "omarchy" / "desktop-widgets.pets" / "boba" / "spritesheet.webp")))
            code, out, err = self.run_cli("pet", "fetch", "boba", "--replace", "--widget", "0")
            self.assertEqual(code, 2); self.assertIn("not a pet", err)                      # widget 0 is the clock
            code, out, err = self.run_cli("pet", "fetch", "boba", "--replace", "--widget", "2")
            self.assertEqual(code, 0, err); w2 = json.loads(self.cfg.read_text())["widgets"][2]
            self.assertEqual((w2["type"], w2["name"], w2["sheet"].endswith("boba/spritesheet.webp")), ("pet", "boba", True))
            code, out, err = self.run_cli("pet", "fetch", "https://evil.dev/x")
            self.assertEqual(code, 2); self.assertIn("petdex", err)
        finally:
            dw.HTTP_GET = old


class Petdex(unittest.TestCase):
    FX = ROOT / "tests" / "fixtures" / "petdex"

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = pathlib.Path(self.tmp.name) / "pets"
        self.sheet = _png(1536, 1872, blank_cells={(4, c) for c in range(8)})
        self.pages = {
            "https://petdex.dev/install/boba": (self.FX / "install-curated.sh").read_bytes(),
            "https://petdex.dev/install/cat-sam": (self.FX / "install-community.sh").read_bytes(),
            "https://petdex.dev/install/badhost": (self.FX / "install-badhost.sh").read_bytes(),
            "https://petdex.dev/install/missing": (self.FX / "install-missing.sh").read_bytes(),
            "https://petdex.dev/pets/boba": b'<html><head><script type="application/ld+json">' + json.dumps([
                {"@context": "https://schema.org", "@type": "CreativeWork", "@id": "https://petdex.dev/pets/boba#pet", "name": "Boba", "license": "https://creativecommons.org/publicdomain/zero/1.0/"},
                {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": []},
            ]).encode() + b'</script></head><body></body></html>',
            "https://petdex.dev/pets/cat-sam": b'<html><head><script type="application/ld+json">' + json.dumps(
                {"@context": "https://schema.org", "@type": "CreativeWork", "name": "Cat Sam", "license": "https://creativecommons.org/licenses/by-nc/4.0/"}
            ).encode() + b'</script></head><body></body></html>',
            "https://assets.petdex.dev/curated/boba/petjson-v2.json": json.dumps({"id": "boba", "displayName": "Boba", "description": "tea", "spritesheetPath": "spritesheet.webp"}).encode(),
            "https://assets.petdex.dev/curated/boba/sprite-v2.webp": self.sheet,
            "https://assets.petdex.dev/pets/cat-sam-9f3a1c/petjson.json": json.dumps({"id": "cat-sam", "displayName": "Cat Sam", "spritesheetPath": "spritesheet.webp"}).encode(),
            "https://assets.petdex.dev/pets/cat-sam-9f3a1c/sprite.webp": _png(1536, 2288),
        }
        self.calls = []
        def http(url, headers=None, limit=None):
            self.calls.append(url)
            if url == "https://petdex.dev/install/nope": raise dw.FetchError(3, "not on petdex")
            if url not in self.pages: raise dw.FetchError(4, "network: " + url)
            return self.pages[url]
        self.http = http

    def tearDown(self): self.tmp.cleanup()

    def test_slug_normalisation(self):
        for t in ("boba", "petdex.dev/pets/boba", "https://petdex.dev/pets/boba/", "https://petdex.dev/en/pets/boba", "https://petdex.dev/install/boba", "https://www.petdex.dev/pets/boba"):
            self.assertEqual(dw.petdex_slug(t), "boba", t)
        for bad in ("https://evil.dev/pets/boba", "http://petdex.dev/pets/boba", "petdex.dev/collections/x", "../boba", "Bo ba", "", "https://petdex.dev/pets/../etc"):
            with self.assertRaises(ValueError, msg=bad): dw.petdex_slug(bad)

    def test_parse_install_script(self):
        m = dw.parse_install_script((self.FX / "install-curated.sh").read_text())
        self.assertEqual(m, {"petjson": "https://assets.petdex.dev/curated/boba/petjson-v2.json", "sheet": "https://assets.petdex.dev/curated/boba/sprite-v2.webp", "displayName": "Boba"})
        self.assertEqual(dw.parse_install_script((self.FX / "install-community.sh").read_text())["displayName"], "Cat Sam")
        for f in ("install-badhost.sh", "install-missing.sh", "install-404.sh"):
            with self.assertRaises(ValueError, msg=f): dw.parse_install_script((self.FX / f).read_text())

    def test_petdex_license_reads_json_ld_only(self):
        self.assertEqual(dw.petdex_license("<b>CC-BY-SA</b>"), "unknown")   # free text is never trusted
        self.assertEqual(dw.petdex_license("nothing"), "unknown")
        cc0 = '<script type="application/ld+json">' + json.dumps({"@context": "https://schema.org", "@type": "CreativeWork", "license": "https://creativecommons.org/publicdomain/zero/1.0/"}) + '</script>'
        self.assertEqual(dw.petdex_license(cc0), "CC0")
        by = '<script type="application/ld+json">' + json.dumps({"@type": "CreativeWork", "license": "cc-by"}) + '</script>'
        self.assertEqual(dw.petdex_license(by), "CC-BY")
        null_lic = '<script type="application/ld+json">' + json.dumps({"@type": "CreativeWork", "license": None}) + '</script>'
        self.assertEqual(dw.petdex_license(null_lic), "unknown")
        listed = '<script type="application/ld+json">' + json.dumps([
            {"@context": "https://schema.org", "@type": "CreativeWork", "name": "Boba", "license": "https://creativecommons.org/licenses/by-nc/4.0/"},
            {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": []},
        ]) + '</script>'
        self.assertEqual(dw.petdex_license(listed), "CC-BY-NC")

    def test_fetch_curated_and_community(self):
        r = dw.fetch_pet("https://petdex.dev/pets/boba", str(self.root), self.http)
        self.assertEqual((r["slug"], r["name"], r["license"], r["rows"]), ("boba", "Boba", "CC0", 9))
        self.assertEqual(r["path"], str(self.root / "boba")); self.assertTrue((self.root / "boba" / "spritesheet.webp").exists())
        meta = json.loads((self.root / "boba" / "pet.json").read_text())
        self.assertEqual(meta["source"]["site"], "petdex"); self.assertEqual(meta["source"]["url"], "https://petdex.dev/pets/boba"); self.assertEqual(meta["source"]["license"], "CC0"); self.assertIn("fetchedAt", meta["source"])
        self.assertTrue(any(u.startswith("https://petdex.dev/pets/boba") for u in self.calls))
        r2 = dw.fetch_pet("cat-sam", str(self.root), self.http)
        self.assertEqual((r2["rows"], r2["license"]), (11, "CC-BY-NC")); self.assertIn("extra", " ".join(l["name"] for l in r2["looks"]))

    def test_fetch_failures(self):
        with self.assertRaises(dw.FetchError) as cm: dw.fetch_pet("https://evil.dev/pets/boba", str(self.root), self.http)
        self.assertEqual(cm.exception.code, 2)
        with self.assertRaises(dw.FetchError) as cm: dw.fetch_pet("nope", str(self.root), self.http)
        self.assertEqual(cm.exception.code, 3)
        with self.assertRaises(dw.FetchError) as cm: dw.fetch_pet("badhost", str(self.root), self.http)
        self.assertEqual(cm.exception.code, 5)
        with self.assertRaises(dw.FetchError) as cm: dw.fetch_pet("missing", str(self.root), self.http)
        self.assertEqual(cm.exception.code, 5)
        self.pages["https://assets.petdex.dev/curated/boba/sprite-v2.webp"] = _png(1000, 1000)
        with self.assertRaises(dw.FetchError) as cm: dw.fetch_pet("boba", str(self.root), self.http)
        self.assertEqual(cm.exception.code, 5); self.assertFalse((self.root / "boba").exists()); self.assertEqual([p for p in self.root.iterdir()] if self.root.exists() else [], [])
        self.pages["https://assets.petdex.dev/curated/boba/sprite-v2.webp"] = self.sheet
        dw.fetch_pet("boba", str(self.root), self.http)
        with self.assertRaises(dw.FetchError) as cm: dw.fetch_pet("boba", str(self.root), self.http)
        self.assertEqual(cm.exception.code, 6)
        self.assertEqual(dw.fetch_pet("boba", str(self.root), self.http, replace=True)["slug"], "boba")

    def test_fetch_size_cap(self):
        big = b"x" * (dw.PETDEX_MAX_BYTES + 1)
        with self.assertRaises(dw.FetchError) as cm: dw._check_size(big)
        self.assertEqual(cm.exception.code, 5)


class PetRules(unittest.TestCase):
    RULES = ROOT / "tests" / "fixtures" / "rules"

    def test_presets_equal_shared_fixture(self):
        self.assertEqual(dw.PET_WATCH, json.loads((self.RULES / "presets.json").read_text()))

    def test_compile_matches_shared_fixture(self):
        fx = json.loads((self.RULES / "compile-basic.json").read_text())
        got = json.loads(json.dumps(dw.compile_rules(fx["rows"])))
        self.assertEqual(got, fx["expect"])

    def test_validate_matches_shared_fixture(self):
        fx = json.loads((self.RULES / "validate-basic.json").read_text())
        self.assertEqual(dw.validate_rules(fx["rows"], fx["ctx"]), fx["expect"])
        self.assertEqual(dw.validate_rules(fx["rows"][:2], {"looks": None, "signals": None, "pets": None}), [])
        self.assertEqual(dw.validate_rules("nope", fx["ctx"]), [])

    def test_tokenize_and_parse_match_js_errors(self):
        self.assertEqual(dw.tokenize_expr("cpu >= 95 && !(a ~ 'x')"), ["cpu", ">=", "95", "&&", "!", "(", "a", "~", "'x'", ")"])
        with self.assertRaises(ValueError) as cm: dw.tokenize_expr("cpu $ 3")
        self.assertEqual(str(cm.exception), "bad token near ' $ 3'")
        self.assertEqual(dw.check_expr("pets.jill.state == 'failed' && cpu > 1"), ["pets.jill.state", "cpu"])
        for src, msg in (("cpu >> 3", "unexpected '3'"), ("(cpu > 1", "missing )"), ("cpu >", "unexpected end"), ("cpu > 1 2", "unexpected '2'")):
            with self.assertRaises(ValueError) as cm: dw.check_expr(src)
            self.assertEqual(str(cm.exception), msg, src)

    def test_unique_names_matches_js(self):
        cfgs = [
            {"type": "pet", "sheet": "/p/teto/spritesheet.webp"},
            {"type": "clock"},
            {"type": "pet", "sheet": "/q/teto/spritesheet.webp"},
            {"type": "pet", "name": "teto"},
            {"type": "pet", "name": "Jill"},
            {"type": "pet", "name": "teto", "enabled": False},
        ]
        self.assertEqual(dw.unique_names(cfgs), ["teto", None, "teto_2", "teto_3", "jill", None])


class SheetProbe(unittest.TestCase):
    def test_image_geometry_headers(self):
        self.assertEqual(dw.image_geometry(_png(1536, 1872)[:64]), ("png", 1536, 1872))
        vp8x = b"RIFF" + struct.pack("<I", 100) + b"WEBPVP8X" + struct.pack("<I", 10) + b"\x10\x00\x00\x00" + (1535).to_bytes(3, "little") + (1871).to_bytes(3, "little")
        self.assertEqual(dw.image_geometry(vp8x), ("webp", 1536, 1872))
        vp8l = b"RIFF" + struct.pack("<I", 100) + b"WEBPVP8L" + struct.pack("<I", 10) + b"\x2f" + struct.pack("<I", (1535) | ((1871) << 14))
        self.assertEqual(dw.image_geometry(vp8l), ("webp", 1536, 1872))
        vp8 = b"RIFF" + struct.pack("<I", 100) + b"WEBPVP8 " + struct.pack("<I", 10) + b"\x00\x00\x00\x9d\x01\x2a" + struct.pack("<HH", 1536, 1872)
        self.assertEqual(dw.image_geometry(vp8), ("webp", 1536, 1872))
        self.assertIsNone(dw.image_geometry(b"GIF89a")); self.assertIsNone(dw.image_geometry(b""))

    def test_sheet_looks_geometry_and_pixels(self):
        d = pathlib.Path(tempfile.mkdtemp()); p = d / "spritesheet.png"; p.write_bytes(_png(1536, 1872, blank_cells={(4, c) for c in range(8)} | {(0, 6), (0, 7)}))
        info = dw.sheet_looks(str(p))
        self.assertEqual(info["rows"], 9); names = [l["name"] for l in info["looks"]]
        self.assertEqual(names, ["idle", "running", "waving", "jumping", "failed", "waiting", "review"])
        if info["measured"]:
            by = {l["name"]: l for l in info["looks"]}
            self.assertFalse(by["jumping"]["present"]); self.assertEqual(by["idle"]["frames"], 6); self.assertTrue(by["running"]["present"])
        else:
            self.assertTrue(all(l["present"] for l in info["looks"]))
        self.assertIsNone(dw.sheet_looks(str(d / "missing.png")))
        (d / "bad.png").write_bytes(_png(1000, 1000)); self.assertIsNone(dw.sheet_looks(str(d / "bad.png")))


if __name__ == "__main__":
    unittest.main()


class Kit(unittest.TestCase):
    """Kit contract (Python twin of tests/kit.test.js): the surface a drop-in is written against
    must survive until the registry's `api` is bumped and a new fixture added."""
    MANIFEST = json.loads((ROOT / "manifest.json").read_text())
    FIXTURE = ROOT / "tests" / "fixtures" / "kit" / f"api-{REGISTRY['api']}.json"

    def fx(self):
        self.assertTrue(self.FIXTURE.exists(), f"missing {self.FIXTURE}: a new api number needs a new fixture")
        fx = json.loads(self.FIXTURE.read_text()); self.assertEqual(fx["api"], REGISTRY["api"]); return fx

    def test_kit_files_declare_surface(self):
        import re as _re
        fx = self.fx()
        for file, want in fx["files"].items():
            qml = (ROOT / "widgets" / file).read_text()
            props = _re.findall(r"^\s*(?:readonly\s+)?(?:default\s+)?property\s+\S+\s+(\w+)", qml, _re.M)
            funcs = _re.findall(r"function\s+(\w+)\s*\(", qml)
            for p in want["properties"]: self.assertIn(p, props, f"{file}: property {p} gone")
            for f in want["functions"]: self.assertIn(f, funcs, f"{file}: function {f} gone")

    def test_import_path_and_injection(self):
        fx = self.fx()
        hello = (ROOT / "examples" / "drop-in" / "hello" / "Widget.qml").read_text()
        self.assertIn(f'import "{fx["importPath"]}"', hello)
        parts = fx["importPath"].split("/")
        self.assertEqual(parts[-2], self.MANIFEST["id"]); self.assertTrue((ROOT / parts[-1]).is_dir())
        service = (ROOT / "Service.qml").read_text()
        for p in fx["injected"]: self.assertIn(f"item.{p} = ", service, f"Service.qml no longer injects {p}")

    def test_field_types_validated_and_covered(self):
        import inspect
        fx = self.fx()
        body = inspect.getsource(dw._check_field)
        for t in fx["fieldTypes"]: self.assertIn(f'"{t}"', body, f"_check_field no longer handles {t}")
        used = {f["type"] for f in REGISTRY["common"]} | {f["type"] for t in REGISTRY["types"].values() for f in t.get("fields", [])}
        self.assertEqual(used - {"type", "petdex"} - set(fx["fieldTypes"]), set(), "registry field types missing from the contract")

    def test_qmllint_shipped_widgets(self):
        import shutil, subprocess as sp
        exe = shutil.which("qmllint") or "/usr/lib/qt6/bin/qmllint"
        if not os.path.exists(exe) or not sp.run([exe, "--version"], capture_output=True, text=True).stdout.startswith("qmllint 6"):
            exe = "/usr/lib/qt6/bin/qmllint"
        if not os.path.exists(exe): self.skipTest("Qt6 qmllint not installed")
        files = [ROOT / "examples" / "drop-in" / "hello" / "Widget.qml", ROOT / "Service.qml", ROOT / "Editor.qml", ROOT / "Companion.qml"]
        files += sorted((ROOT / "widgets").glob("*.qml")) + sorted((ROOT / "editor").glob("*.qml")) + sorted((ROOT / "arrange").glob("*.qml"))
        for f in files:
            with self.subTest(f.name):
                r = sp.run([exe, str(f)], capture_output=True, text=True)   # syntax errors exit non-zero; unresolved shell imports only warn
                self.assertEqual(r.returncode, 0, r.stdout[-800:] + r.stderr[-800:])


class Ext(CliCase):
    """`desktop-widgets ext`: drop-ins shared as git repos."""
    def make_repo(self, name="wani", requires=None, qml="WidgetCard {}"):
        src = self.home / "src" / name; src.mkdir(parents=True)
        spec = {"displayName": name.title(), "fields": [{"key": "n", "type": "integer", "label": "N", "default": 1}]}
        if requires is not None: spec["requires"] = requires
        (src / "type.json").write_text(json.dumps(spec)); (src / "Widget.qml").write_text(qml)
        for argv in (["init", "-q"], ["add", "."], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "one"]):
            self.assertEqual(dw.git(argv, cwd=str(src))[0], 0, argv)
        return src

    def bump(self, src, msg="two"):
        (src / "Widget.qml").write_text(f"WidgetCard {{ }}  // {msg}")
        self.assertEqual(dw.git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", msg], cwd=str(src))[0], 0)

    def dropin(self, name): return self.home / ".config" / "omarchy" / "desktop-widgets.d" / name

    def test_ext_name(self):
        for url, want in (("https://x/y/wani.git", "wani"), ("git@x:y/Wani-Kani/", "wani-kani"), ("/tmp/a/b", "b"), ("https://x/y/dw.git/", "dw")):
            self.assertEqual(dw.ext_name(url), want)
        for bad in ("https://x/Bad_Name", "https://x/", "", "-"): self.assertRaises(ValueError, dw.ext_name, bad)

    def test_ext_list_shows_local_and_git(self):
        self.write_dropin("hello")
        code, out, err = self.run_cli("ext", "list", "--json")
        self.assertEqual(code, 0, err)
        rows = json.loads(out); self.assertEqual([r["name"] for r in rows], ["hello"])
        self.assertEqual((rows[0]["origin"], rows[0]["commit"], rows[0]["inUse"], rows[0]["api"]), ("local", None, 0, None))
        src = self.make_repo("wani", requires={"api": 1}); self.assertEqual(self.run_cli("ext", "add", str(src))[0], 0)
        self.run_cli("add", "wani")
        rows = {r["name"]: r for r in json.loads(self.run_cli("ext", "list", "--json")[1])}
        self.assertEqual((rows["wani"]["origin"], rows["wani"]["inUse"], rows["wani"]["api"]), (str(src), 1, 1))
        self.assertEqual(len(rows["wani"]["commit"]), 7)
        code, out, _ = self.run_cli("ext", "list"); self.assertEqual(code, 0); self.assertIn("wani", out); self.assertIn("hello", out)

    def test_ext_add_clones_validates_and_reports(self):
        src = self.make_repo("wani", requires={"api": 1})
        code, out, err = self.run_cli("ext", "add", str(src))
        self.assertEqual(code, 0, err)
        d = self.dropin("wani")
        self.assertTrue((d / ".git").is_dir() and (d / "type.json").exists())
        self.assertIn("wani", out); self.assertIn("api 1", out); self.assertIn("n", out); self.assertIn("desktop-widgets add wani", out)
        self.assertIn("wani", dw.load_registry()["types"])
        self.assertEqual(self.run_cli("ext", "add", str(src))[0], 6)            # exists
        self.assertEqual(self.run_cli("ext", "add", str(src), "clock")[0], 2)   # built-in name
        self.assertEqual(self.run_cli("ext", "add", str(src), "Bad")[0], 2)
        self.assertEqual(self.run_cli("ext", "add", "-oops")[0], 2)
        self.assertEqual(self.run_cli("ext", "add", str(self.home / "nope"))[0], 4)   # clone failed
        self.assertFalse(self.dropin("nope").exists())
        code, out, _ = self.run_cli("ext", "add", str(src), "second", "--json"); self.assertEqual(code, 0)
        self.assertEqual(json.loads(out)["name"], "second")

    def test_ext_add_rejects_invalid_and_warns_on_api(self):
        src = self.make_repo("broken"); (src / "type.json").write_text("{ nope")
        dw.git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "break"], cwd=str(src))
        code, _, err = self.run_cli("ext", "add", str(src))
        self.assertEqual(code, 5); self.assertIn("type.json", err)
        self.assertFalse(self.dropin("broken").exists())
        fut = self.make_repo("future", requires={"api": 99})
        code, out, err = self.run_cli("ext", "add", str(fut))
        self.assertEqual(code, 0); self.assertIn("wants api 99, plugin provides 1", err); self.assertTrue(self.dropin("future").exists())

    def test_ext_update_pulls_and_reports(self):
        src = self.make_repo("wani"); self.assertEqual(self.run_cli("ext", "add", str(src))[0], 0)
        self.write_dropin("hello")   # no .git: listed as skipped, not an error
        self.assertEqual(self.run_cli("add", "wani")[0], 0)
        code, out, _ = self.run_cli("ext", "update"); self.assertEqual(code, 0); self.assertIn("wani", out); self.assertIn("up to date", out)
        self.assertNotIn("restart shell", out)
        self.bump(src)
        code, out, _ = self.run_cli("ext", "update", "wani"); self.assertEqual(code, 0)
        self.assertIn("updated", out); self.assertIn("restart shell", out)
        self.assertIn("// two", (self.dropin("wani") / "Widget.qml").read_text())
        self.assertEqual(self.run_cli("ext", "update", "nope")[0], 2)
        self.assertEqual(self.run_cli("ext", "update", "hello")[0], 2)   # not a git checkout
        (self.dropin("wani") / "Widget.qml").write_text("local edit")
        self.bump(src, "three")
        code, out, err = self.run_cli("ext", "update", "wani"); self.assertEqual(code, 4); self.assertIn("wani", err)

    def test_ext_remove_refuses_in_use_unless_forced(self):
        src = self.make_repo("wani"); self.run_cli("ext", "add", str(src))
        self.run_cli("add", "wani"); self.run_cli("add", "wani")
        code, _, err = self.run_cli("ext", "remove", "wani"); self.assertEqual(code, 2); self.assertIn("2 widget", err); self.assertIn("--force", err)
        self.assertTrue(self.dropin("wani").exists())
        code, out, err = self.run_cli("ext", "remove", "wani", "--force"); self.assertEqual(code, 0, err)
        self.assertFalse(self.dropin("wani").exists())
        self.assertEqual([w["type"] for w in json.loads(self.cfg.read_text())["widgets"]], ["clock", "stats"])
        self.assertTrue(self.cfg.with_suffix(".json.bak").exists())
        self.assertEqual(self.run_cli("ext", "remove", "nope")[0], 2)
        self.assertEqual(self.run_cli("ext", "remove", "clock")[0], 2)
        self.write_dropin("hello"); self.assertEqual(self.run_cli("ext", "remove", "hello")[0], 0); self.assertFalse(self.dropin("hello").exists())
