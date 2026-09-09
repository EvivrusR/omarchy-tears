# Desktop Widgets Phase 3b: `template` Widget Type — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A widget type that needs no QML: a command prints JSON, and rows described in the config (heading, text, key/value, bar, spacer) render from it with `{placeholders}`.

**Architecture:** `widgets/Template.js` (pure, node-tested) parses command output and renders placeholders with a small filter set. `widgets/TemplateWidget.qml` runs the command on an interval like the command widget and draws the rows through a `Repeater` + `Loader` per row kind. The registry gains a `rows` field type; both validators check it (array of objects with a known `kind`); the editor gets a compact rows editor for that type.

**Spec:** `docs/ROADMAP.md` → Phase 3 "New parts without QML", route 1.

## Status (handoff block — update after every task)

**PHASE 3b COMPLETE 2026-09-09.** Watch item: one quickshell SIGSEGV (coredump PID 320027, 20:45:30 JST, abort inside Quickshell's QQmlComponent finalize → dynamic_cast) in the shell that was starting during the Task 3 restart, right after the first template widget was added. Not reproduced across later restarts and many widget rebuilds. If it recurs, run the `diagnose-crash` skill on the dump before changing code. Remaining Phase 3: drop-in custom widget types. Phase 4 (share) awaits go.

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 Template.js (parse, placeholders, filters, bar value) + tests | done | 65c97eb | 5 tests |
| 2 Registry `rows` type in JS + Python validators, fixtures | done | 42554fc | 2 new fixtures, both engines |
| 3 TemplateWidget.qml + Service/Loader hook + example + live check | done | 2ba1ede | live: load-average template renders; failing command keeps values + red !; fixed Qt-list arrays (also affected stats `show`) |
| 4 Editor rows control + README/vault/status | done | 28c5e89 | rows editor renders; not yet hand-tested by a human |

**How to resume:** read this file; run `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -p 'test_*.py'`; continue at the first task not done. Code changes need `omarchy restart shell`.

## Global Constraints

- Same as earlier phases. No new runtime dependencies; the command is the user's own.
- Placeholder syntax is `{path}` or `{path|filter}` / `{path|filter:arg}`. Unresolvable → `—`. Literal braces via `{{` and `}}`.
- Output that is not a JSON object is still usable as `{output}` (trimmed text) and `{lines.N}`.

---

## Contract

```json
{ "type": "template", "corner": "bottom-right",
  "command": "python3 -c 'import json,os; l=os.getloadavg(); print(json.dumps({\"l1\":l[0],\"l5\":l[1],\"cpus\":os.cpu_count()}))'",
  "intervalSec": 10, "timeoutSec": 10,
  "rows": [
    { "kind": "heading", "text": "SYSTEM" },
    { "kind": "kv",      "label": "load",  "value": "{l1|fixed:2} / {l5|fixed:2}" },
    { "kind": "bar",     "label": "1 min", "value": "{l1}", "max": "{cpus}", "warnAt": 0.9 },
    { "kind": "text",    "text": "{cpus} cpus" },
    { "kind": "spacer" }
  ] }
```

Row kinds and keys:

| kind | keys | renders |
|---|---|---|
| `heading` | `text` | caption, letter-spaced, muted colour |
| `text` | `text` | body text (multi-line allowed) |
| `kv` | `label`, `value`, `labelWidth` (px, min) | label left (muted), value right |
| `bar` | `label`, `value` (numeric, for the meter), `text` (display, default = value), `max` (default `100`), `min` (default `0`), `warnAt` (fraction 0..1, default `0.9`), `suffix`, `labelWidth` | label, meter, number |
| `spacer` | `height` (px, default `6`) | vertical gap |

Filters: `fixed:N`, `round`, `int`, `pct` (×100, `fixed:0`, `%`), `upper`, `lower`, `default:TEXT` (used when the path is missing), `human` (1234567 → `1.2M`), `secs` (seconds → `1h 02m`).

---

### Task 1: Template.js

**Files:** Create `widgets/Template.js`, `tests/template.test.js`.

**Interfaces:**
- `Template.parseOutput(text) -> object` — JSON object → as is (plus `output` and `lines`); JSON non-object or non-JSON → `{ output, lines }`.
- `Template.get(data, path) -> any|undefined` — dotted path with numeric indices.
- `Template.render(text, data) -> string`.
- `Template.number(text, data, fallback) -> number` — renders then parses a float.
- `Template.barFraction(row, data) -> number` 0..1 or `-1` when unavailable.

- [ ] **Step 1: tests**

```js
const test = require("node:test");
const assert = require("node:assert/strict");
const T = require("../widgets/Template.js");

test("parseOutput keeps JSON objects and adds output/lines", () => {
  const d = T.parseOutput('{"a":1,"b":{"c":[10,20]}}\n');
  assert.equal(d.a, 1); assert.equal(d.b.c[1], 20);
  assert.equal(d.output, '{"a":1,"b":{"c":[10,20]}}');
  assert.deepEqual(d.lines, ['{"a":1,"b":{"c":[10,20]}}']);
});

test("parseOutput wraps non-JSON and non-object JSON", () => {
  assert.deepEqual(T.parseOutput("up 3 hours\nsecond\n"), { output: "up 3 hours\nsecond", lines: ["up 3 hours", "second"] });
  assert.deepEqual(T.parseOutput("[1,2]"), { output: "[1,2]", lines: ["[1,2]"] });
  assert.deepEqual(T.parseOutput(""), { output: "", lines: [] });
});

test("get walks dotted paths and indices", () => {
  const d = { a: { b: [{ n: "x" }] }, lines: ["l0", "l1"] };
  assert.equal(T.get(d, "a.b.0.n"), "x");
  assert.equal(T.get(d, "lines.1"), "l1");
  assert.equal(T.get(d, "a.zz"), undefined);
  assert.equal(T.get(null, "a"), undefined);
});

test("render substitutes, applies filters, and handles missing values", () => {
  const d = { rated: 1181, loved: 635, rate: 0.5376, big: 1234567, t: 3725, name: "teto" };
  assert.equal(T.render("{rated} rated · {loved} loved", d), "1181 rated · 635 loved");
  assert.equal(T.render("{rate|pct}", d), "54%");
  assert.equal(T.render("{rate|fixed:1}", d), "0.5");
  assert.equal(T.render("{rate|round}", d), "1");
  assert.equal(T.render("{rate|int}", d), "0");
  assert.equal(T.render("{name|upper} {name|lower}", d), "TETO teto");
  assert.equal(T.render("{big|human}", d), "1.2M");
  assert.equal(T.render("{t|secs}", d), "1h 02m");
  assert.equal(T.render("{missing}", d), "—");
  assert.equal(T.render("{missing|default:none}", d), "none");
  assert.equal(T.render("{{literal}} {rated}", d), "{literal} 1181");
  assert.equal(T.render("plain", d), "plain");
});

test("number and barFraction", () => {
  const d = { l1: 1.5, cpus: 4, pct: 87 };
  assert.equal(T.number("{l1}", d, 0), 1.5);
  assert.equal(T.number("{nope}", d, 7), 7);
  assert.equal(T.number("12", d, 0), 12);
  assert.equal(T.barFraction({ value: "{l1}", max: "{cpus}" }, d), 0.375);
  assert.equal(T.barFraction({ value: "{pct}" }, d), 0.87);
  assert.equal(T.barFraction({ value: "{pct}", min: "80", max: "90" }, d), 0.7);
  assert.equal(T.barFraction({ value: "{nope}" }, d), -1);
  assert.equal(T.barFraction({ value: "{pct}", max: "50" }, d), 1);
});
```

- [ ] **Step 2: run → fails.**
- [ ] **Step 3: implement** (see the file in the repo; ~90 lines).
- [ ] **Step 4: tests pass; commit** `"Template.js: command-output parsing, placeholders with filters, bar fractions"`.

---

### Task 2: Registry `rows` type

**Files:** Modify `widgets/registry.json`, `widgets/Registry.js`, `bin/desktop-widgets`, `tests/fixtures/validate/template.json` (new), `tests/fixtures/validate/bad-rows.json` (new).

- Registry entry:

```json
"template": {
  "displayName": "Template",
  "description": "Rows rendered from a command's JSON output with {placeholders}.",
  "fields": [
    { "key": "command", "type": "command", "label": "Command", "default": "", "description": "Should print a JSON object; plain text is available as {output} and {lines.N}" },
    { "key": "intervalSec", "type": "integer", "label": "Refresh (s)", "default": 60, "min": 1, "max": 86400 },
    { "key": "timeoutSec", "type": "integer", "label": "Timeout (s)", "default": 10, "min": 1, "max": 600 },
    { "key": "maxWidth", "type": "integer", "label": "Max width (px)", "default": 420, "min": 40, "max": 4000 },
    { "key": "rows", "type": "rows", "label": "Rows", "default": [], "options": ["heading", "text", "kv", "bar", "spacer"], "description": "Each row: kind + its keys; text/label/value take {placeholders}" }
  ]
}
```

- Validation (both engines): `rows` must be a list; each item an object with `kind` in `options`; message forms: `rows must be a list`, `rows.N must be an object`, `rows.N has unknown kind 'x'`.
- Fixtures: `template.json` (valid, 0 errors), `bad-rows.json` (3 errors as above).
- `apply_defaults`/`applyDefaults` need no change. `summarize()` in the CLI: `template` → first heading text or row count.
- Commit `"Registry: template type with rows field validated by both engines"`.

---

### Task 3: TemplateWidget.qml

**Files:** Create `widgets/TemplateWidget.qml`; Modify `Service.qml` (Loader switch), `desktop-widgets.example.jsonc`, `README.md` (types list).

- Same Process/Timer shape as `CommandWidget.qml` (`bash -lc` under `timeout`), `data` = `Template.parseOutput(stdout)`; non-zero exit keeps the last data and sets `failed`.
- Rows via `Repeater { model: config.rows }` with a `Loader` choosing a component per `kind`; every text uses `WidgetText` with the card's outline/halo; bars reuse the stats bar look (track + fill in `textColor`, `Color.urgent` above `warnAt`).
- Live check: add the load-average example to the live config, restart, see rows and a bar; break the command (exit 1) → red `!`, last values stay; non-JSON command → `{output}` renders.
- Commit `"Template widget: rows from a command's JSON"`.

---

### Task 4: Editor rows control, docs

**Files:** Modify `editor/FieldControl.qml` (new `rows` component), `README.md`, vault guide, this plan.

- Rows control: a `ColumnLayout` of row editors: `Dropdown` for `kind`, then the kind's keys as `TextField`s (`heading`/`text`: text; `kv`: label, value; `bar`: label, value, max, warnAt; `spacer`: height), `✕` to remove, `+ row` to append, `↑`/`↓` to reorder. Every edit emits `edited("rows", newArray)`.
- README "Template widgets" section with the contract table and two examples (load average; Curator via `curator-cli`); vault guide section; status table; DQ-025 tick.
- Commit `"Editor: rows control for template widgets; docs — Phase 3b complete"`; push.
