# Desktop Widgets Phase 3c: Drop-in Custom Widget Types — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone can add a widget *type* without forking the plugin: a folder under `~/.config/omarchy/desktop-widgets.d/<name>/` holding `type.json` (its fields, registry-style) and `Widget.qml` (the same contract the built-in widgets use). The CLI, the validator, the service and the editor all learn about it automatically.

**Architecture:** The CLI becomes the one place the registry is assembled: `load_registry()` merges `widgets/registry.json` with every valid drop-in and stamps each drop-in type with `source` (absolute path to its `Widget.qml`) and `dropIn: true`. `desktop-widgets registry --json` prints the merged registry; the service runs that at startup, on every config reload and on IPC `rescan`, falling back to the built-in file if the CLI is unavailable. The service's Loader uses `registry.types[type].source` for any type without a built-in file. `desktop-widgets new <name>` scaffolds a working drop-in from a template.

**Author contract:** `Widget.qml` is `WidgetCard { ... }` exactly like `widgets/ClockWidget.qml`, importing the plugin's widget kit through a path that is stable on every `omarchy plugin add` install: `import "../../plugins/homelab.desktop-widgets/widgets"`. `config` is injected; `textColor`, `mutedColor`, `outlineColor`, `halo`, `scale_` come from the card; `WidgetText` gives outlined text.

**Spec:** `docs/ROADMAP.md` → Phase 3 "New parts without QML", route 2.

## Status (handoff block — update after every task)

**PHASE 3c COMPLETE 2026-09-10.** Phase 3 is done in full (3a drag-to-place, 3b template, 3c drop-ins). Next: Phase 4 (share it) — awaits Michael's go + public handle (DQ-025). Human checks still owed: a real mouse drag; a hand-built drop-in beyond the scaffold.

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 CLI: merged registry (drop-ins), `registry --json`, `types` marks drop-ins, `new <name>` scaffold, tests | done | 8a09269 | 21 python tests |
| 2 Service: registry from CLI + fallback, Loader `source`, IPC `rescan`; live drop-in | done | e81a9f6 | hello drop-in rendered live without a restart; registry refreshed before validation on reload |
| 3 Docs (README, example), vault, status | done | 173887d | |

**How to resume:** read this file; run `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -p 'test_*.py'`; continue at the first task not done. Code changes need `omarchy restart shell`. A *new* drop-in loads without a restart (its QML was never cached); *editing* an existing drop-in needs one.

## Global Constraints

- Same as earlier phases. A broken drop-in (bad `type.json`, missing `Widget.qml`, bad name) is reported by `desktop-widgets types` and skipped; it never stops the built-ins.
- Drop-in names: `^[a-z][a-z0-9-]{0,39}$`, must not shadow a built-in type (built-in wins, drop-in reported).
- `type.json` keys: `displayName` (optional), `description` (optional), `fields` (array, registry field objects; common fields are added automatically, so only type-specific ones go here).

---

### Task 1: CLI

**Files:** Modify `bin/desktop-widgets`, `tests/test_cli.py`; Create `examples/drop-in/hello/type.json`, `examples/drop-in/hello/Widget.qml` (used by `new` as the template and as documentation).

**Interfaces:**
- `dropin_dir() -> str` (`$XDG_CONFIG_HOME/omarchy/desktop-widgets.d`).
- `load_dropins(dir) -> (types: dict, problems: list[str])`.
- `load_registry(path=REGISTRY_PATH, dropins=True) -> dict` with `registry["problems"]` (list) when any.
- CLI: `registry [--json]`, `types` shows `(drop-in)` and problems, `new <name> [--force]`.

- [ ] **Step 1: tests** (append to `Cli`)

```python
    def write_dropin(self, name, type_json='{"displayName":"Hello","fields":[{"key":"name","type":"string","label":"Name","default":"world"}]}', qml="WidgetCard {}"):
        d = self.home / ".config" / "omarchy" / "desktop-widgets.d" / name
        d.mkdir(parents=True, exist_ok=True)
        if type_json is not None: (d / "type.json").write_text(type_json)
        if qml is not None: (d / "Widget.qml").write_text(qml)
        return d

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

    def test_registry_json_and_new_scaffold(self):
        code, out, _ = self.run_cli("registry", "--json")
        self.assertEqual(code, 0); self.assertIn("clock", json.loads(out)["types"])
        code, out, err = self.run_cli("new", "greeting")
        self.assertEqual(code, 0, err)
        d = self.home / ".config" / "omarchy" / "desktop-widgets.d" / "greeting"
        self.assertTrue((d / "type.json").exists() and (d / "Widget.qml").exists())
        self.assertIn("greeting", dw.load_registry()["types"])
        self.assertEqual(self.run_cli("new", "greeting")[0], 2)          # exists
        self.assertEqual(self.run_cli("new", "greeting", "--force")[0], 0)
        self.assertEqual(self.run_cli("new", "Bad")[0], 2)
        self.assertEqual(self.run_cli("new", "clock")[0], 2)             # built-in
```

- [ ] **Step 2: run → fails.**
- [ ] **Step 3: implement** in `bin/desktop-widgets`:

```python
import re
DROPIN_NAME = re.compile(r"^[a-z][a-z0-9-]{0,39}$")
EXAMPLE_DIR = os.path.join(PLUGIN_DIR, "examples", "drop-in", "hello")


def dropin_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "omarchy", "desktop-widgets.d")


def load_dropins(directory, builtin_types):
    types, problems = {}, []
    if not os.path.isdir(directory): return types, problems
    for name in sorted(os.listdir(directory)):
        d = os.path.join(directory, name)
        if not os.path.isdir(d): continue
        if not DROPIN_NAME.match(name): problems.append(f"{name}: name must match {DROPIN_NAME.pattern}"); continue
        if name in builtin_types: problems.append(f"{name}: shadows a built-in type, ignored"); continue
        tj, qml = os.path.join(d, "type.json"), os.path.join(d, "Widget.qml")
        if not os.path.exists(tj): problems.append(f"{name}: missing type.json"); continue
        if not os.path.exists(qml): problems.append(f"{name}: missing Widget.qml"); continue
        try:
            with open(tj) as fh: spec = json.loads(strip_jsonc(fh.read()))
        except (OSError, ValueError) as e:
            problems.append(f"{name}: type.json: {e}"); continue
        if not isinstance(spec, dict) or not isinstance(spec.get("fields", []), list):
            problems.append(f"{name}: type.json must be an object with a fields list"); continue
        types[name] = {"displayName": spec.get("displayName", name), "description": spec.get("description", ""),
                       "fields": spec.get("fields", []), "source": qml, "dropIn": True}
    return types, problems


def load_registry(path=REGISTRY_PATH, dropins=True):
    with open(path) as fh:
        reg = json.load(fh)
    if dropins:
        extra, problems = load_dropins(dropin_dir(), reg.get("types", {}))
        reg["types"].update(extra)
        if problems: reg["problems"] = problems
    return reg
```

`cmd_types`: append ` (drop-in)` after the display name for entries with `dropIn`, print `problems` to stderr as `PROBLEM <text>` lines. `cmd_registry`: `print(json.dumps(ctx["registry"]))` with `--json`, else a short table. `cmd_new`:

```python
def cmd_new(args, ctx):
    name = args.name
    if not DROPIN_NAME.match(name): print(f"name must match {DROPIN_NAME.pattern}", file=sys.stderr); return 2
    builtin = load_registry(dropins=False)["types"]
    if name in builtin: print(f"'{name}' is a built-in type; pick another name", file=sys.stderr); return 2
    d = os.path.join(dropin_dir(), name)
    if os.path.exists(d) and not args.force: print(f"{d} exists (use --force to overwrite)", file=sys.stderr); return 2
    os.makedirs(d, exist_ok=True)
    for fn in ("type.json", "Widget.qml"):
        with open(os.path.join(EXAMPLE_DIR, fn)) as src: text = src.read()
        text = text.replace("Hello", name.replace("-", " ").title()).replace("hello", name)
        with open(os.path.join(d, fn), "w") as dst: dst.write(text)
    print(f"created {d}\n  edit type.json (fields) and Widget.qml, then:\n  desktop-widgets add {name}\n  (editing an existing drop-in later needs: omarchy restart shell)")
    return 0
```

Parser: `sub.add_parser("registry", ...)` with `--json`; `n = sub.add_parser("new", help="scaffold a drop-in widget type"); n.add_argument("name"); n.add_argument("--force", action="store_true")`.

`main()` builds `ctx["registry"]` with drop-ins; tests that `import` the module call `dw.load_registry()` directly.

- [ ] **Step 4: the example** `examples/drop-in/hello/`:

`type.json`
```json
{
  "displayName": "Hello",
  "description": "A greeting — the smallest possible drop-in widget.",
  "fields": [
    { "key": "name", "type": "string", "label": "Name", "default": "world" },
    { "key": "shout", "type": "boolean", "label": "Shout", "default": false }
  ]
}
```

`Widget.qml`
```qml
import QtQuick
import qs.Commons
// The plugin's widget kit: WidgetCard (frame, colours, outline) and WidgetText.
// This relative path is the same on every `omarchy plugin add` install.
import "../../plugins/homelab.desktop-widgets/widgets"

// Drop-in widget "hello". `config` is injected with your type.json fields
// (defaults applied) plus the common keys. Use root.textColor / mutedColor /
// outlineColor / halo / scale_ so it follows the theme and the config.
WidgetCard {
  id: root
  readonly property string name: String(config.name || "world")
  readonly property bool shout: config.shout === true

  Column {
    spacing: Math.round(Style.space(2) * root.scale_)
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: root.shout ? ("HELLO, " + root.name.toUpperCase() + "!") : ("hello, " + root.name)
      color: root.textColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.heading * root.scale_)
    }
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: "drop-in widget · edit ~/.config/omarchy/desktop-widgets.d/hello/"
      color: root.mutedColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.caption * root.scale_)
    }
  }
}
```

- [ ] **Step 5: tests pass (both suites); commit** `"CLI: drop-in widget types merged into the registry; registry --json; new <name> scaffold"`.

---

### Task 2: Service

**Files:** Modify `Service.qml`.

- Replace the registry `FileView` with a `Process` running `[cliPath, "registry", "--json"]` (StdioCollector → `JSON.parse` → `registry`), started at `Component.onCompleted`, re-run on every config reload (`applyConfig` start) and on IPC `rescan`. On non-zero exit or parse failure: log and load `widgets/registry.json` via the existing FileView as a fallback (keep the FileView but `blockLoading: false`, only triggered on fallback).
- Loader `source`: `default: return t && t.source ? "file://" + t.source : ""` where `t = root.registry.types[type]`.
- IPC: `function rescan(): string { root.loadRegistry(); return "ok" }`.
- Log `problems` from the registry once per load.
- Live: `desktop-widgets new hello`, `desktop-widgets add hello --corner top-left --y 220 --set name=sir`, the widget appears (no restart); `desktop-widgets types` lists it; editor Add dropdown lists "Hello"; `omarchy-shell desktop-widgets state`.
- Commit `"Service: registry assembled by the CLI (drop-ins), Loader source for drop-in types, rescan IPC"`.

---

### Task 3: Docs

- README "Drop-in widget types" section: the contract, the scaffold command, the relative import, the restart rule, the problems report; link the example. Vault guide section; memory; board; DQ-025 tick; this plan's status.
- Commit `"Drop-in widget types: docs — Phase 3c complete"`; push.
