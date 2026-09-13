# Desktop Widgets Phase 1: Registry, JSONC config, CLI — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the widget config formal and human-editable without a UI: one registry that describes every widget type, a comment-tolerant config file, and a `desktop-widgets` CLI that lists, edits, validates and toggles it, reachable from the Household menu.

**Architecture:** `widgets/registry.json` is the single description of common and per-type fields. Two thin engines read it — `widgets/Registry.js` inside the shell (defaults + validation at load) and `bin/desktop-widgets` (Python stdlib) for humans — and both are proven equivalent by shared fixture files under `tests/fixtures/`. The service keeps its "last good layout" behaviour; validation only decides which entries are drawn and what is logged.

**Tech Stack:** Quickshell QML/JS (no npm), Node 25 for JS tests (`node --test`), Python 3.14 stdlib only for the CLI and its tests (`python3 -m unittest`), Omarchy 4.0.3 plugin contract.

**Spec:** `docs/ROADMAP.md` (Phase 1 section) and `docs/superpowers/specs/2026-09-09-desktop-widgets-design.md`. Michael approved Phase 1 and a native shell panel for Phase 2 on 2026-09-09 (vault Decision Queue DQ-024).

## Status (handoff block — update after every task)

**PHASE 1 COMPLETE 2026-09-09.** Next: Phase 2 native editor panel — brainstorm + plan in a new file; Michael has already chosen native over web (DQ-024).

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 Registry + Registry.js | done | b22d2ed | 18 node tests green |
| 2 JSONC strip | done | bfad80c | 5 fixtures incl. comma-then-comment |
| 3 Service.qml wiring | done | ef97329 | live: JSONC comment ok, bad corner → ERROR + skipped, 4 widgets restored |
| 4 CLI read-only (validate/list/types) | done | fb46d52 | python tests green over shared fixtures; live list/validate ok |
| 5 CLI mutations + writer | done | 2c7bebe | 14 python tests; live config untouched |
| 6 CLI edit/status/toggle + install + docs | done | 67fe78c | 16 python tests; symlink in ~/.local/bin; live status ok |
| 7 Household menu rows + vault | done | (this commit) | rows live under Household › Desktop widgets; toggle off→0 layers, on→4 |

**How to resume in a fresh session:** read this file, `README.md`, and `docs/ROADMAP.md`; run `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -p 'test_*.py'`; continue at the first task not marked done. Live plugin: `~/.config/omarchy/plugins/homelab.desktop-widgets/` (this repo), config `~/.config/omarchy/desktop-widgets.json`. Code changes under `widgets/` or `bin/` need `omarchy restart shell` to reach the running shell; config changes hot-reload. Board claim: `sirbucket-desktop-widgets` in vault `02 Areas/Agent Board.md`.

## Global Constraints

- No dependencies beyond Node (tests only) and Python 3 stdlib. Omarchy does not guarantee Node, so nothing at runtime may need it.
- Nothing under `/usr/share/omarchy` is ever written.
- Config path stays `~/.config/omarchy/desktop-widgets.json` (honour `$XDG_CONFIG_HOME` if set).
- A valid existing config must render identically before and after this phase (the four live widgets on the dev laptop are the regression check).
- Every write to the config keeps the previous version at `desktop-widgets.json.bak` and is atomic (temp file + rename).
- Commit after every task with the session attribution trailer; push to Forge `origin master`.
- Plugin id `homelab.desktop-widgets`; CLI name `desktop-widgets`; exit code 0 success, 1 validation errors, 2 usage/IO errors.

---

## File structure

| File | Responsibility |
|---|---|
| `widgets/registry.json` | Data: common fields + per-type fields with type/default/min/max/options/label/description. |
| `widgets/Registry.js` | JS engine: `applyDefaults(entry, registry)`, `validateConfig(parsed, registry)`; QML-importable and node-testable. |
| `widgets/Jsonc.js` | JS `strip(text)`: remove `//`, `/* */` comments and trailing commas outside strings. |
| `Service.qml` | Loads registry + config, runs strip → parse → validate → defaults, logs messages, draws entries without errors. |
| `widgets/WidgetCard.qml` | Accept `align: "auto"` (registry default) as "by corner". |
| `bin/desktop-widgets` | Python CLI. Single file. `strip_jsonc`, `load_registry`, `validate_config`, `apply_defaults`, commands. |
| `tests/fixtures/jsonc/*.jsonc` + `*.json` | Shared strip fixtures (input → expected JSON). |
| `tests/fixtures/validate/*.json` | Shared validation fixtures (`config`, `expect`). |
| `tests/registry.test.js`, `tests/jsonc.test.js` | Node tests over fixtures. |
| `tests/test_cli.py` | Python unittest over the same fixtures + CLI behaviour in a temp HOME. |
| `desktop-widgets.example.jsonc` | Commented template (replaces the `.json` example). |
| `README.md`, `docs/ROADMAP.md` | Docs. |
| `~/.config/omarchy/extensions/omarchy-menu.jsonc` | Household → Desktop widgets rows (outside the repo; documented in README). |

---

### Task 1: Registry data + JS engine

**Files:**
- Create: `widgets/registry.json`
- Create: `widgets/Registry.js`
- Create: `tests/fixtures/validate/ok-four-widgets.json`, `tests/fixtures/validate/unknown-type.json`, `tests/fixtures/validate/bad-values.json`, `tests/fixtures/validate/not-a-list.json`
- Test: `tests/registry.test.js`

**Interfaces:**
- Produces `Registry.applyDefaults(entry, registry) -> entry` (new object; fills every common + type field missing from `entry`; never overwrites present keys; adds nothing for unknown types).
- Produces `Registry.validateConfig(parsed, registry) -> { widgets: [...], messages: [{level, widget, key, message}] }` where `widgets` is the array found (top-level array or `parsed.widgets`) or `null` when the shape is wrong; `level` is `"error"` or `"warning"`; `widget` is the index or `-1`.
- Produces `Registry.fieldsFor(type, registry) -> [field...]` (common fields followed by the type's fields).
- Produces `Registry.hasErrors(messages, index) -> bool`.

- [ ] **Step 1: Write the registry**

`widgets/registry.json`:

```json
{
  "version": 1,
  "common": [
    { "key": "type", "type": "type", "label": "Type", "required": true },
    { "key": "enabled", "type": "boolean", "label": "Enabled", "default": true },
    { "key": "corner", "type": "enum", "label": "Corner", "options": ["top-left", "top-right", "bottom-left", "bottom-right"], "default": "top-right" },
    { "key": "x", "type": "integer", "label": "X offset (px)", "default": 48, "min": 0, "max": 8000 },
    { "key": "y", "type": "integer", "label": "Y offset (px)", "default": 48, "min": 0, "max": 8000 },
    { "key": "scale", "type": "number", "label": "Scale", "default": 1, "min": 0.25, "max": 4 },
    { "key": "backdrop", "type": "number", "label": "Backdrop alpha", "default": 0, "min": 0, "max": 1, "description": "Rounded themed card behind the widget; 0 hides it" },
    { "key": "color", "type": "color", "label": "Text colour", "default": "foreground", "description": "Theme token (foreground, background, accent, muted, urgent) or any colour" },
    { "key": "mutedColor", "type": "color", "label": "Muted colour", "default": "muted" },
    { "key": "outline", "type": "color", "label": "Outline colour", "default": "#000000", "description": "Empty disables outline and halo" },
    { "key": "halo", "type": "number", "label": "Halo strength", "default": 0.7, "min": 0, "max": 1 },
    { "key": "align", "type": "enum", "label": "Text alignment", "options": ["auto", "left", "right"], "default": "auto" },
    { "key": "screen", "type": "string", "label": "Screen", "default": "", "description": "Output name from hyprctl monitors; empty means every screen" }
  ],
  "types": {
    "clock": {
      "displayName": "Clock",
      "description": "Time with the date beneath.",
      "fields": [
        { "key": "timeFormat", "type": "string", "label": "Time format", "default": "HH:mm", "description": "Qt date/time format" },
        { "key": "dateFormat", "type": "string", "label": "Date format", "default": "dddd d MMMM", "description": "Empty hides the date" }
      ]
    },
    "stats": {
      "displayName": "System stats",
      "description": "CPU, memory, disk and battery as bars.",
      "fields": [
        { "key": "show", "type": "multi-enum", "label": "Rows", "options": ["cpu", "mem", "disk", "battery"], "default": ["cpu", "mem", "disk", "battery"] },
        { "key": "intervalSec", "type": "integer", "label": "Refresh (s)", "default": 3, "min": 1, "max": 3600 },
        { "key": "diskPath", "type": "path", "label": "Disk to watch", "default": "/" }
      ]
    },
    "command": {
      "displayName": "Command output",
      "description": "Runs a shell command on an interval and shows its output.",
      "fields": [
        { "key": "command", "type": "command", "label": "Command", "default": "", "description": "Run with bash -lc" },
        { "key": "title", "type": "string", "label": "Title", "default": "" },
        { "key": "intervalSec", "type": "integer", "label": "Refresh (s)", "default": 60, "min": 1, "max": 86400 },
        { "key": "timeoutSec", "type": "integer", "label": "Timeout (s)", "default": 10, "min": 1, "max": 600 },
        { "key": "maxLines", "type": "integer", "label": "Max lines", "default": 8, "min": 1, "max": 200 },
        { "key": "maxWidth", "type": "integer", "label": "Max width (px)", "default": 420, "min": 40, "max": 4000 }
      ]
    },
    "agents": {
      "displayName": "Agent session",
      "description": "Current AI-agent session: percent used and when it ends.",
      "fields": [
        { "key": "agent", "type": "enum", "label": "Agent", "options": ["claude", "codex"], "default": "claude" },
        { "key": "title", "type": "string", "label": "Title override", "default": "" },
        { "key": "showWeekly", "type": "boolean", "label": "Show weekly window", "default": false },
        { "key": "timeFormat", "type": "string", "label": "Clock format", "default": "HH:mm" },
        { "key": "refreshIntervalSec", "type": "integer", "label": "Self refresh (s)", "default": 0, "min": 0, "max": 86400, "description": "0 relies on the bar's Agents widget refresh" }
      ]
    }
  }
}
```

- [ ] **Step 2: Write the fixtures**

`tests/fixtures/validate/ok-four-widgets.json`:

```json
{
  "config": { "version": 1, "widgets": [
    { "type": "clock", "corner": "top-right", "x": 48, "y": 64, "color": "#F99957" },
    { "type": "stats", "corner": "bottom-left", "show": ["cpu", "mem"] },
    { "type": "command", "corner": "bottom-right", "title": "UPTIME", "command": "uptime -p" },
    { "type": "agents", "corner": "top-left", "agent": "claude" }
  ] },
  "expect": { "widgets": 4, "errors": 0, "warnings": 0 }
}
```

`tests/fixtures/validate/unknown-type.json`:

```json
{
  "config": [ { "type": "clock" }, { "type": "weather" }, { "corner": "top-left" } ],
  "expect": { "widgets": 3, "errors": 2, "warnings": 0,
    "messages": [ "widget 1: unknown type 'weather'", "widget 2: missing type" ] }
}
```

`tests/fixtures/validate/bad-values.json`:

```json
{
  "config": { "widgets": [
    { "type": "clock", "corner": "middle", "x": "far", "scale": 9, "bogus": 1 },
    { "type": "stats", "show": ["cpu", "gpu"], "intervalSec": 0 },
    { "type": "agents", "agent": "gemini", "showWeekly": "yes" }
  ] },
  "expect": { "widgets": 3, "errors": 7, "warnings": 1,
    "messages": [
      "widget 0: corner must be one of top-left, top-right, bottom-left, bottom-right",
      "widget 0: x must be an integer",
      "widget 0: scale must be at most 4",
      "widget 0: unknown key 'bogus'",
      "widget 1: show has unknown option 'gpu'",
      "widget 1: intervalSec must be at least 1",
      "widget 2: agent must be one of claude, codex",
      "widget 2: showWeekly must be true or false"
    ] }
}
```

`tests/fixtures/validate/not-a-list.json`:

```json
{
  "config": { "widgets": { "type": "clock" } },
  "expect": { "widgets": null, "errors": 1, "warnings": 0,
    "messages": [ "config must be a list of widgets or an object with a widgets list" ] }
}
```

- [ ] **Step 3: Write the failing tests**

`tests/registry.test.js`:

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const R = require("../widgets/Registry.js");

const registry = JSON.parse(fs.readFileSync(path.join(__dirname, "../widgets/registry.json"), "utf8"));
const fixDir = path.join(__dirname, "fixtures/validate");

for (const name of fs.readdirSync(fixDir).filter((f) => f.endsWith(".json")).sort()) {
  test(`validate fixture ${name}`, () => {
    const fx = JSON.parse(fs.readFileSync(path.join(fixDir, name), "utf8"));
    const out = R.validateConfig(fx.config, registry);
    const errors = out.messages.filter((m) => m.level === "error");
    const warnings = out.messages.filter((m) => m.level === "warning");
    assert.equal(out.widgets === null ? null : out.widgets.length, fx.expect.widgets, "widget count");
    assert.equal(errors.length, fx.expect.errors, "errors: " + JSON.stringify(out.messages));
    assert.equal(warnings.length, fx.expect.warnings, "warnings: " + JSON.stringify(out.messages));
    const texts = out.messages.map((m) => (m.widget >= 0 ? `widget ${m.widget}: ` : "") + m.message);
    for (const want of fx.expect.messages || []) assert.ok(texts.includes(want), `missing "${want}" in ${JSON.stringify(texts)}`);
  });
}

test("applyDefaults fills common and type fields without overwriting", () => {
  const e = R.applyDefaults({ type: "clock", x: 10, timeFormat: "H" }, registry);
  assert.equal(e.x, 10);
  assert.equal(e.y, 48);
  assert.equal(e.corner, "top-right");
  assert.equal(e.timeFormat, "H");
  assert.equal(e.dateFormat, "dddd d MMMM");
  assert.equal(e.align, "auto");
  assert.deepEqual(R.applyDefaults({ type: "stats" }, registry).show, ["cpu", "mem", "disk", "battery"]);
  assert.deepEqual(R.applyDefaults({ type: "nope" }, registry), { type: "nope" });
});

test("fieldsFor lists common then type fields", () => {
  const f = R.fieldsFor("agents", registry).map((x) => x.key);
  assert.equal(f[0], "type");
  assert.ok(f.includes("corner") && f.includes("agent") && f.includes("showWeekly"));
  assert.ok(f.indexOf("corner") < f.indexOf("agent"));
  assert.deepEqual(R.fieldsFor("nope", registry), []);
});

test("hasErrors is per widget index", () => {
  const msgs = [{ level: "error", widget: 1, key: "x", message: "m" }, { level: "warning", widget: 0, key: "y", message: "w" }];
  assert.equal(R.hasErrors(msgs, 1), true);
  assert.equal(R.hasErrors(msgs, 0), false);
});
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `node --test tests/registry.test.js`
Expected: FAIL, `Cannot find module '../widgets/Registry.js'`.

- [ ] **Step 5: Write Registry.js**

`widgets/Registry.js`:

```js
// Registry engine: defaults and validation driven by widgets/registry.json.
// Shared by Service.qml (via `import "Registry.js" as Registry`) and node tests.
// bin/desktop-widgets carries the Python twin; tests/fixtures/validate keeps them honest.

function fieldsFor(type, registry) {
  if (!registry || !registry.types || !registry.types[type]) return []
  return (registry.common || []).concat(registry.types[type].fields || [])
}

function clone(v) { return JSON.parse(JSON.stringify(v)) }

function applyDefaults(entry, registry) {
  var out = clone(entry || {})
  var fields = fieldsFor(String(out.type || ""), registry)
  for (var i = 0; i < fields.length; i++) {
    var f = fields[i]
    if (out[f.key] === undefined && f.default !== undefined) out[f.key] = clone(f.default)
  }
  return out
}

function isInt(v) { return typeof v === "number" && isFinite(v) && Math.floor(v) === v }

function checkField(f, value, push) {
  var list
  switch (f.type) {
    case "boolean":
      if (typeof value !== "boolean") push("error", f.key + " must be true or false")
      break
    case "integer":
      if (!isInt(value)) { push("error", f.key + " must be an integer"); return }
      if (f.min !== undefined && value < f.min) push("error", f.key + " must be at least " + f.min)
      if (f.max !== undefined && value > f.max) push("error", f.key + " must be at most " + f.max)
      break
    case "number":
      if (typeof value !== "number" || !isFinite(value)) { push("error", f.key + " must be a number"); return }
      if (f.min !== undefined && value < f.min) push("error", f.key + " must be at least " + f.min)
      if (f.max !== undefined && value > f.max) push("error", f.key + " must be at most " + f.max)
      break
    case "enum":
      if (typeof value !== "string" || (f.options || []).indexOf(value) === -1)
        push("error", f.key + " must be one of " + (f.options || []).join(", "))
      break
    case "multi-enum":
      if (!Array.isArray(value)) { push("error", f.key + " must be a list"); return }
      for (var i = 0; i < value.length; i++)
        if ((f.options || []).indexOf(value[i]) === -1) push("error", f.key + " has unknown option '" + value[i] + "'")
      break
    case "string": case "path": case "command": case "color":
      if (typeof value !== "string") push("error", f.key + " must be a string")
      break
    default:
      break
  }
}

function validateEntry(entry, index, registry, messages) {
  function push(level, message, key) { messages.push({ level: level, widget: index, key: key || "", message: message }) }
  if (!entry || typeof entry !== "object" || Array.isArray(entry)) { push("error", "widget must be an object"); return }
  var type = entry.type
  if (type === undefined || type === null || type === "") { push("error", "missing type", "type"); return }
  if (typeof type !== "string" || !registry.types || !registry.types[type]) { push("error", "unknown type '" + type + "'", "type"); return }
  var fields = fieldsFor(type, registry)
  var known = {}
  for (var i = 0; i < fields.length; i++) {
    var f = fields[i]
    known[f.key] = true
    if (f.type === "type") continue
    if (entry[f.key] === undefined) continue
    checkField(f, entry[f.key], function(level, message) { push(level, message, f.key) })
  }
  for (var k in entry) if (!known[k]) push("warning", "unknown key '" + k + "'", k)
}

function validateConfig(parsed, registry) {
  var messages = []
  var list = Array.isArray(parsed) ? parsed
    : (parsed && typeof parsed === "object" && Array.isArray(parsed.widgets) ? parsed.widgets : null)
  if (!list) {
    messages.push({ level: "error", widget: -1, key: "", message: "config must be a list of widgets or an object with a widgets list" })
    return { widgets: null, messages: messages }
  }
  for (var i = 0; i < list.length; i++) validateEntry(list[i], i, registry, messages)
  return { widgets: list, messages: messages }
}

function hasErrors(messages, index) {
  for (var i = 0; i < messages.length; i++)
    if (messages[i].level === "error" && messages[i].widget === index) return true
  return false
}

if (typeof module !== "undefined") module.exports = { fieldsFor, applyDefaults, validateConfig, hasErrors }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `node --test tests/*.test.js`
Expected: all pass (11 earlier + 4 fixtures + 3 new).

- [ ] **Step 7: Commit and push**

```bash
git add widgets/registry.json widgets/Registry.js tests/registry.test.js tests/fixtures/validate
git commit -m "Widget registry: field descriptions for every type, JS defaults + validation engine, shared fixtures"
git push origin master
```

Update the Status table (Task 1 done, commit hash).

---

### Task 2: JSONC strip (JS)

**Files:**
- Create: `widgets/Jsonc.js`
- Create: `tests/fixtures/jsonc/comments.jsonc`, `tests/fixtures/jsonc/comments.json`, `tests/fixtures/jsonc/trailing-commas.jsonc`, `tests/fixtures/jsonc/trailing-commas.json`, `tests/fixtures/jsonc/strings-untouched.jsonc`, `tests/fixtures/jsonc/strings-untouched.json`
- Test: `tests/jsonc.test.js`

**Interfaces:**
- Produces `Jsonc.strip(text) -> string` that `JSON.parse` accepts when the input was valid JSONC. Plain JSON passes through unchanged in meaning.

- [ ] **Step 1: Write the fixtures**

`comments.jsonc`:

```jsonc
{
  // line comment
  "version": 1, /* block */
  "widgets": [ { "type": "clock" /* inline */ } ]
}
```

`comments.json`: `{"version":1,"widgets":[{"type":"clock"}]}`

`trailing-commas.jsonc`:

```jsonc
{ "widgets": [ { "type": "clock", "x": 1, }, ], }
```

`trailing-commas.json`: `{"widgets":[{"type":"clock","x":1}]}`

`strings-untouched.jsonc`:

```jsonc
{ "widgets": [ { "type": "command", "command": "echo '// not a comment' && echo \"/* nor this */\", " } ] }
```

`strings-untouched.json`: `{"widgets":[{"type":"command","command":"echo '// not a comment' && echo \"/* nor this */\", "}]}`

- [ ] **Step 2: Write the failing test**

`tests/jsonc.test.js`:

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const J = require("../widgets/Jsonc.js");

const dir = path.join(__dirname, "fixtures/jsonc");
for (const name of fs.readdirSync(dir).filter((f) => f.endsWith(".jsonc")).sort()) {
  test(`strip ${name}`, () => {
    const input = fs.readFileSync(path.join(dir, name), "utf8");
    const expected = JSON.parse(fs.readFileSync(path.join(dir, name.replace(/\.jsonc$/, ".json")), "utf8"));
    assert.deepEqual(JSON.parse(J.strip(input)), expected);
  });
}

test("plain JSON is unchanged", () => {
  const s = '{"a":[1,2,{"b":"x"}]}';
  assert.equal(J.strip(s), s);
});
```

- [ ] **Step 3: Run it to verify it fails**

Run: `node --test tests/jsonc.test.js` → FAIL, module not found.

- [ ] **Step 4: Write Jsonc.js**

```js
// Strip // and /* */ comments and trailing commas from JSONC, leaving string
// contents untouched. Python twin: strip_jsonc in bin/desktop-widgets.
function strip(text) {
  var s = String(text || "")
  var out = ""
  var i = 0, n = s.length
  var inString = false
  while (i < n) {
    var c = s[i]
    if (inString) {
      out += c
      if (c === "\\" && i + 1 < n) { out += s[i + 1]; i += 2; continue }
      if (c === '"') inString = false
      i++
      continue
    }
    if (c === '"') { inString = true; out += c; i++; continue }
    if (c === "/" && s[i + 1] === "/") { while (i < n && s[i] !== "\n") i++; continue }
    if (c === "/" && s[i + 1] === "*") { i += 2; while (i < n && !(s[i] === "*" && s[i + 1] === "/")) i++; i += 2; continue }
    if (c === ",") {
      var j = i + 1
      while (j < n && /\s/.test(s[j])) j++
      // skip comments between the comma and the closer
      var k = j
      while (k < n && s[k] === "/" && (s[k + 1] === "/" || s[k + 1] === "*")) {
        if (s[k + 1] === "/") { while (k < n && s[k] !== "\n") k++ }
        else { k += 2; while (k < n && !(s[k] === "*" && s[k + 1] === "/")) k++; k += 2 }
        while (k < n && /\s/.test(s[k])) k++
      }
      if (s[k] === "}" || s[k] === "]") { i++; continue }
    }
    out += c
    i++
  }
  return out
}

if (typeof module !== "undefined") module.exports = { strip }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `node --test tests/*.test.js` → all pass.

- [ ] **Step 6: Commit and push**

```bash
git add widgets/Jsonc.js tests/jsonc.test.js tests/fixtures/jsonc
git commit -m "JSONC: comment and trailing-comma stripping with shared fixtures"
git push origin master
```

Update the Status table.

---

### Task 3: Wire the registry and JSONC into the service

**Files:**
- Modify: `Service.qml` (imports, `knownTypes`, `loadConfig`, add registry FileView)
- Modify: `widgets/WidgetCard.qml` (`align` handles `"auto"`)
- Modify: `README.md` (mention comments allowed, validation messages)

**Interfaces:**
- Consumes `Registry.validateConfig`, `Registry.applyDefaults`, `Registry.hasErrors`, `Jsonc.strip`.
- Produces the same `widgets` property shape as before (array of entry objects with `__index`), now default-filled.

- [ ] **Step 1: Edit Service.qml**

Replace the top imports and the `knownTypes` line:

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "widgets/Jsonc.js" as Jsonc
import "widgets/Registry.js" as Registry
```

```qml
  readonly property string registryPath: String(Qt.resolvedUrl("widgets/registry.json")).replace(/^file:\/\//, "")
  property var registry: null
  property string pendingConfigText: ""
  property bool haveConfigText: false
```

Replace the body of `loadConfig(raw)` with:

```qml
  function loadConfig(raw) {
    pendingConfigText = String(raw || "")
    haveConfigText = true
    if (registry) applyConfig()
  }

  function applyConfig() {
    var text = pendingConfigText.trim()
    if (!text) {
      if (!everLoaded) log("no config at " + configPath + " — nothing to draw")
      widgets = []
      everLoaded = true
      return
    }
    var parsed
    try {
      parsed = JSON.parse(Jsonc.strip(text))
    } catch (e) {
      log("config parse error, keeping last good layout: " + e)
      return
    }
    var result = Registry.validateConfig(parsed, registry)
    for (var m = 0; m < result.messages.length; m++) {
      var msg = result.messages[m]
      log((msg.level === "error" ? "ERROR " : "warn  ") + (msg.widget >= 0 ? "widget " + msg.widget + ": " : "") + msg.message)
    }
    if (!result.widgets) { log("keeping last good layout"); return }
    var next = []
    for (var i = 0; i < result.widgets.length; i++) {
      if (Registry.hasErrors(result.messages, i)) continue
      var entry = Registry.applyDefaults(result.widgets[i], registry)
      if (entry.enabled === false) continue
      entry.__index = i
      next.push(entry)
    }
    widgets = next
    everLoaded = true
    log("loaded " + next.length + " widget(s)" + (next.length !== result.widgets.length ? " (" + (result.widgets.length - next.length) + " skipped)" : ""))
  }
```

Add a registry FileView next to the config one:

```qml
  FileView {
    path: root.registryPath
    blockLoading: true
    onLoaded: {
      try { root.registry = JSON.parse(text()) } catch (e) { root.log("registry parse error: " + e); root.registry = null }
      if (root.registry && root.haveConfigText) root.applyConfig()
    }
    onLoadFailed: function(error) { root.log("registry read failed: " + error) }
  }
```

Remove the `knownTypes` property and its use (validation replaces it). Keep the Loader `switch` as is — unknown types never reach it now.

- [ ] **Step 2: Edit WidgetCard.qml**

Replace the `align` line with:

```qml
  readonly property string align: {
    var a = String(config.align || "auto")
    if (a === "left" || a === "right") return a
    return String(config.corner || "top-right").indexOf("right") !== -1 ? "right" : "left"
  }
```

- [ ] **Step 3: Live check on the dev laptop**

```bash
omarchy plugin validate . && omarchy restart shell; sleep 7
hyprctl layers | grep -c homelab-desktop-widgets          # expect 4
journalctl --user _COMM=quickshell --since "30 sec ago" --no-pager | grep desktop-widgets
```

Expected: `loaded 4 widget(s)`, no ERROR lines. Then append `, // comment` inside the live config, save, confirm the journal shows a reload with 4 widgets (JSONC accepted). Then set `"corner": "middle"` on one widget: expect `ERROR widget n: corner must be one of ...` and `loaded 3 widget(s) (1 skipped)`; revert.

- [ ] **Step 4: README**

Under "Configure" add: "Comments (`//`, `/* */`) and trailing commas are allowed. Entries with invalid values are skipped and the reason is logged (`journalctl --user _COMM=quickshell | grep desktop-widgets`); unknown keys only warn."

- [ ] **Step 5: Commit and push**

```bash
git add Service.qml widgets/WidgetCard.qml README.md
git commit -m "Service: registry-driven defaults and validation, JSONC config"
git push origin master
```

Update the Status table.

---

### Task 4: CLI, read-only commands

**Files:**
- Create: `bin/desktop-widgets` (Python, executable)
- Test: `tests/test_cli.py`

**Interfaces:**
- Produces module-level functions importable by tests (the file is loaded via `importlib` from its path): `strip_jsonc(text) -> str`, `load_registry(path) -> dict`, `fields_for(type, registry) -> list`, `apply_defaults(entry, registry) -> dict`, `validate_config(parsed, registry) -> (widgets|None, messages)` with messages as dicts `{level, widget, key, message}` matching the JS engine exactly, `config_path() -> str`, `read_config(path) -> (parsed, raw_text)`, `main(argv) -> int`.
- Commands: `validate [file]`, `list`, `types [type]`, `path`.

- [ ] **Step 1: Write the failing tests**

`tests/test_cli.py`:

```python
import importlib.util, io, json, os, pathlib, sys, tempfile, unittest
from contextlib import redirect_stdout, redirect_stderr

ROOT = pathlib.Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_loader("dw", importlib.machinery.SourceFileLoader("dw", str(ROOT / "bin" / "desktop-widgets")))
dw = importlib.util.module_from_spec(spec); spec.loader.exec_module(dw)
REGISTRY = dw.load_registry(str(ROOT / "widgets" / "registry.json"))


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


class Cli(unittest.TestCase):
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

    def test_missing_config(self):
        self.cfg.unlink()
        code, out, err = self.run_cli("list")
        self.assertEqual(code, 0); self.assertIn("no config", out)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run to verify it fails**

Run: `python3 -m unittest discover -s tests -p 'test_*.py' -v` → errors: file `bin/desktop-widgets` missing.

- [ ] **Step 3: Write the CLI (read-only part)**

`bin/desktop-widgets` (mark executable with `chmod +x`):

```python
#!/usr/bin/env python3
"""desktop-widgets — manage ~/.config/omarchy/desktop-widgets.json for the
homelab.desktop-widgets Omarchy shell plugin. Python 3 stdlib only.

Validation and defaults mirror widgets/Registry.js; tests/fixtures keep the
two engines identical."""
import argparse, json, os, re, shutil, subprocess, sys, tempfile

PLUGIN_ID = "homelab.desktop-widgets"
HERE = os.path.dirname(os.path.realpath(__file__))
PLUGIN_DIR = os.path.dirname(HERE)
REGISTRY_PATH = os.path.join(PLUGIN_DIR, "widgets", "registry.json")
CORNERS = ["top-left", "top-right", "bottom-left", "bottom-right"]


def config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "omarchy", "desktop-widgets.json")


# ----------------------------------------------------------------- jsonc
def strip_jsonc(text):
    out, i, n, in_str = [], 0, len(text), False
    while i < n:
        c = text[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(text[i + 1]); i += 2; continue
            if c == '"': in_str = False
            i += 1; continue
        if c == '"':
            in_str = True; out.append(c); i += 1; continue
        if text.startswith("//", i):
            while i < n and text[i] != "\n": i += 1
            continue
        if text.startswith("/*", i):
            end = text.find("*/", i + 2); i = n if end < 0 else end + 2; continue
        if c == ",":
            k = i + 1
            while True:
                while k < n and text[k].isspace(): k += 1
                if text.startswith("//", k):
                    while k < n and text[k] != "\n": k += 1
                elif text.startswith("/*", k):
                    end = text.find("*/", k + 2); k = n if end < 0 else end + 2
                else:
                    break
            if k < n and text[k] in "}]":
                i += 1; continue
        out.append(c); i += 1
    return "".join(out)


def has_comments(text):
    return strip_jsonc(text) != text


# -------------------------------------------------------------- registry
def load_registry(path=REGISTRY_PATH):
    with open(path) as fh:
        return json.load(fh)


def fields_for(type_, registry):
    t = registry.get("types", {}).get(type_)
    if not t: return []
    return list(registry.get("common", [])) + list(t.get("fields", []))


def apply_defaults(entry, registry):
    out = json.loads(json.dumps(entry))
    for f in fields_for(str(out.get("type", "")), registry):
        if f["key"] not in out and "default" in f:
            out[f["key"]] = json.loads(json.dumps(f["default"]))
    return out


def _check_field(f, value, push):
    t = f["type"]
    if t == "boolean":
        if not isinstance(value, bool): push("error", f"{f['key']} must be true or false")
    elif t == "integer":
        if isinstance(value, bool) or not isinstance(value, int):
            push("error", f"{f['key']} must be an integer"); return
        if "min" in f and value < f["min"]: push("error", f"{f['key']} must be at least {f['min']}")
        if "max" in f and value > f["max"]: push("error", f"{f['key']} must be at most {f['max']}")
    elif t == "number":
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            push("error", f"{f['key']} must be a number"); return
        if "min" in f and value < f["min"]: push("error", f"{f['key']} must be at least {_num(f['min'])}")
        if "max" in f and value > f["max"]: push("error", f"{f['key']} must be at most {_num(f['max'])}")
    elif t == "enum":
        if not isinstance(value, str) or value not in f.get("options", []):
            push("error", f"{f['key']} must be one of {', '.join(f.get('options', []))}")
    elif t == "multi-enum":
        if not isinstance(value, list):
            push("error", f"{f['key']} must be a list"); return
        for v in value:
            if v not in f.get("options", []): push("error", f"{f['key']} has unknown option '{v}'")
    elif t in ("string", "path", "command", "color"):
        if not isinstance(value, str): push("error", f"{f['key']} must be a string")


def _num(v):
    return str(int(v)) if float(v).is_integer() else str(v)


def validate_config(parsed, registry):
    messages = []
    if isinstance(parsed, list): widgets = parsed
    elif isinstance(parsed, dict) and isinstance(parsed.get("widgets"), list): widgets = parsed["widgets"]
    else:
        messages.append({"level": "error", "widget": -1, "key": "", "message": "config must be a list of widgets or an object with a widgets list"})
        return None, messages
    for i, entry in enumerate(widgets):
        def push(level, message, key=""): messages.append({"level": level, "widget": i, "key": key, "message": message})
        if not isinstance(entry, dict): push("error", "widget must be an object"); continue
        type_ = entry.get("type")
        if type_ in (None, ""): push("error", "missing type", "type"); continue
        if not isinstance(type_, str) or type_ not in registry.get("types", {}):
            push("error", f"unknown type '{type_}'", "type"); continue
        known = set()
        for f in fields_for(type_, registry):
            known.add(f["key"])
            if f["type"] == "type" or f["key"] not in entry: continue
            _check_field(f, entry[f["key"]], lambda level, message, key=f["key"]: push(level, message, key))
        for k in entry:
            if k not in known: push("warning", f"unknown key '{k}'", k)
    return widgets, messages


# ---------------------------------------------------------------- config io
def read_config(path):
    """Returns (parsed, raw_text). parsed is None when the file is missing;
    raises ValueError on a parse error."""
    if not os.path.exists(path): return None, ""
    with open(path) as fh: raw = fh.read()
    try:
        return json.loads(strip_jsonc(raw)), raw
    except json.JSONDecodeError as e:
        raise ValueError(f"{path}: {e}")


def print_messages(messages, stream):
    for m in messages:
        where = f"widget {m['widget']}: " if m["widget"] >= 0 else ""
        print(f"{m['level'].upper():7} {where}{m['message']}", file=stream)


def summarize(entry, registry):
    t = entry.get("type", "?")
    bits = {
        "clock": lambda e: e.get("timeFormat", "HH:mm"),
        "stats": lambda e: ",".join(e.get("show", ["cpu", "mem", "disk", "battery"])),
        "command": lambda e: (e.get("title") or e.get("command") or "")[:40],
        "agents": lambda e: e.get("agent", "claude"),
    }
    return bits.get(t, lambda e: "")(entry)


# ---------------------------------------------------------------- commands
def cmd_path(args, ctx):
    print(ctx["path"]); return 0


def cmd_validate(args, ctx):
    path = args.file or ctx["path"]
    try:
        parsed, raw = read_config(path)
    except ValueError as e:
        print(f"ERROR   {e}", file=sys.stderr); return 1
    if parsed is None:
        print(f"no config at {path}"); return 0
    widgets, messages = validate_config(parsed, ctx["registry"])
    print_messages(messages, sys.stderr)
    errors = sum(m["level"] == "error" for m in messages)
    if errors: print(f"{errors} error(s)", file=sys.stderr); return 1
    print(f"ok: {len(widgets)} widget(s), {sum(m['level'] == 'warning' for m in messages)} warning(s)")
    return 0


def cmd_list(args, ctx):
    try:
        parsed, raw = read_config(ctx["path"])
    except ValueError as e:
        print(f"ERROR   {e}", file=sys.stderr); return 1
    if parsed is None: print(f"no config at {ctx['path']}"); return 0
    widgets, messages = validate_config(parsed, ctx["registry"])
    if widgets is None: print_messages(messages, sys.stderr); return 1
    for i, e in enumerate(widgets):
        bad = any(m["level"] == "error" and m["widget"] == i for m in messages)
        state = "ERR" if bad else ("off" if e.get("enabled") is False else "on ")
        t = str(e.get("type", "?"))
        print(f"{i:<2} {t:<8} {state} {str(e.get('corner', 'top-right')):<12} {e.get('x', 48):>4},{e.get('y', 48):<4} {summarize(e, ctx['registry'])}")
    return 0


def cmd_types(args, ctx):
    reg = ctx["registry"]
    if args.type:
        if args.type not in reg["types"]: print(f"unknown type '{args.type}'", file=sys.stderr); return 2
        t = reg["types"][args.type]
        print(f"{args.type} — {t.get('displayName', args.type)}: {t.get('description', '')}")
        for f in fields_for(args.type, reg):
            if f["type"] == "type": continue
            extra = []
            if "default" in f: extra.append(f"default {json.dumps(f['default'])}")
            if "options" in f: extra.append("one of " + ", ".join(f["options"]) if f["type"] == "enum" else "any of " + ", ".join(f["options"]))
            if "min" in f or "max" in f: extra.append(f"{_num(f.get('min', '-'))}..{_num(f.get('max', '-')) if 'max' in f else ''}")
            print(f"  {f['key']:<20} {f['type']:<11} {'; '.join(extra)}" + (f"  — {f['description']}" if f.get("description") else ""))
        return 0
    for name, t in reg["types"].items():
        print(f"{name:<9} {t.get('displayName', name):<16} {t.get('description', '')}")
    return 0


def build_parser():
    p = argparse.ArgumentParser(prog="desktop-widgets", description="Manage the desktop-widgets config.")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("path", help="print the config path").set_defaults(fn=cmd_path)
    v = sub.add_parser("validate", help="validate the config (exit 1 on errors)"); v.add_argument("file", nargs="?"); v.set_defaults(fn=cmd_validate)
    sub.add_parser("list", help="list widgets").set_defaults(fn=cmd_list)
    t = sub.add_parser("types", help="describe widget types and their fields"); t.add_argument("type", nargs="?"); t.set_defaults(fn=cmd_types)
    return p


def main(argv=None):
    args = build_parser().parse_args(argv)
    ctx = {"path": config_path(), "registry": load_registry()}
    return args.fn(args, ctx)


if __name__ == "__main__":
    sys.exit(main())
```

Note on `_num` for the `number` type: the JS engine prints `scale must be at most 4` (JS number formatting drops `.0`); Python must print `4` not `4.0`, which `_num` does.

- [ ] **Step 4: Run tests to verify they pass**

Run: `chmod +x bin/desktop-widgets && python3 -m unittest discover -s tests -p 'test_*.py' -v` → all pass. Also `node --test tests/*.test.js` still green.

- [ ] **Step 5: Commit and push**

```bash
git add bin/desktop-widgets tests/test_cli.py
git commit -m "desktop-widgets CLI: validate, list, types, path (Python stdlib; shares fixtures with the JS engine)"
git push origin master
```

Update the Status table.

---

### Task 5: CLI mutations and the safe writer

**Files:**
- Modify: `bin/desktop-widgets`
- Modify: `tests/test_cli.py`

**Interfaces:**
- Produces `write_config(path, data, raw_before)`: writes `path + ".bak"` with `raw_before` (only if a file existed), then atomically writes `json.dumps(data, indent=2) + "\n"`.
- Produces `parse_value(field, text) -> value` converting `key=value` CLI text by the registry field type (`integer` → int, `number` → float/int, `boolean` → `true/false/yes/no/1/0`, `multi-enum` → comma-split list, others → string).
- Commands: `add <type> [--corner C] [--x N] [--y N] [--set key=value ...]`, `set <index> key=value ...`, `move <index> [--corner C] [--x N] [--y N]`, `enable <index>`, `disable <index>`, `remove <index>`, `duplicate <index>`. All accept `--force` to write even when the file contains comments (which a write would drop); without it they refuse with exit 2 and a hint to use `edit`.

- [ ] **Step 1: Write the failing tests** (append to `class Cli`)

```python
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
        self.assertEqual(self.run_cli("add", "weather")[0], 2)

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
```

- [ ] **Step 2: Run to verify they fail** → `argparse` errors (unknown command), exit code 2 from argparse becomes `SystemExit`; wrap: in tests these raise. Expected: failures/errors for the new tests only.

- [ ] **Step 3: Implement** (insert before `build_parser`, then extend it)

```python
def write_config(path, data, raw_before):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if raw_before is not None and os.path.exists(path):
        with open(path + ".bak", "w") as fh: fh.write(raw_before)
    fd, tmp = tempfile.mkstemp(prefix=".desktop-widgets.", dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as fh:
        fh.write(json.dumps(data, indent=2) + "\n")
    os.replace(tmp, path)


def parse_value(field, text):
    t = field["type"] if field else "string"
    if t == "integer":
        try: return int(text)
        except ValueError: raise ValueError(f"{field['key']} must be an integer")
    if t == "number":
        try:
            v = float(text); return int(v) if v.is_integer() else v
        except ValueError: raise ValueError(f"{field['key']} must be a number")
    if t == "boolean":
        low = text.strip().lower()
        if low in ("true", "yes", "1", "on"): return True
        if low in ("false", "no", "0", "off"): return False
        raise ValueError(f"{field['key']} must be true or false")
    if t == "multi-enum":
        return [s.strip() for s in text.split(",") if s.strip()]
    return text


def load_for_write(ctx, force, create=False):
    """Returns (document, widgets, raw) or raises SystemExit-style tuple via ValueError."""
    try:
        parsed, raw = read_config(ctx["path"])
    except ValueError as e:
        raise ValueError(f"ERROR   {e}")
    if parsed is None:
        if not create: raise ValueError(f"no config at {ctx['path']} (add a widget first)")
        return {"version": 1, "widgets": []}, [], None
    if raw and has_comments(raw) and not force:
        raise ValueError("config contains comments, which a write would drop — edit it with `desktop-widgets edit`, or pass --force")
    if isinstance(parsed, list): parsed = {"version": 1, "widgets": parsed}
    if not isinstance(parsed, dict) or not isinstance(parsed.get("widgets"), list):
        raise ValueError("config must be a list of widgets or an object with a widgets list")
    return parsed, parsed["widgets"], raw


def apply_sets(entry, pairs, registry):
    fields = {f["key"]: f for f in fields_for(entry.get("type", ""), registry)}
    for pair in pairs:
        if "=" not in pair: raise ValueError(f"expected key=value, got '{pair}'")
        key, text = pair.split("=", 1)
        entry[key] = parse_value(fields.get(key), text)


def index_arg(widgets, index):
    if index < 0 or index >= len(widgets): raise ValueError(f"no widget {index} (have {len(widgets)})")
    return widgets[index]


def commit(ctx, doc, widgets, raw, touched):
    """Validate then write. touched = indices to report errors for; any error aborts."""
    _, messages = validate_config(doc, ctx["registry"])
    errors = [m for m in messages if m["level"] == "error"]
    if errors:
        print_messages(errors, sys.stderr); print("not written", file=sys.stderr); return 1
    write_config(ctx["path"], doc, raw)
    print(f"wrote {ctx['path']}" + (f" (previous copy in {os.path.basename(ctx['path'])}.bak)" if raw is not None else ""))
    return 0


def mutate(args, ctx, fn, create=False):
    try:
        doc, widgets, raw = load_for_write(ctx, getattr(args, "force", False), create=create)
        touched = fn(doc, widgets)
    except ValueError as e:
        print(str(e), file=sys.stderr); return 2 if "must be" not in str(e) else 1
    return commit(ctx, doc, widgets, raw, touched)


def cmd_add(args, ctx):
    if args.type not in ctx["registry"]["types"]:
        print(f"unknown type '{args.type}' (see `desktop-widgets types`)", file=sys.stderr); return 2
    def fn(doc, widgets):
        entry = {"type": args.type}
        if args.corner: entry["corner"] = args.corner
        if args.x is not None: entry["x"] = args.x
        if args.y is not None: entry["y"] = args.y
        apply_sets(entry, args.set or [], ctx["registry"])
        widgets.append(entry); return [len(widgets) - 1]
    return mutate(args, ctx, fn, create=True)


def cmd_set(args, ctx):
    def fn(doc, widgets):
        e = index_arg(widgets, args.index); apply_sets(e, args.pairs, ctx["registry"]); return [args.index]
    return mutate(args, ctx, fn)


def cmd_move(args, ctx):
    def fn(doc, widgets):
        e = index_arg(widgets, args.index)
        if args.corner: e["corner"] = args.corner
        if args.x is not None: e["x"] = args.x
        if args.y is not None: e["y"] = args.y
        return [args.index]
    return mutate(args, ctx, fn)


def cmd_enabled(value):
    def run(args, ctx):
        def fn(doc, widgets):
            e = index_arg(widgets, args.index)
            if value: e.pop("enabled", None)
            else: e["enabled"] = False
            return [args.index]
        return mutate(args, ctx, fn)
    return run


def cmd_remove(args, ctx):
    def fn(doc, widgets):
        index_arg(widgets, args.index); widgets.pop(args.index); return []
    return mutate(args, ctx, fn)


def cmd_duplicate(args, ctx):
    def fn(doc, widgets):
        e = index_arg(widgets, args.index); widgets.insert(args.index + 1, json.loads(json.dumps(e))); return [args.index + 1]
    return mutate(args, ctx, fn)
```

Extend `build_parser` (after the `types` parser):

```python
    def idx(sp): sp.add_argument("index", type=int); sp.add_argument("--force", action="store_true", help="write even if the file has comments")
    a = sub.add_parser("add", help="append a widget"); a.add_argument("type"); a.add_argument("--corner", choices=CORNERS); a.add_argument("--x", type=int); a.add_argument("--y", type=int); a.add_argument("--set", action="append", metavar="key=value"); a.add_argument("--force", action="store_true"); a.set_defaults(fn=cmd_add)
    s = sub.add_parser("set", help="set key=value pairs on a widget"); idx(s); s.add_argument("pairs", nargs="+", metavar="key=value"); s.set_defaults(fn=cmd_set)
    m = sub.add_parser("move", help="change corner/offset"); idx(m); m.add_argument("--corner", choices=CORNERS); m.add_argument("--x", type=int); m.add_argument("--y", type=int); m.set_defaults(fn=cmd_move)
    e = sub.add_parser("enable", help="enable a widget"); idx(e); e.set_defaults(fn=cmd_enabled(True))
    d = sub.add_parser("disable", help="disable a widget (kept in the file)"); idx(d); d.set_defaults(fn=cmd_enabled(False))
    r = sub.add_parser("remove", help="delete a widget"); idx(r); r.set_defaults(fn=cmd_remove)
    u = sub.add_parser("duplicate", help="copy a widget to the next slot"); idx(u); u.set_defaults(fn=cmd_duplicate)
```

And make `main` tolerant of argparse exits in tests:

```python
def main(argv=None):
    try:
        args = build_parser().parse_args(argv)
    except SystemExit as e:
        return int(e.code or 0)
    ctx = {"path": config_path(), "registry": load_registry()}
    return args.fn(args, ctx)
```

- [ ] **Step 4: Run tests** → all pass (Python + node).

- [ ] **Step 5: Live check**: `bin/desktop-widgets list` against the real config prints the four widgets; `bin/desktop-widgets validate` prints `ok: 4 widget(s)`. Do NOT mutate the live config in this task.

- [ ] **Step 6: Commit and push**

```bash
git add bin/desktop-widgets tests/test_cli.py
git commit -m "desktop-widgets CLI: add/set/move/enable/disable/remove/duplicate with .bak and atomic writes"
git push origin master
```

Update the Status table.

---

### Task 6: `edit`, `status`, `toggle`, install, docs

**Files:**
- Modify: `bin/desktop-widgets`
- Modify: `tests/test_cli.py`
- Create: `desktop-widgets.example.jsonc`; Delete: `desktop-widgets.example.json`
- Modify: `README.md`

**Interfaces:**
- `edit`: copies the file to a temp file, runs `$VISUAL`/`$EDITOR`/`nano`/`vi` on it, validates the result; on errors prints them and asks `save anyway? [y/N]` (non-tty → refuse); on OK writes with `.bak`. Never reformats: the edited text is written verbatim (comments survive).
- `status [--enabled]`: `--enabled` exits 0 when the plugin id is present in `plugins[]` of `~/.config/omarchy/shell.json`, else 1 (for the menu's `checked`). Without the flag prints: plugin enabled?, config path + validation summary, number of `homelab-desktop-widgets` layers from `hyprctl layers`, last 5 journal lines matching `desktop-widgets`.
- `toggle`: runs `omarchy plugin disable|enable homelab.desktop-widgets` depending on `status --enabled`.
- `plugin_enabled(shell_json_path) -> bool` for tests.

- [ ] **Step 1: Write the failing tests** (append)

```python
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
```

- [ ] **Step 2: Run to verify they fail.**

- [ ] **Step 3: Implement**

```python
def shell_json_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "omarchy", "shell.json")


def plugin_enabled(path=None):
    path = path or shell_json_path()
    try:
        with open(path) as fh: doc = json.load(fh)
    except (OSError, ValueError):
        return False
    return any(isinstance(p, dict) and p.get("id") == PLUGIN_ID for p in doc.get("plugins", []) or [])


def run_quiet(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def cmd_status(args, ctx):
    enabled = plugin_enabled()
    if args.enabled: return 0 if enabled else 1
    print(f"plugin:  {PLUGIN_ID} — {'enabled' if enabled else 'disabled'} (shell.json)")
    print(f"config:  {ctx['path']}")
    try:
        parsed, raw = read_config(ctx["path"])
        if parsed is None: print("         missing")
        else:
            widgets, messages = validate_config(parsed, ctx["registry"])
            errs = sum(m["level"] == "error" for m in messages)
            print(f"         {len(widgets) if widgets else 0} widget(s), {errs} error(s), {sum(m['level'] == 'warning' for m in messages)} warning(s)")
            print_messages([m for m in messages if m["level"] == "error"], sys.stdout)
    except ValueError as e:
        print(f"         parse error: {e}")
    layers = run_quiet(["hyprctl", "layers"]).count("homelab-desktop-widgets")
    print(f"layers:  {layers} window(s) on screen")
    log = run_quiet(["journalctl", "--user", "_COMM=quickshell", "-n", "400", "--no-pager"])
    lines = [l for l in log.splitlines() if "desktop-widgets" in l][-5:]
    if lines:
        print("log:")
        for l in lines: print("  " + l.split("]: ", 1)[-1])
    return 0


def cmd_toggle(args, ctx):
    action = "disable" if plugin_enabled() else "enable"
    rc = subprocess.call(["omarchy", "plugin", action, PLUGIN_ID])
    return 0 if rc == 0 else 2


def cmd_edit(args, ctx):
    path = ctx["path"]
    try:
        parsed, raw = read_config(path)
    except ValueError:
        with open(path) as fh: raw = fh.read()   # let the user fix a broken file
    if not os.path.exists(path):
        raw = '{\n  "version": 1,\n  "widgets": [\n  ]\n}\n'
    editor = os.environ.get("VISUAL") or os.environ.get("EDITOR") or (shutil.which("nano") and "nano") or "vi"
    fd, tmp = tempfile.mkstemp(prefix="desktop-widgets.", suffix=".jsonc")
    with os.fdopen(fd, "w") as fh: fh.write(raw)
    try:
        rc = subprocess.call(f"{editor} {tmp}", shell=True)
        if rc != 0: print(f"editor exited {rc}; not saved", file=sys.stderr); return 2
        with open(tmp) as fh: text = fh.read()
    finally:
        try: os.unlink(tmp)
        except OSError: pass
    if text == raw: print("no changes"); return 0
    try:
        parsed = json.loads(strip_jsonc(text)); widgets, messages = validate_config(parsed, ctx["registry"])
        errors = [m for m in messages if m["level"] == "error"]
    except json.JSONDecodeError as e:
        errors = [{"level": "error", "widget": -1, "key": "", "message": f"parse error: {e}"}]
    if errors:
        print_messages(errors, sys.stderr)
        if not sys.stdin.isatty(): print("not saved (invalid, no terminal to confirm)", file=sys.stderr); return 1
        if input("save anyway? [y/N] ").strip().lower() != "y": print("not saved", file=sys.stderr); return 1
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if os.path.exists(path):
        with open(path + ".bak", "w") as fh: fh.write(raw)
    fd, tmp2 = tempfile.mkstemp(prefix=".desktop-widgets.", dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as fh: fh.write(text)
    os.replace(tmp2, path)
    print(f"wrote {path}"); return 0
```

Parser additions:

```python
    st = sub.add_parser("status", help="plugin state, config health, windows on screen"); st.add_argument("--enabled", action="store_true", help="exit 0 if the plugin is enabled"); st.set_defaults(fn=cmd_status)
    sub.add_parser("toggle", help="enable or disable the plugin via omarchy plugin").set_defaults(fn=cmd_toggle)
    sub.add_parser("edit", help="open the config in $EDITOR, validate on save, keep .bak").set_defaults(fn=cmd_edit)
```

- [ ] **Step 4: Run tests** → all pass.

- [ ] **Step 5: Example config and install**

`desktop-widgets.example.jsonc` (delete the `.json` one; update README references):

```jsonc
{
  // Desktop widgets — copy to ~/.config/omarchy/desktop-widgets.json and prune.
  // Comments and trailing commas are fine. `desktop-widgets types <type>` lists every key.
  "version": 1,
  "widgets": [
    // Big clock, top-right. color/outline/halo keep it readable on any wallpaper.
    { "type": "clock", "corner": "top-right", "x": 48, "y": 64,
      "timeFormat": "HH:mm", "dateFormat": "dddd d MMMM" },

    // CPU / memory / disk / battery bars.
    { "type": "stats", "corner": "bottom-left", "x": 48, "y": 48,
      "show": ["cpu", "mem", "disk", "battery"], "intervalSec": 3 },

    // Any command's output. Non-zero exit keeps the last good text and marks a red "!".
    { "type": "command", "corner": "bottom-right", "x": 48, "y": 48,
      "title": "UPTIME", "command": "uptime -p", "intervalSec": 60, "maxLines": 4 },

    // Current Claude session: % used, meter, "ends in 3h 27m · 22:59".
    { "type": "agents", "corner": "top-left", "x": 48, "y": 64, "agent": "claude" },
  ],
}
```

Install line for README (and run it on the dev laptop):

```bash
mkdir -p ~/.local/bin && ln -sf ~/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets ~/.local/bin/desktop-widgets
desktop-widgets status
```

README: add a "## CLI" section listing every command with one line each (copy from the ROADMAP table plus `status`, `toggle`, `path`), the install line, and the comment-loss rule (`add/set/... refuse to rewrite a commented file without --force; edit keeps comments`).

- [ ] **Step 6: Live check**: `desktop-widgets status` shows enabled, 4 widgets, 4 layers. `desktop-widgets edit` with `EDITOR=true` → "no changes".

- [ ] **Step 7: Commit and push**

```bash
git add -A
git commit -m "desktop-widgets CLI: edit (verbatim, validated), status, toggle; commented example config; README CLI section"
git push origin master
```

Update the Status table.

---

### Task 7: Household menu rows and vault

**Files:**
- Modify: `~/.config/omarchy/extensions/omarchy-menu.jsonc` (outside the repo)
- Modify: `README.md` ("Omarchy menu" subsection with the snippet)
- Modify vault: `03 Resources/Tool Guides/Omarchy Desktop Widgets.md`, `02 Areas/Agent Board.md`, memory `omarchy-desktop-widgets.md`

- [ ] **Step 1: Add the rows** after `"household.flame"`:

```jsonc
  "household.widgets":         {"icon":"󱂬","label":"Desktop widgets","aliases":["widgets"],"description":"Wallpaper-layer widgets"},
  "household.widgets.edit":    {"icon":"","label":"Edit config","action":"omarchy-launch-terminal $HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets edit","description":"$EDITOR, validated on save"},
  "household.widgets.status":  {"icon":"󰋼","label":"Status","action":"omarchy-launch-floating-terminal-with-presentation \"$HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets status; read -n1 -s -r -p 'press any key'\""},
  "household.widgets.enabled": {"icon":"󰔡","label":"Enabled","checked":"$HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets status --enabled","action":"$HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets toggle"},
  "household.widgets.restart": {"icon":"","label":"Restart shell","action":"omarchy-restart-shell","description":"needed after code changes"},
```

The menu file hot-reloads. Absolute paths via `$HOME` because the shell's environment is not guaranteed to include `~/.local/bin`.

- [ ] **Step 2: Live check**: open the menu (`omarchy-shell shell toggle omarchy.menu '{"menu":"household"}'`), confirm the Desktop widgets submenu lists four rows and Enabled shows ✓. Trigger Status and Edit once each. Trigger Enabled twice (off, then on) and confirm layers return.

- [ ] **Step 3: README** — add the snippet under a "## Omarchy menu" heading.

- [ ] **Step 4: Vault** — in the Tool Guide add a "## CLI and menu" section (install line, command list, comment rule, menu rows); update the "Where it's going" paragraph to say Phase 1 done, Phase 2 native panel next; board: clear the claim, add a Recently done line; memory file: Phase 1 done + CLI path.

- [ ] **Step 5: Commit and push**

```bash
git add README.md docs/superpowers/plans/2026-09-09-phase1-registry-cli.md
git commit -m "Household menu rows for desktop widgets; Phase 1 complete"
git push origin master
```

Mark every Status row done.

---

## Self-review notes

- Spec coverage: registry (T1), JSONC (T2, T4), defaults in the service (T3), `.bak` + atomic writes (T5, T6), CLI surface list/add/set/move/enable/disable/remove/duplicate/types/validate/edit/status (T4–T6), Household menu rows (T7), README (T3, T6, T7). The ROADMAP's `desktop-widgets status` "last log lines" is in T6.
- Message parity: the JS and Python engines emit identical strings; the fixtures assert on exact text so drift fails both suites.
- Known gap by design: a `type` field value for `align: "auto"` changes nothing visible (T3 handles it). `enum` on `agent` restricts to claude/codex; any other collector record would need a registry edit — acceptable, the registry is the point.
