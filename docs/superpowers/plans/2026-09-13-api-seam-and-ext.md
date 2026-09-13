# Versioned kit API + drop-in distribution — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the drop-in kit a version number (`api`) that drop-ins can `requires`, a contract test that stops a core change from silently breaking that surface, and `desktop-widgets ext add|update|list|remove` so a drop-in folder can be shared as a git repo.

**Architecture:** `widgets/registry.json` carries `"api": 1`; the CLI merges each drop-in's `requires` into the registry and turns a mismatch into a *warning* (the drop-in still loads), which `types`, `validate`, `registry` and the service log all surface. A fixture `tests/fixtures/kit/api-1.json` describes the kit surface; both suites parse the QML/registry with regexes and fail if a listed property, function, import path or field type disappears. `ext` verbs are thin wrappers around `git` in `bin/desktop-widgets`; removal goes through the existing `mutate`/`commit` writer.

**Tech Stack:** Python 3 stdlib (CLI), node:test, QML regex checks, `git`, optional Qt6 `qmllint`.

**Spec:** `docs/ROADMAP.md` § "Backlog additions" item 8 (Michael, 2026-09-13).

## Global Constraints

- Registry first; QML reads `config.<key>` only.
- One writer: every config change goes through `commit` (validated, atomic, `.bak`).
- A broken drop-in is reported and skipped, never fatal; an `api` mismatch is a warning, never a skip.
- No hard-coded `$HOME`, hostnames or colours in core files.
- Nothing from a cloned repo runs except its `Widget.qml` (git never executes repo content on clone/pull).
- Both suites green before every commit: `node --test tests/*.test.js` and `python3 -m unittest discover -s tests`.
- Branch `feat/api-seam`; merge `--no-ff`; version/tag only at release (Michael's word).

## Status

| task | state |
|---|---|
| 1 api number in registry + CLI output | DONE |
| 2 `requires` in type.json → warning | DONE |
| 3 contract fixture + node test | DONE |
| 4 contract test in python + qmllint | DONE |
| 5 `ext list` / name-from-url helpers | DONE |
| 6 `ext add` | DONE |
| 7 `ext update` / `ext remove` | DONE |
| 8 service logs api warnings | DONE |
| 9 docs (README, kit.md, SKILL.md, contributing.md, CHANGELOG, ROADMAP) | DONE |

---

### Task 1: `api` number in the registry, printed by `types` / `status` / `registry --json`

**Files:**
- Modify: `widgets/registry.json:1-2` (add `"api": 1` after `"version"`)
- Modify: `bin/desktop-widgets` `cmd_types`, `cmd_status`
- Test: `tests/test_cli.py` (class `Cli`), `tests/registry.test.js`

**Produces:** `registry["api"]` (int) on the merged registry; `KIT_API = 1` constant is *not* added — the registry file is the single source.

- [ ] Test (python): `types` prints `kit api 1`; `status` prints `api:     1`; `registry --json` has `"api": 1`.

```python
    def test_api_number_is_printed(self):
        code, out, _ = self.run_cli("registry", "--json")
        self.assertEqual(json.loads(out)["api"], 1)
        self.assertIn("kit api 1", self.run_cli("types")[1])
        self.assertIn("api:     1", self.run_cli("status")[1])
```

- [ ] Test (node, `registry.test.js`): `registry.api` is a positive integer.
- [ ] Implement: registry.json `"api": 1`; `cmd_types` prints `kit api {reg.get('api', 1)}` as the first line of the type list; `cmd_status` prints `api:     {n}` after `plugin:`.
- [ ] Run both suites; commit `Registry: kit api number`.

### Task 2: `requires` in type.json → warning on mismatch

**Files:**
- Modify: `bin/desktop-widgets` `load_dropins`, `load_registry`, `cmd_types`, `cmd_registry`, `cmd_validate`
- Test: `tests/test_cli.py`

**Produces:** on a drop-in type: `"requires": {"api": N}` (copied verbatim when present); registry key `"warnings": [str]` (only when non-empty, like `problems`). Message format: `{name} wants api {N}, plugin provides {api}`. Malformed `requires` (not an object, or `api` not a positive int) is a *problem* (drop-in skipped): `{name}: requires.api must be a positive integer`.

- [ ] Test:

```python
    def test_dropin_requires_api(self):
        self.write_dropin("fresh", type_json='{"displayName":"F","requires":{"api":1},"fields":[]}')
        self.write_dropin("future", type_json='{"displayName":"F","requires":{"api":2},"fields":[]}')
        self.write_dropin("junk", type_json='{"displayName":"F","requires":{"api":"x"},"fields":[]}')
        reg = dw.load_registry()
        self.assertIn("fresh", reg["types"]); self.assertIn("future", reg["types"]); self.assertNotIn("junk", reg["types"])
        self.assertEqual(reg["types"]["future"]["requires"], {"api": 2})
        self.assertEqual(reg["warnings"], ["future wants api 2, plugin provides 1"])
        self.assertTrue(any("requires.api must be a positive integer" in p for p in reg["problems"]))
        for argv in (("types",), ("registry",), ("validate",)):
            code, out, err = self.run_cli(*argv)
            self.assertEqual(code, 0, err); self.assertIn("future wants api 2, plugin provides 1", err)
```

- [ ] Implement in `load_dropins(directory, builtin_types, api=None)`: parse `requires`; `load_registry` passes `reg.get("api")` and sets `reg["warnings"]`. `cmd_types`/`cmd_registry` print `WARN drop-in {w}` to stderr after problems; `cmd_validate` prints the same before its summary (warnings do not change the exit code).
- [ ] Run suites; commit `Drop-ins: requires.api warning`.

### Task 3: contract fixture + node test

**Files:**
- Create: `tests/fixtures/kit/api-1.json`
- Create: `tests/kit.test.js`

**Produces:** fixture shape:

```json
{
  "api": 1,
  "importPath": "../../plugins/homelab.desktop-widgets/widgets",
  "fieldTypes": ["string", "integer", "number", "boolean", "enum", "multi-enum", "color", "path", "command", "text", "rows", "apps"],
  "injected": ["config", "service"],
  "files": {
    "WidgetCard.qml": { "properties": ["config", "content", "scale_", "backdrop", "pad", "topInset", "align", "textColor", "mutedColor", "outlineColor", "halo"], "functions": ["resolveColor", "listOf"] },
    "WidgetText.qml": { "properties": ["outlineColor", "halo", "outlineMinPx"], "functions": [] },
    "Sparkline.qml":  { "properties": ["points", "lineColor", "outlineColor", "fillAlpha", "lineWidth", "pts"], "functions": ["px", "py"] }
  }
}
```

Checks (same in both languages):
1. `registry.json.api` equals the fixture's `api`, and the fixture file for the registry's api exists (`api-<n>.json`).
2. For each file: every property name matches `/^\s*(readonly\s+)?(default\s+)?property\s+\S+\s+(\w+)/m` in the QML; every function matches `/function\s+(\w+)\s*\(/`.
3. `examples/drop-in/hello/Widget.qml` contains `import "<importPath>"`; the last path segment is a directory in the plugin (`widgets/`), and the segment before it equals `manifest.json.id`.
4. Every `fieldTypes` entry appears as `case "<t>"` in `widgets/Registry.js` `checkField` (node) / as `"<t>"` in the Python `_check_field` source (python), and every non-special type used in `registry.json` is in the list.
5. `Service.qml` contains `item.config = ` and `item.service = ` (the injection).

- [ ] Write `tests/kit.test.js` implementing 1–5 with `node:test`; run, expect PASS; commit `Kit contract fixture + node test`.

### Task 4: contract test in python + qmllint

**Files:**
- Modify: `tests/test_cli.py` (new class `Kit`)

- [ ] Same five checks in Python (regex over the files; Python check for field types uses `inspect.getsource(dw._check_field)`).
- [ ] `test_qmllint_shipped_widgets`: find `shutil.which("qmllint")` or `/usr/lib/qt6/bin/qmllint`; skip unless `--version` starts with `qmllint 6`; run it on `examples/drop-in/hello/Widget.qml`, every `widgets/*.qml`, `Service.qml`, `Editor.qml`, `Companion.qml`, `arrange/*.qml`, `editor/*.qml`; assert returncode 0 (syntax errors return 255; unresolved shell imports only warn).
- [ ] Run; commit `Kit contract in python + qmllint pass`.

### Task 5: `ext list` + helpers

**Files:**
- Modify: `bin/desktop-widgets` (new section `# ---- ext`), `build_parser`
- Test: `tests/test_cli.py` class `Ext`

**Produces:**
- `ext_name(url) -> str`: last path segment of the URL with a trailing `/`, `.git` removed, lower-cased; `ValueError` if it does not match `DROPIN_NAME`.
- `git(args, cwd=None) -> (code, out)`: `subprocess.run(["git", *args])`, `GIT_TERMINAL_PROMPT=0`.
- `ext_info(name, registry, widgets) -> dict`: `{name, api, origin, commit, inUse, path, git}`; `origin` = `git remote get-url origin` or `local`; `commit` = short head or `-`.
- `cmd_ext(args, ctx)` dispatching `list|add|update|remove`.

- [ ] Test:

```python
class Ext(Cli):
    def make_repo(self, name="wani", requires=None, qml="WidgetCard {}"):
        src = self.home / "src" / name; src.mkdir(parents=True)
        spec = {"displayName": name.title(), "fields": [{"key": "n", "type": "integer", "label": "N", "default": 1}]}
        if requires is not None: spec["requires"] = requires
        (src / "type.json").write_text(json.dumps(spec)); (src / "Widget.qml").write_text(qml)
        for argv in (["init", "-q"], ["add", "."], ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "one"]):
            self.assertEqual(dw.git(argv, cwd=str(src))[0], 0)
        return src

    def test_ext_name(self):
        for url, want in (("https://x/y/wani.git", "wani"), ("git@x:y/Wani-Kani/", "wani-kani"), ("/tmp/a/b", "b")):
            self.assertEqual(dw.ext_name(url), want)
        self.assertRaises(ValueError, dw.ext_name, "https://x/Bad_Name")

    def test_ext_list_shows_local_and_git(self):
        self.write_dropin("hello")
        code, out, err = self.run_cli("ext", "list", "--json")
        self.assertEqual(code, 0, err)
        rows = json.loads(out); self.assertEqual(rows[0]["name"], "hello"); self.assertEqual(rows[0]["origin"], "local"); self.assertEqual(rows[0]["inUse"], 0)
```

- [ ] Implement; parser: `ext list [--json]`; text columns `name api origin commit in-use`. Run; commit `ext list`.

### Task 6: `ext add <url> [name]`

- [ ] Test:

```python
    def test_ext_add_clones_validates_and_reports(self):
        src = self.make_repo("wani", requires={"api": 1})
        code, out, err = self.run_cli("ext", "add", str(src))
        self.assertEqual(code, 0, err)
        d = self.home / ".config" / "omarchy" / "desktop-widgets.d" / "wani"
        self.assertTrue((d / ".git").is_dir() and (d / "type.json").exists())
        self.assertIn("wani", out); self.assertIn("api 1", out); self.assertIn("n", out)
        self.assertIn("wani", dw.load_registry()["types"])
        self.assertEqual(self.run_cli("ext", "add", str(src))[0], 6)            # exists
        self.assertEqual(self.run_cli("ext", "add", str(src), "clock")[0], 2)   # built-in name
        self.assertEqual(self.run_cli("ext", "add", str(src), "Bad")[0], 2)
        self.assertEqual(self.run_cli("ext", "add", str(self.home / "nope"))[0], 4)   # clone failed

    def test_ext_add_rejects_invalid_and_warns_on_api(self):
        bad = self.make_repo("bad", qml=None) if False else None
        src = self.make_repo("broken"); (src / "type.json").write_text("{ nope")
        dw.git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "break"], cwd=str(src))
        code, _, err = self.run_cli("ext", "add", str(src))
        self.assertEqual(code, 5); self.assertIn("type.json", err)
        self.assertFalse((self.home / ".config" / "omarchy" / "desktop-widgets.d" / "broken").exists())
        fut = self.make_repo("future", requires={"api": 99})
        code, out, err = self.run_cli("ext", "add", str(fut))
        self.assertEqual(code, 0); self.assertIn("wants api 99, plugin provides 1", err)
```

- [ ] Implement: reject URLs starting with `-`; name = `args.name or ext_name(url)`; refuse built-in (2) / existing dir (6); `git clone -q -- <url> <dir>` (4 on failure); `load_dropins(dropin_dir(), builtin, api)` filtered to this name — a problem → print, `shutil.rmtree`, exit 5; a warning → print to stderr, keep; success prints `added <name> (<displayName>, api <n or ->) → <dir>`, the field keys, and `next: desktop-widgets add <name>`. Exit codes match `pet fetch`: 2 usage, 4 network/git, 5 invalid, 6 exists.
- [ ] Run; commit `ext add`.

### Task 7: `ext update [name]` and `ext remove <name> [--force]`

- [ ] Test:

```python
    def test_ext_update_pulls_and_reports(self):
        src = self.make_repo("wani"); self.assertEqual(self.run_cli("ext", "add", str(src))[0], 0)
        self.assertEqual(self.run_cli("add", "wani")[0], 0)
        code, out, _ = self.run_cli("ext", "update"); self.assertEqual(code, 0); self.assertIn("wani", out); self.assertIn("up to date", out)
        (src / "Widget.qml").write_text("WidgetCard { }  // v2")
        dw.git(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qam", "two"], cwd=str(src))
        code, out, _ = self.run_cli("ext", "update", "wani"); self.assertEqual(code, 0)
        self.assertIn("updated", out); self.assertIn("restart shell", out)
        self.assertEqual(self.run_cli("ext", "update", "nope")[0], 2)

    def test_ext_remove_refuses_in_use_unless_forced(self):
        src = self.make_repo("wani"); self.run_cli("ext", "add", str(src))
        self.run_cli("add", "wani"); self.run_cli("add", "wani")
        code, _, err = self.run_cli("ext", "remove", "wani"); self.assertEqual(code, 2); self.assertIn("2 widget", err)
        d = self.home / ".config" / "omarchy" / "desktop-widgets.d" / "wani"; self.assertTrue(d.exists())
        code, out, err = self.run_cli("ext", "remove", "wani", "--force"); self.assertEqual(code, 0, err)
        self.assertFalse(d.exists())
        self.assertEqual([w["type"] for w in json.loads(self.cfg.read_text())["widgets"]], ["clock", "stats"])
        self.assertEqual(self.run_cli("ext", "remove", "nope")[0], 2)
```

- [ ] Implement `update`: folders with `.git` (one, or all); `git pull -q --ff-only` (4 on failure, continue others); before/after `rev-parse --short HEAD`; `updated <a>→<b>` or `up to date`; re-validate and print problems/warnings; if any updated folder is in use, print `restart the shell to load the new QML: omarchy restart shell`. `remove`: not a drop-in dir → 2; in-use count > 0 without `--force` → stderr `wani is used by N widget(s); pass --force to remove them too`, exit 2; with `--force` → `mutate` removing those widgets (its exit code wins if non-zero), then `shutil.rmtree`.
- [ ] Run; commit `ext update + remove`.

### Task 8: the service logs api warnings

**Files:**
- Modify: `Service.qml:276-286` (registryProc `onExited`)

- [ ] After the `problems` loop add `var warnings = reg.warnings || []; for (...) root.log("drop-in warning: " + warnings[i])`. No test hook beyond the journal; verify live: create a drop-in with `requires.api: 2`, `omarchy-shell desktop-widgets rescan`, `journalctl --user _COMM=quickshell -n 20 | grep "drop-in warning"`, then delete it.
- [ ] Commit `Service: log drop-in api warnings`.

### Task 9: docs

- [ ] README: "Drop-in widget types" gains `requires`; new section "Sharing a drop-in" (repo layout, `ext` verbs, exit codes, restart rule); CLI table rows for `ext …`; `types` row mentions the api line.
- [ ] `skills/desktop-widgets/kit.md`: `api` + `requires` paragraph, `ext` verbs; `SKILL.md` quick-ref row "install a shared drop-in"; `contributing.md`: rule 2b — bump `api` + add `tests/fixtures/kit/api-<n>.json` on a breaking kit change, contract test guards it.
- [ ] `CHANGELOG.md` Unreleased; `docs/ROADMAP.md` item 8 → DONE with plan link. Commit `Docs: api, requires, ext`.
