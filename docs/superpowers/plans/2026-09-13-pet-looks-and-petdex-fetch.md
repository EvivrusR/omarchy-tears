# Pet looks, look rules and the petdex fetcher — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pet reports which looks its sheet actually has; users pick when each look plays with structured rows (brackets, flags, keywords, another pet) instead of hand-written expressions; a petdex.dev URL pasted into the editor (or the CLI) downloads the pet into the right folder.

**Architecture:** Structured rule rows *compile* into the existing `when`/`on` rules and run through the unchanged `Pet.step` engine (one evaluator, one tested path; raw rows stay for power users). The compiler, the validator and the preset rows exist in both engines — `widgets/Pet.js` (shell) and `bin/desktop-widgets` (CLI, stdlib Python) — kept identical by shared fixtures under `tests/fixtures/rules/`. Signals are sampled once per service tick (one `dw-signals` process for every pet, with the union of the pets' custom commands) and pushed to the pets. The petdex installer script is parsed as a manifest, never executed; the shell does no networking — the editor's Download button runs the CLI.

**Tech Stack:** Quickshell QML (Omarchy 4.x shell, `qs.Ui` controls), plain JS (`node --test`), Python 3 stdlib (`unittest`), ImageMagick `magick` optional at runtime for pixel probes.

**Spec:** `docs/superpowers/specs/2026-09-10-pet-looks-and-petdex-fetch-design.md`. Michael's decisions (2026-09-13): (1) compile structured rows onto the existing engine; (2) shared sampler + custom command signals **now**; (3) licence on fetch = best-effort label, shown, **no gate**; (4) the editor's Download points the selected pet's `sheet` at the download; the CLI has both `--add` and `--widget N`.

## Global Constraints

- Python 3 standard library only in `bin/*` (Omarchy ships Python; no Pillow, no node guaranteed). `magick` may be used when present, never required.
- One writer: every config write goes through `desktop-widgets write` / the `mutate()` helpers. Nothing in the shell writes the file.
- JS and Python engines must agree: every rule fixture in `tests/fixtures/rules/` is run by both `tests/pet.test.js` and `tests/test_cli.py`.
- Code changes need `omarchy restart shell` (validate `manifest.json` first: `python3 -c 'import json;json.load(open("manifest.json"))'`); config changes hot-reload.
- Run **both** suites and read **both** summary lines before every commit: `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -v 2>&1 | tail -3`.
- Never write under the plugin checkout at runtime (petdex art lands in `~/.config/omarchy/desktop-widgets.pets/<slug>/`).
- Branch: `feat/pet-looks-petdex` (already exists, docs-only). Commit per task. Push both remotes (`origin` Forge when reachable, `github`). Do not merge to master; do not bump `manifest.json` version (Michael merges + tags).
- A pet must never crash the shell: the evaluator's `try/catch` stays; errors surface through `validateRules` only.
- Sheet contract: cells 192×208, 8 columns, height = k×208 with k in 8..11; rows past 9 are `extra…`.

---

## File map

| File | Responsibility after this plan |
|---|---|
| `widgets/Pet.js` | evaluator (+ `~`), `LOOKS`/fallback chain, `trimInfo`, `looks()`, `rowFor(…, present)`, `compileRule(s)`, `WATCH` as structured rows, `presetRows()`, `validateRules()`, lost-beat-safe `step` |
| `widgets/PetWidget.qml` | uses service-published signals when a service is injected (own process otherwise), publishes `looks`, row lookup honours `present` |
| `Service.qml` | one `dw-signals` sampler for all pets (`signals`, `signalCommands`), unchanged `petStates` |
| `bin/dw-signals` | `--command key=<shell>` → `custom.<key>` |
| `bin/desktop-widgets` | Python twin of compiler/validator/presets; `pet expand|check|fetch`; `pets --looks`; image header parse; petdex fetch |
| `widgets/registry.json` | `rules` row kinds + `rowFields`; `signals` rows field; `petdex` field type |
| `editor/FieldControl.qml` | per-key row controls (look/pet/signal dropdowns, toggle, numbers), kind-specific add buttons, warnings; `petdex` control |
| `editor/EditorForm.qml` | passes `rowContext` (looks/signals/pets) + rule warnings to fields; "Customise these rules" button under `watch`; looks line under `sheet` |
| `Editor.qml` | computes `rowContext` from the service's `petStates` and the selected entry |
| `tests/fixtures/rules/*.json` | shared compiler/validator fixtures + `presets.json` |
| `tests/pet.test.js`, `tests/test_cli.py`, `tests/test_signals.py` | tests |
| `README.md`, `CHANGELOG.md`, vault guide | docs |

---

### Task 1: Looks inventory in `Pet.js`

**Files:**
- Modify: `widgets/Pet.js` (sheet section, lines ~120–140, and exports)
- Test: `tests/pet.test.js`

**Interfaces:**
- Produces: `LOOKS = ["idle","running","waving","jumping","failed","waiting","review"]`; `FALLBACK = { jumping:["waving","idle"], waiting:["review","idle"], failed:["waiting","idle"], running:["idle"], review:["idle"], waving:["idle"], idle:[] }`; `trimInfo(maxAlphaPerCell, rows) → { counts:number[], present:boolean[] }` (`counts` identical to `trimCounts`); `looks(sheetHeight, info) → [{ name, row, frames, present }]` (one entry per user-facing look, `running` collapsed from rows 1/2/7 on Codex sheets, extras kept as `extra1…`); `rowFor(state, sheetHeight, facingLeft, present)` where `present` is the optional boolean array — when given and the target row is absent, walk `FALLBACK`; `resolveLook(state, presentNames) → name` (the look actually shown).

- [ ] **Step 1: Write the failing tests** (append to `tests/pet.test.js`)

```js
test("trimInfo reports frames and presence per row; looks collapses running rows and keeps extras", () => {
  // 9-row codex sheet: row 4 (jumping) fully blank, row 2 (running-left) blank, row 7 (running) has 6 frames
  const alpha = []; for (let r = 0; r < 9; r++) for (let c = 0; c < 8; c++) alpha.push((r === 4 || r === 2) ? 0 : (c < 6 ? 255 : 0));
  const info = P.trimInfo(alpha, 9);
  assert.deepEqual(info.counts, P.trimCounts(alpha, 9));
  assert.equal(info.present[4], false); assert.equal(info.present[0], true); assert.equal(info.present[2], false);
  const L = P.looks(1872, info);
  assert.deepEqual(L.map((l) => l.name), ["idle", "running", "waving", "jumping", "failed", "waiting", "review"]);
  const byName = Object.fromEntries(L.map((l) => [l.name, l]));
  assert.equal(byName.jumping.present, false); assert.equal(byName.running.present, true); assert.equal(byName.running.frames, 6); assert.equal(byName.running.row, 7);
  assert.equal(L.filter((l) => l.present).length, 6);
  // legacy 8-row sheet keeps extra1/extra2
  const a8 = []; for (let r = 0; r < 8; r++) for (let c = 0; c < 8; c++) a8.push(c < 4 ? 255 : 0);
  assert.deepEqual(P.looks(1664, P.trimInfo(a8, 8)).map((l) => l.name), ["idle", "waving", "running", "failed", "review", "jumping", "extra1", "extra2"]);
  // 11-row ChatGPT export: rows past 9 are extras
  const a11 = []; for (let r = 0; r < 11; r++) for (let c = 0; c < 8; c++) a11.push(255);
  assert.deepEqual(P.looks(2288, P.trimInfo(a11, 11)).map((l) => l.name).slice(7), ["extra10", "extra11"]);
});

test("rowFor falls back along the chain when a look is missing, and resolveLook names what is shown", () => {
  const present = [true, true, false, true, false, true, false, true, true];   // jumping (4) and waiting (6) absent
  assert.equal(P.rowFor("jumping", 1872, false, present), 3);                  // → waving
  assert.equal(P.rowFor("waiting", 1872, false, present), 8);                  // → review
  assert.equal(P.rowFor("failed", 1872, false, present), 5);                   // present, unchanged
  assert.equal(P.rowFor("jumping", 1872), 4);                                  // no presence info: old behaviour
  const noWave = present.slice(); noWave[3] = false;
  assert.equal(P.rowFor("jumping", 1872, false, noWave), 0);                   // waving gone too → idle
  assert.equal(P.rowFor("running", 1872, true, [true, false, false, true, true, true, true, true, true]), 7); // running-left absent → row 7 (flip handles direction)
  assert.equal(P.resolveLook("jumping", ["idle", "waving"]), "waving");
  assert.equal(P.resolveLook("failed", ["idle"]), "idle");
  assert.equal(P.resolveLook("waving", ["idle", "waving"]), "waving");
});

test("uniqueNames gives later pets on the same sheet a numbered name", () => {
  const cfgs = [{ type: "pet", sheet: "/p/teto/spritesheet.webp" }, { type: "clock" }, { type: "pet", sheet: "/q/teto/spritesheet.webp" }, { type: "pet", name: "teto" }, { type: "pet", name: "Jill" }];
  assert.deepEqual(P.uniqueNames(cfgs), ["teto", null, "teto_2", "teto_3", "jill"]);
  assert.deepEqual(P.uniqueNames([]), []);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/.config/omarchy/plugins/homelab.desktop-widgets && node --test tests/pet.test.js 2>&1 | tail -8`
Expected: 2 failing tests (`P.trimInfo is not a function`).

- [ ] **Step 3: Implement** — replace the sheet section of `widgets/Pet.js` (from `var CODEX_ROWS` down to and including `trimCounts`) with:

```js
var CODEX_ROWS = ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"]
var LEGACY_ROWS = ["idle", "waving", "running", "failed", "review", "jumping", "extra1", "extra2"]
var LOOKS = ["idle", "running", "waving", "jumping", "failed", "waiting", "review"]
// A look the sheet lacks falls back along this chain, never silently to row 0.
var FALLBACK = { jumping: ["waving", "idle"], waiting: ["review", "idle"], failed: ["waiting", "idle"], running: ["idle"], review: ["idle"], waving: ["idle"], idle: [] }
function rowNames(sheetHeight) {
  var n = Math.round(sheetHeight / FRAME_H)
  if (n === 8) return LEGACY_ROWS
  var rows = CODEX_ROWS.slice()
  for (var r = 10; r <= n; r++) rows.push("extra" + r)      // 10-/11-row exports: rows past 9 are extras
  return rows
}
function rowIndex(name, rows, present) {
  var i = rows.indexOf(name)
  return i === -1 || (present && present[i] === false) ? -1 : i
}
function rowFor(state, sheetHeight, facingLeft, present) {
  var rows = rowNames(sheetHeight), s = String(state)
  var alias = { run: "running", wave: "waving", jump: "jumping" }
  s = alias[s] || s
  var chain = [s].concat(FALLBACK[s] || ["idle"])
  for (var k = 0; k < chain.length; k++) {
    var want = chain[k], i = -1
    if (want === "running") {
      if (facingLeft) i = rowIndex("running-left", rows, present)
      if (i === -1) i = rowIndex("running", rows, present)
      if (i === -1) i = rowIndex("running-right", rows, present)
    } else i = rowIndex(want, rows, present)
    if (i !== -1) return i
  }
  return 0
}
// Which look is actually shown for `state` given the present look names.
function resolveLook(state, presentNames) {
  var s = String(state), chain = [s].concat(FALLBACK[s] || ["idle"])
  for (var k = 0; k < chain.length; k++) if (!presentNames || presentNames.indexOf(chain[k]) !== -1) return chain[k]
  return "idle"
}
// Trailing blank cells (max alpha ≤ 8) are padding: count the real frames per row.
function trimInfo(maxAlphaPerCell, rows) {
  var counts = [], present = []
  for (var r = 0; r < rows; r++) {
    var n = 0
    for (var c = 0; c < COLS && c < FRAMES + 2; c++) { var a = maxAlphaPerCell[r * COLS + c]; if (a !== undefined && a > 8) n = c + 1 }
    counts.push(Math.max(1, n)); present.push(n > 0)
  }
  return { counts: counts, present: present }
}
function trimCounts(maxAlphaPerCell, rows) { return trimInfo(maxAlphaPerCell, rows).counts }
// User-facing looks: one per row, except running-right/left/running collapse into `running`.
function looks(sheetHeight, info) {
  var rows = rowNames(sheetHeight), out = [], counts = info && info.counts ? info.counts : [], present = info && info.present ? info.present : []
  function entry(name, row) { return { name: name, row: row, frames: counts[row] || FRAMES, present: present[row] !== false && present[row] !== undefined ? true : present[row] === undefined && !info ? true : !!present[row] } }
  if (rows === LEGACY_ROWS) { for (var r = 0; r < rows.length; r++) out.push(entry(rows[r], r)); return out }
  var runRow = -1
  for (var i = 0; i < rows.length; i++) {
    var name = rows[i]
    if (name === "running" || name === "running-right" || name === "running-left") { if (present[i] !== false && (runRow === -1 || name === "running")) runRow = runRow === -1 || name === "running" ? i : runRow; continue }
    out.push(entry(name, i))
  }
  var run = runRow === -1 ? { name: "running", row: 7, frames: FRAMES, present: false } : entry("running", runRow)
  run.present = runRow !== -1
  out.splice(1, 0, run)
  return out
}
```

And after `petName`, the collision fix (spec §2 issue 3 — two pets on the same sheet folder used to overwrite each other's published state):

```js
// Published names for a whole widget list: non-pets are null; a repeated name becomes name_2, name_3…
function uniqueNames(configs) {
  var seen = {}, out = []
  for (var i = 0; i < (configs || []).length; i++) {
    var c = configs[i]
    if (!c || String(c.type) !== "pet") { out.push(null); continue }
    var base = petName(c), n = (seen[base] || 0) + 1
    seen[base] = n
    out.push(n === 1 ? base : base + "_" + n)
  }
  return out
}
```

Update the exports line to add `LOOKS, FALLBACK, trimInfo, looks, resolveLook, uniqueNames`.

- [ ] **Step 4: Run tests**

Run: `node --test tests/pet.test.js 2>&1 | tail -8`
Expected: all pass (existing `trimCounts`/`rowFor` tests unchanged).

- [ ] **Step 5: Commit**

```bash
git add widgets/Pet.js tests/pet.test.js
git commit -m "Pet.js: looks inventory (trimInfo/looks), fallback chain in rowFor, resolveLook"
```

---

### Task 2: Widget publishes looks; row lookup honours presence

**Files:**
- Modify: `widgets/PetWidget.qml`
- Modify: `Editor.qml`, `editor/EditorForm.qml` (looks line under `sheet`)

**Interfaces:**
- Consumes: `Pet.trimInfo`, `Pet.looks`, `Pet.rowFor(state, h, flip, present)`.
- Produces: `service.petStates[name].looks` = the `looks()` array (so the editor and other pets read it); `PetWidget.present` (bool array); EditorForm `property var looks: null`.

- [ ] **Step 1: PetWidget.qml** — replace `property var counts: []` with:

```qml
  property var counts: []
  property var present: []
  readonly property var looksList: Pet.looks(sheetRows * Pet.FRAME_H, { counts: counts, present: present })
  readonly property int row: Pet.rowFor(petState, sheetRows * Pet.FRAME_H, flip, present.length ? present : null)
```
(delete the old `readonly property int row:` line). In `publish()` send `{ state: petState, say: say, watch: watch, looks: looksList }`. In the Canvas `onImageLoaded`, replace `root.counts = Pet.trimCounts(alpha, rows)` with:
```qml
      var info = Pet.trimInfo(alpha, rows)
      root.counts = info.counts; root.present = info.present
      root.publish()
```
In the `Layer` component, `lrow` becomes `Pet.rowFor(root.petState, root.sheetRows * Pet.FRAME_H, root.flip, root.present.length ? root.present : null)`.

- [ ] **Step 1b: Unique published names** — `Service.qml`, next to `petStates`:

```qml
  // pets.<name> keys: a second pet on the same sheet folder publishes as name_2 (not over the first).
  readonly property var petNames: Pet.uniqueNames(widgets)
  function petNameFor(index) { var n = petNames[Number(index)]; return n || null }
```
(add `import "widgets/Pet.js" as Pet` to Service.qml). In `PetWidget.qml`: `readonly property string petName: service && service.petNameFor(config.__index) ? service.petNameFor(config.__index) : Pet.petName(config)`.

- [ ] **Step 2: EditorForm.qml** — add `property var looks: null`, `property string publishedName: ""` and, inside the Repeater delegate after `FieldControl { … }`, a caption shown under the sheet field plus a collision note under `name`:

```qml
        Text {
          visible: modelData.key === "name" && root.publishedName !== "" && root.publishedName !== Pet.petName(root.entry)
          Layout.fillWidth: true; Layout.leftMargin: Style.space(190) + Style.spacing.md
          wrapMode: Text.WordWrap; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption
          text: "another pet is already '" + Pet.petName(root.entry) + "' — this one publishes as pets." + root.publishedName + " (give it a name to pick your own)"
        }
```
(with `import "../widgets/Pet.js" as Pet` in EditorForm.) Editor.qml passes `publishedName: root.selected >= 0 ? (Pet.uniqueNames(root.doc)[root.selected] || "") : ""`; `petRowContext` (Task 7) uses `Pet.uniqueNames(doc)` for `me` and the other pets' names instead of raw `petName`.

Sheet-field caption:

```qml
        Text {
          visible: modelData.key === "sheet" && root.entry && String(root.entry.type) === "pet"
          Layout.fillWidth: true; Layout.leftMargin: Style.space(190) + Style.spacing.md
          wrapMode: Text.WordWrap; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption
          text: {
            if (!root.looks) return "Looks: idle, running, waving, jumping, failed, waiting, review (contract; measured once the pet renders)"
            var have = root.looks.filter(function(l) { return l.present })
            return "Looks: " + have.map(function(l) { return l.name + " ×" + l.frames }).join(", ") + " (" + have.length + " of " + root.looks.length + ")"
          }
        }
```

- [ ] **Step 3: Editor.qml** — add `import "widgets/Pet.js" as Pet` next to the other imports, and pass the looks into the form:

```qml
              EditorForm {
                …
                looks: root.selectedEntry && String(root.selectedEntry.type) === "pet" && root.service && root.service.petStates[Pet.petName(root.selectedEntry)] ? (root.service.petStates[Pet.petName(root.selectedEntry)].looks || null) : null
```

- [ ] **Step 4: Live check**

```bash
python3 -c 'import json;json.load(open("manifest.json"))' && omarchy restart shell
sleep 4; journalctl --user _COMM=quickshell --since "-30s" | grep -i 'desktop-widgets\|PetWidget\|EditorForm' | tail -5
omarchy-shell shell toggle homelab.desktop-widgets '{}'; sleep 1
omarchy-shell shell call homelab.desktop-widgets call '{"op":"select","index":<index of a pet>}'
```
Expected: no QML errors in the journal; the editor shows "Looks: idle ×6, … (N of 9)" under the sheet field for a pet. Close the editor (`omarchy-shell shell call homelab.desktop-widgets call '{"op":"revert"}'` then toggle).

- [ ] **Step 5: Commit**

```bash
git add widgets/PetWidget.qml editor/EditorForm.qml Editor.qml
git commit -m "Pet widget publishes its looks; editor shows them under the sheet field; missing looks fall back"
```

---

### Task 3: Rule compiler, `~` operator, presets as rows, validator, lost-beat fix (JS)

**Files:**
- Modify: `widgets/Pet.js` (evaluator `tokenize`/`cmp`, `WATCH`, `rulesFor`, `step`; new `compileRule`, `compileRules`, `presetRows`, `validateRules`, `SIGNAL_KEYS`, `SIGNAL_GROUPS`)
- Create: `tests/fixtures/rules/presets.json`, `tests/fixtures/rules/compile-basic.json`, `tests/fixtures/rules/validate-basic.json`
- Test: `tests/pet.test.js`

**Interfaces:**
- Produces:
  - `evalExpr` gains `~` (case-insensitive substring; `null ~ x` is false).
  - `compileRule(row) → { kind:"when"|"on", if, state, beat, say } | null` per the table below; `compileRules(rows) → rule[]` (nulls dropped).
  - `WATCH` = `{ claude|battery|agents|cpu|mem|gpu: structuredRow[] }`; `presetRows(watch) → deep copy of WATCH[watch] or []`; `rulesFor(watch, custom)` returns **compiled** rules in both cases.
  - `SIGNAL_KEYS = ["claude.session","claude.weekly","claude.resetInMin","claude.label","battery.pct","battery.status","battery.charging","battery.discharging","battery.full","agents.active","cpu","mem","gpu","load","temp","hour"]`.
  - `validateRules(rows, ctx) → [{ row, message }]` with `ctx = { looks: string[]|null, signals: string[]|null, pets: string[]|null }` (null = don't check that dimension).
  - `step` never swallows a rising edge that arrives during another beat.

Compilation table (from the spec):

| row kind | `if` |
|---|---|
| `range` (`signal`, `min`?, `max`?) | both: `(sig >= min && sig < max)`; `min > max`: `(sig >= min \|\| sig < max)` (wraps midnight); only min: `sig >= min`; only max: `sig < max`; neither: `sig != null` |
| `flag` (`signal`, `is`) | `sig == true` or `sig == false` |
| `keyword` (`signal`, `words`, `match`) | words split on `,`, trimmed, single quotes stripped; any: `(sig ~ 'a' \|\| sig ~ 'b')`, all: `&&`, none: `!(… \|\| …)`; no words → `false` |
| `pet` (`pet`, `look`, `then`, `beat`?) | `pets.<petkey>.state == '<look>'`, state = `then` |
| any structured row with `and` | `<test> && (<and>)` |
| any structured row with `beat` > 0 | kind `on`, else `when` |
| `when` / `on` | passed through (`if`, `state`, `beat`, `say`) |

`state` for range/flag/keyword rows is the row's `look`.

- [ ] **Step 1: Write the fixtures**

`tests/fixtures/rules/presets.json` — the contract both engines must equal:

```json
{
  "claude": [
    { "kind": "range", "signal": "claude.resetInMin", "min": 200, "look": "jumping", "beat": 2.2, "say": "fresh session!" },
    { "kind": "range", "signal": "claude.session", "min": 95, "look": "failed", "say": "session cap {claude.session}%" },
    { "kind": "range", "signal": "claude.session", "min": 80, "look": "waiting", "say": "{claude.session}% used" },
    { "kind": "range", "signal": "agents.active", "min": 1, "look": "running", "say": "" },
    { "kind": "range", "signal": "claude.session", "min": 50, "look": "review", "say": "{claude.session}%" }
  ],
  "battery": [
    { "kind": "flag", "signal": "battery.full", "is": true, "look": "waving", "beat": 2.2, "say": "full!" },
    { "kind": "range", "signal": "battery.pct", "max": 10, "and": "battery.discharging", "look": "failed", "say": "{battery.pct}%!" },
    { "kind": "range", "signal": "battery.pct", "max": 20, "and": "battery.discharging", "look": "waiting", "say": "{battery.pct}%" },
    { "kind": "flag", "signal": "battery.charging", "is": true, "look": "running", "say": "" }
  ],
  "agents": [
    { "kind": "range", "signal": "agents.active", "max": 1, "look": "waving", "beat": 2.2, "say": "all done" },
    { "kind": "range", "signal": "agents.active", "min": 1, "look": "running", "say": "{agents.active} working" }
  ],
  "cpu": [
    { "kind": "range", "signal": "cpu", "min": 95, "look": "failed", "say": "cpu {cpu}%" },
    { "kind": "range", "signal": "cpu", "min": 60, "look": "running", "say": "cpu {cpu}%" },
    { "kind": "range", "signal": "cpu", "min": 30, "look": "review", "say": "" }
  ],
  "mem": [
    { "kind": "range", "signal": "mem", "min": 95, "look": "failed", "say": "mem {mem}%" },
    { "kind": "range", "signal": "mem", "min": 80, "look": "waiting", "say": "mem {mem}%" },
    { "kind": "range", "signal": "mem", "min": 50, "look": "review", "say": "" }
  ],
  "gpu": [
    { "kind": "range", "signal": "gpu", "min": 95, "look": "failed", "say": "gpu {gpu}%" },
    { "kind": "range", "signal": "gpu", "min": 60, "look": "running", "say": "gpu {gpu}%" },
    { "kind": "range", "signal": "gpu", "min": 30, "look": "review", "say": "" },
    { "kind": "when", "if": "gpu == null", "state": "idle", "say": "no gpu here" }
  ]
}
```

`tests/fixtures/rules/compile-basic.json`:

```json
{
  "rows": [
    { "kind": "range", "signal": "battery.pct", "max": 10, "look": "failed", "say": "{battery.pct}%!" },
    { "kind": "range", "signal": "hour", "min": 23, "max": 6, "look": "waiting", "say": "zzz" },
    { "kind": "range", "signal": "cpu", "min": 30, "max": 60, "look": "review" },
    { "kind": "range", "signal": "gpu", "look": "idle" },
    { "kind": "flag", "signal": "battery.charging", "is": true, "look": "running" },
    { "kind": "flag", "signal": "battery.discharging", "is": false, "look": "idle" },
    { "kind": "keyword", "signal": "custom.window", "words": "youtube, netflix", "match": "any", "look": "review", "say": "slacking?" },
    { "kind": "keyword", "signal": "claude.label", "words": "session,5-hour", "match": "all", "look": "review" },
    { "kind": "keyword", "signal": "claude.label", "words": "it's", "match": "none", "look": "idle" },
    { "kind": "keyword", "signal": "claude.label", "words": "", "look": "idle" },
    { "kind": "pet", "pet": "Jill", "look": "failed", "then": "waving", "beat": 2, "say": "you ok?" },
    { "kind": "pet", "pet": "jill", "look": "running", "then": "running" },
    { "kind": "range", "signal": "mem", "min": 90, "and": "cpu > 50", "look": "failed" },
    { "kind": "when", "if": "cpu >= 95", "state": "failed", "say": "cpu {cpu}%" },
    { "kind": "on", "if": "agents.active == 0", "state": "waving", "beat": 1.5 },
    { "kind": "bogus" },
    "not a row"
  ],
  "expect": [
    { "kind": "when", "if": "battery.pct < 10", "state": "failed", "say": "{battery.pct}%!" },
    { "kind": "when", "if": "(hour >= 23 || hour < 6)", "state": "waiting", "say": "zzz" },
    { "kind": "when", "if": "(cpu >= 30 && cpu < 60)", "state": "review", "say": "" },
    { "kind": "when", "if": "gpu != null", "state": "idle", "say": "" },
    { "kind": "when", "if": "battery.charging == true", "state": "running", "say": "" },
    { "kind": "when", "if": "battery.discharging == false", "state": "idle", "say": "" },
    { "kind": "when", "if": "(custom.window ~ 'youtube' || custom.window ~ 'netflix')", "state": "review", "say": "slacking?" },
    { "kind": "when", "if": "(claude.label ~ 'session' && claude.label ~ '5-hour')", "state": "review", "say": "" },
    { "kind": "when", "if": "!(claude.label ~ 'its')", "state": "idle", "say": "" },
    { "kind": "when", "if": "false", "state": "idle", "say": "" },
    { "kind": "on", "if": "pets.jill.state == 'failed'", "state": "waving", "beat": 2, "say": "you ok?" },
    { "kind": "when", "if": "pets.jill.state == 'running'", "state": "running", "say": "" },
    { "kind": "when", "if": "mem >= 90 && (cpu > 50)", "state": "failed", "say": "" },
    { "kind": "when", "if": "cpu >= 95", "state": "failed", "say": "cpu {cpu}%" },
    { "kind": "on", "if": "agents.active == 0", "state": "waving", "beat": 1.5, "say": "" }
  ]
}
```
(Compiled `when` rows carry no `beat` key; `on` rows carry a numeric `beat`. Compare after JSON round-trip so `undefined` drops.)

`tests/fixtures/rules/validate-basic.json`:

```json
{
  "ctx": { "looks": ["idle", "running", "waving", "failed", "review"], "signals": ["claude.session", "battery.pct", "cpu", "hour", "custom.window"], "pets": ["jill", "hanna"] },
  "rows": [
    { "kind": "range", "signal": "cpu", "min": 30, "max": 60, "look": "review" },
    { "kind": "range", "signal": "nope.pct", "max": 10, "look": "failed" },
    { "kind": "range", "signal": "cpu", "min": 60, "max": 30, "look": "review" },
    { "kind": "range", "signal": "hour", "min": 23, "max": 6, "look": "idle" },
    { "kind": "range", "signal": "cpu", "min": "lots", "look": "review" },
    { "kind": "range", "look": "review" },
    { "kind": "flag", "signal": "battery.pct", "is": true, "look": "jumping" },
    { "kind": "keyword", "signal": "custom.window", "words": "", "look": "idle" },
    { "kind": "pet", "pet": "bob", "look": "failed", "then": "waving" },
    { "kind": "pet", "look": "failed", "then": "waiting" },
    { "kind": "when", "if": "cpu >> 3", "state": "idle" },
    { "kind": "when", "if": "", "state": "idle" },
    { "kind": "when", "if": "pets.hanna.state == 'idle' && claude.weekly > 1", "state": "idle" },
    { "kind": "on", "if": "custom.window ~ 'x'", "state": "review", "beat": 1 },
    { "kind": "bogus" }
  ],
  "expect": [
    { "row": 1, "message": "unknown signal 'nope.pct'" },
    { "row": 2, "message": "min must be below max" },
    { "row": 4, "message": "min must be a number" },
    { "row": 5, "message": "needs a signal" },
    { "row": 6, "message": "look 'jumping' is not on this sheet (shows waving)" },
    { "row": 7, "message": "needs words" },
    { "row": 8, "message": "unknown pet 'bob'" },
    { "row": 9, "message": "needs a pet" },
    { "row": 9, "message": "look 'waiting' is not on this sheet (shows review)" },
    { "row": 10, "message": "bad expression: unexpected '3'" },
    { "row": 11, "message": "empty test" },
    { "row": 12, "message": "unknown signal 'claude.weekly'" },
    { "row": 14, "message": "unknown kind 'bogus'" }
  ]
}
```
(`hour` wrap on row 3 is allowed; `pets.hanna.state` is fine because `hanna` is a known pet; `custom.window` is in the signal list. The expected list is the complete output, in order.)

- [ ] **Step 2: Write the failing tests** (append to `tests/pet.test.js`; add `const fs = require("node:fs"); const path = require("node:path");` at the top)

```js
const RULES_DIR = path.join(__dirname, "fixtures/rules");
const readFx = (n) => JSON.parse(fs.readFileSync(path.join(RULES_DIR, n), "utf8"));

test("~ is a case-insensitive substring test; null never matches", () => {
  const s = { claude: { label: "Session (5-hour)" }, custom: { window: "YouTube — Firefox" }, gpu: null };
  assert.equal(P.evalExpr("claude.label ~ 'session'", s), true);
  assert.equal(P.evalExpr("custom.window ~ 'youtube' || custom.window ~ 'netflix'", s), true);
  assert.equal(P.evalExpr("!(custom.window ~ 'netflix')", s), true);
  assert.equal(P.evalExpr("gpu ~ 'x'", s), false); assert.equal(P.evalExpr("nope ~ 'x'", s), false);
  assert.equal(P.evalExpr("cpu ~ '1'", { cpu: 12 }), true);
});

test("compileRule matches the shared fixture, and presets equal the shared presets fixture", () => {
  const fx = readFx("compile-basic.json");
  const got = JSON.parse(JSON.stringify(P.compileRules(fx.rows)));
  assert.deepEqual(got, fx.expect);
  assert.deepEqual(JSON.parse(JSON.stringify(P.WATCH)), readFx("presets.json"));
  assert.deepEqual(P.presetRows("cpu"), P.WATCH.cpu); assert.notEqual(P.presetRows("cpu"), P.WATCH.cpu); assert.deepEqual(P.presetRows("nope"), []);
  assert.equal(P.rulesFor("battery")[0].if, "battery.full == true");
});

test("validateRules matches the shared fixture and skips dimensions that are null", () => {
  const fx = readFx("validate-basic.json");
  assert.deepEqual(P.validateRules(fx.rows, fx.ctx), fx.expect);
  assert.deepEqual(P.validateRules(fx.rows.slice(0, 2), { looks: null, signals: null, pets: null }), []);
  assert.deepEqual(P.validateRules("nope", fx.ctx), []);
});

test("step: an edge that rises during another beat is held, not lost", () => {
  const rules = [
    { kind: "on", if: "a", state: "waving", beat: 1 },
    { kind: "on", if: "b", state: "jumping", beat: 1, say: "b!" },
  ];
  let s = P.step(rules, { a: false, b: false }, null, 0);
  s = P.step(rules, { a: true, b: false }, s, 100);  assert.equal(s.state, "waving");
  s = P.step(rules, { a: true, b: true }, s, 200);   assert.equal(s.state, "waving");   // b rose while a beats
  s = P.step(rules, { a: true, b: true }, s, 1200);  assert.equal(s.state, "jumping"); assert.equal(s.say, "b!");  // held edge fires once a's beat ends
  s = P.step(rules, { a: true, b: true }, s, 2300);  assert.equal(s.state, "idle");     // no re-fire without a new edge
});
```

- [ ] **Step 3: Run to verify they fail**

Run: `node --test tests/pet.test.js 2>&1 | tail -8`
Expected: 4 new failures (`~` bad token; `compileRules` not a function; `validateRules` not a function; held-edge assertion).

- [ ] **Step 4: Implement in `widgets/Pet.js`**

Tokenizer regex: change `(>=|<=|==|!=|&&|\|\||[()!<>]|…` to `(>=|<=|==|!=|&&|\|\||~|[()!<>]|…`. In `cmp()` extend the operator test with `|| op === "~"` and, before the null check, add:

```js
      if (op === "~") return a === null || b === null ? false : String(a).toLowerCase().indexOf(String(b).toLowerCase()) !== -1
```

Replace the `WATCH` object with the structured rows from `presets.json` (copy verbatim — the test compares them). Then add, after `STATES`:

```js
var SIGNAL_KEYS = ["claude.session", "claude.weekly", "claude.resetInMin", "claude.label", "battery.pct", "battery.status", "battery.charging", "battery.discharging", "battery.full", "agents.active", "cpu", "mem", "gpu", "load", "temp", "hour"]
var ROW_KINDS = ["range", "flag", "keyword", "pet", "when", "on"]

function q(s) { return "'" + String(s).replace(/'/g, "") + "'" }
function petKey(name) { return String(name || "").trim().toLowerCase().replace(/[^a-z0-9_]+/g, "_") }
function hasNum(v) { return v !== undefined && v !== null && v !== "" && !isNaN(Number(v)) }
function isSet(v) { return v !== undefined && v !== null && v !== "" }

// A structured row → an engine rule. Raw when/on rows pass through.
function compileRule(row) {
  if (!row || typeof row !== "object") return null
  var kind = String(row.kind || "when"), test = null, state = row.look
  if (kind === "when" || kind === "on") return { kind: kind, if: String(row.if || ""), state: String(row.state || "idle"), beat: kind === "on" ? Number(row.beat) || 1.6 : undefined, say: String(row.say || "") }
  var sig = String(row.signal || "").trim()
  if (kind === "range") {
    var mn = Number(row.min), mx = Number(row.max), hasMin = hasNum(row.min), hasMax = hasNum(row.max)
    if (hasMin && hasMax) test = mn > mx ? "(" + sig + " >= " + mn + " || " + sig + " < " + mx + ")" : "(" + sig + " >= " + mn + " && " + sig + " < " + mx + ")"
    else if (hasMin) test = sig + " >= " + mn
    else if (hasMax) test = sig + " < " + mx
    else test = sig + " != null"
  } else if (kind === "flag") {
    test = sig + " == " + (row.is === false || String(row.is) === "false" ? "false" : "true")
  } else if (kind === "keyword") {
    var words = String(row.words || "").split(",").map(function(w) { return w.trim() }).filter(function(w) { return w !== "" })
    var match = String(row.match || "any")
    if (!words.length) test = "false"
    else {
      var parts = words.map(function(w) { return sig + " ~ " + q(w) })
      test = match === "all" ? "(" + parts.join(" && ") + ")" : match === "none" ? "!(" + parts.join(" || ") + ")" : "(" + parts.join(" || ") + ")"
    }
  } else if (kind === "pet") {
    test = "pets." + petKey(row.pet) + ".state == " + q(row.look)
    state = row.then
  } else return null
  if (isSet(row.and)) test = test + " && (" + String(row.and) + ")"
  var beat = hasNum(row.beat) && Number(row.beat) > 0 ? Number(row.beat) : undefined
  return { kind: beat ? "on" : "when", if: test, state: String(state || "idle"), beat: beat, say: String(row.say || "") }
}
function compileRules(rows) {
  var out = []
  for (var i = 0; i < (rows || []).length; i++) { var r = compileRule(rows[i]); if (r) out.push(r) }
  return out
}
function presetRows(watch) { return JSON.parse(JSON.stringify(WATCH[String(watch)] || [])) }

// Identifiers an expression reads (dotted paths), for the validator. Parses
// the expression first (against empty signals) so syntax errors surface with
// the evaluator's own messages ("unexpected '3'", "missing )", "unexpected end").
function identifiers(src) {
  evalExpr(String(src || ""), {})
  var out = [], toks = tokenize(String(src || ""))
  for (var i = 0; i < toks.length; i++) { var t = toks[i]; if (/^[A-Za-z_]/.test(t) && t !== "true" && t !== "false" && t !== "null") out.push(t) }
  return out
}
function knownSignal(path, ctx) {
  if (!ctx || !ctx.signals) return true
  if (ctx.signals.indexOf(path) !== -1) return true
  var m = /^pets\.([a-z0-9_]+)\.(state|say|watch)$/.exec(path)
  if (m) return !ctx.pets || ctx.pets.indexOf(m[1]) !== -1
  return false
}
// ctx = { looks: string[]|null, signals: string[]|null, pets: string[]|null }; null skips that check.
function validateRules(rows, ctx) {
  var out = []
  if (!Array.isArray(rows)) return out
  ctx = ctx || {}
  function push(i, m) { out.push({ row: i, message: m }) }
  function checkLook(i, name) {
    if (!ctx.looks || !ctx.looks.length || !isSet(name)) return
    if (ctx.looks.indexOf(String(name)) === -1) push(i, "look '" + name + "' is not on this sheet (shows " + resolveLook(name, ctx.looks) + ")")
  }
  function checkSignal(i, sig) { if (!knownSignal(sig, ctx)) push(i, "unknown signal '" + sig + "'") }
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    if (!r || typeof r !== "object") { push(i, "not a row"); continue }
    var kind = String(r.kind || "when")
    if (ROW_KINDS.indexOf(kind) === -1) { push(i, "unknown kind '" + kind + "'"); continue }
    if (kind === "when" || kind === "on") {
      var src = String(r.if || "").trim()
      if (!src) push(i, "empty test")
      else {
        try { var ids = identifiers(src); for (var k = 0; k < ids.length; k++) checkSignal(i, ids[k]) }
        catch (e) { push(i, "bad expression: " + e.message) }
      }
      checkLook(i, r.state)
      continue
    }
    if (kind === "pet") {
      if (!isSet(r.pet)) push(i, "needs a pet")
      else if (ctx.pets && ctx.pets.indexOf(petKey(r.pet)) === -1) push(i, "unknown pet '" + r.pet + "'")
      checkLook(i, r.then)
    } else {
      var sig = String(r.signal || "").trim()
      if (!sig) push(i, "needs a signal")
      else checkSignal(i, sig)
      if (kind === "range") {
        if (isSet(r.min) && !hasNum(r.min)) push(i, "min must be a number")
        if (isSet(r.max) && !hasNum(r.max)) push(i, "max must be a number")
        if (hasNum(r.min) && hasNum(r.max) && Number(r.min) >= Number(r.max) && sig !== "hour") push(i, "min must be below max")
      }
      if (kind === "keyword" && !String(r.words || "").split(",").some(function(w) { return w.trim() !== "" })) push(i, "needs words")
      checkLook(i, r.look)
    }
    if (isSet(r.and)) { try { var ids2 = identifiers(r.and); for (var j = 0; j < ids2.length; j++) checkSignal(i, ids2[j]) } catch (e2) { push(i, "bad expression: " + e2.message) } }
  }
  return out
}
```

Change `rulesFor` to compile in both cases:

```js
function rulesFor(watch, custom) {
  if (String(watch) === "custom") return Array.isArray(custom) ? compileRules(custom) : []
  return compileRules(WATCH[String(watch)] || [])
}
```

Lost-beat fix in `step` — replace the `on` branch:

```js
    if (String(r.kind) === "on") {
      var was = prev && prev.edges ? prev.edges[i] : undefined
      var rising = v && was === false
      if (rising && !beatUntil) { beatUntil = now + Math.max(0.2, Number(r.beat) || 1.6) * 1000; beatState = String(r.state || "waving"); beatSay = fill(r.say, signals); edges[i] = true }
      else edges[i] = rising ? false : v        // a beat is running: hold this edge so it fires when the beat ends
    }
```

Note the fixture expects `hasNum("lots")` false → "min must be a number"; `rowFor`'s `resolveLook` from Task 1 is reused. Add to the exports: `SIGNAL_KEYS, ROW_KINDS, compileRule, compileRules, presetRows, validateRules, petKey`.

- [ ] **Step 5: Run the whole JS suite**

Run: `node --test tests/*.test.js 2>&1 | tail -8`
Expected: all pass, including the pre-existing preset behaviour tests (they exercise the compiled presets).

- [ ] **Step 6: Commit**

```bash
git add widgets/Pet.js tests/pet.test.js tests/fixtures/rules
git commit -m "Pet rules: structured rows (range/flag/keyword/pet) compiled onto the engine, ~ operator, presets as rows, validateRules, held edges"
```

---

### Task 4: Python twin — compiler, validator, presets; `pet expand|check`; registry rules field

**Files:**
- Modify: `bin/desktop-widgets` (new section `# ---- pet rules` before the pets section; `pet` sub-command; parser)
- Modify: `widgets/registry.json` (`pet.rules` options/description/`rowFields`)
- Create: `tests/fixtures/validate/pet-structured-rules.json`, `tests/fixtures/validate/pet-bad-rule-kind.json`
- Test: `tests/test_cli.py`

**Interfaces:**
- Consumes: fixtures from Task 3.
- Produces (Python): `PET_WATCH` (dict, equals `presets.json`), `PET_LOOKS`, `PET_FALLBACK`, `SIGNAL_KEYS`, `tokenize_expr(src)`, `compile_rule(row)`, `compile_rules(rows)`, `resolve_look(name, present)`, `validate_rules(rows, ctx)`; commands `desktop-widgets pet expand <index> [--force]` (copies the preset rows into `rules`, sets `watch: custom`; error if already custom) and `desktop-widgets pet check [index] [--json]` (prints `row N: message` lines; exit 0 always, `--json` → `{"widgets": {index: [...]}}`).
- Registry: `rules.options` = `["range","flag","keyword","pet","when","on"]`; `rules.rowFields` = per-key control hints (below); `rules.description` rewritten.

- [ ] **Step 1: Write the failing tests** (append to `tests/test_cli.py`, inside class `Cli` unless noted)

```python
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
```

and in `Cli`:

```python
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
```

Fixtures — `tests/fixtures/validate/pet-structured-rules.json`:

```json
{ "config": { "widgets": [ { "type": "pet", "sheet": "/x/spritesheet.webp", "watch": "custom", "rules": [
    { "kind": "range", "signal": "battery.pct", "max": 20, "look": "waiting" },
    { "kind": "flag", "signal": "battery.charging", "is": true, "look": "running" },
    { "kind": "keyword", "signal": "custom.window", "words": "youtube", "look": "review" },
    { "kind": "pet", "pet": "jill", "look": "failed", "then": "waving", "beat": 2 } ],
    "signals": [ { "kind": "command", "key": "window", "command": "hyprctl activewindow -j | jq -r .title" } ] } ] },
  "expect": { "widgets": 1, "errors": 0, "warnings": 0 } }
```

`tests/fixtures/validate/pet-bad-rule-kind.json`:

```json
{ "config": { "widgets": [ { "type": "pet", "sheet": "/x/spritesheet.webp", "watch": "custom", "rules": [ { "kind": "bracket", "signal": "cpu" } ] } ] },
  "expect": { "widgets": 1, "errors": 1, "warnings": 0, "messages": [ "widget 0: rules.0 has unknown kind 'bracket'" ] } }
```
(The `signals` rows field is part of this task's registry edit in Step 3, so the fixture's 0 warnings hold from the start; the sampler that reads it arrives in Task 5.)

- [ ] **Step 2: Run to verify they fail**

Run: `python3 -m unittest tests.test_cli -v 2>&1 | tail -12`
Expected: `PetRules` tests error (`no attribute 'PET_WATCH'`), `test_pet_expand_and_check` fails (argparse: invalid choice `pet`), both fixture tests fail on the rules `kind` check.

- [ ] **Step 3: Registry** — in `widgets/registry.json` `pet.fields`, replace the `rules` entry with:

```json
        {
          "key": "rules",
          "type": "rows",
          "label": "Rules (custom)",
          "options": ["range", "flag", "keyword", "pet", "when", "on"],
          "default": [],
          "showWhen": { "watch": "custom" },
          "rowFields": {
            "signal": { "enum": "signals" }, "look": { "enum": "looks" }, "then": { "enum": "looks" }, "state": { "enum": "looks" },
            "pet": { "enum": "pets" }, "is": { "type": "boolean" }, "match": { "options": ["any", "all", "none"] },
            "min": { "type": "number" }, "max": { "type": "number" }, "beat": { "type": "number" }
          },
          "description": "top-down, first steady match wins; a row with `beat` plays once for that many seconds when it turns true. range = brackets on a number (min ≤ value < max; min > max wraps for hour); flag = true/false; keyword = comma-separated words in a text signal (match any/all/none); pet = when another pet shows a look; when/on = a raw test (signals: claude.session, claude.weekly, claude.resetInMin, claude.label, battery.pct/status/charging/discharging/full, agents.active, cpu, mem, gpu, load, temp, hour, custom.<key>, pets.<name>.state/say). `and` adds a raw extra condition to any row."
        },
        {
          "key": "signals",
          "type": "rows",
          "label": "Extra signals",
          "options": ["command"],
          "default": [],
          "description": "commands sampled with the pet's signals; each becomes custom.<key> (numbers parsed, text kept). e.g. key window, command `hyprctl activewindow -j | jq -r .title`"
        },
```

- [ ] **Step 4: Python implementation** — add before `# ---- pets (sprite sheets on this machine)` in `bin/desktop-widgets`:

```python
# ---------------------------------------------------------------- pet rules (twin of widgets/Pet.js; tests/fixtures/rules keep them equal)
PET_LOOKS = ["idle", "running", "waving", "jumping", "failed", "waiting", "review"]
PET_FALLBACK = {"jumping": ["waving", "idle"], "waiting": ["review", "idle"], "failed": ["waiting", "idle"], "running": ["idle"], "review": ["idle"], "waving": ["idle"], "idle": []}
SIGNAL_KEYS = ["claude.session", "claude.weekly", "claude.resetInMin", "claude.label", "battery.pct", "battery.status", "battery.charging", "battery.discharging", "battery.full", "agents.active", "cpu", "mem", "gpu", "load", "temp", "hour"]
ROW_KINDS = ["range", "flag", "keyword", "pet", "when", "on"]
PET_WATCH = {
    "claude": [
        {"kind": "range", "signal": "claude.resetInMin", "min": 200, "look": "jumping", "beat": 2.2, "say": "fresh session!"},
        {"kind": "range", "signal": "claude.session", "min": 95, "look": "failed", "say": "session cap {claude.session}%"},
        {"kind": "range", "signal": "claude.session", "min": 80, "look": "waiting", "say": "{claude.session}% used"},
        {"kind": "range", "signal": "agents.active", "min": 1, "look": "running", "say": ""},
        {"kind": "range", "signal": "claude.session", "min": 50, "look": "review", "say": "{claude.session}%"}],
    "battery": [
        {"kind": "flag", "signal": "battery.full", "is": True, "look": "waving", "beat": 2.2, "say": "full!"},
        {"kind": "range", "signal": "battery.pct", "max": 10, "and": "battery.discharging", "look": "failed", "say": "{battery.pct}%!"},
        {"kind": "range", "signal": "battery.pct", "max": 20, "and": "battery.discharging", "look": "waiting", "say": "{battery.pct}%"},
        {"kind": "flag", "signal": "battery.charging", "is": True, "look": "running", "say": ""}],
    "agents": [
        {"kind": "range", "signal": "agents.active", "max": 1, "look": "waving", "beat": 2.2, "say": "all done"},
        {"kind": "range", "signal": "agents.active", "min": 1, "look": "running", "say": "{agents.active} working"}],
    "cpu": [
        {"kind": "range", "signal": "cpu", "min": 95, "look": "failed", "say": "cpu {cpu}%"},
        {"kind": "range", "signal": "cpu", "min": 60, "look": "running", "say": "cpu {cpu}%"},
        {"kind": "range", "signal": "cpu", "min": 30, "look": "review", "say": ""}],
    "mem": [
        {"kind": "range", "signal": "mem", "min": 95, "look": "failed", "say": "mem {mem}%"},
        {"kind": "range", "signal": "mem", "min": 80, "look": "waiting", "say": "mem {mem}%"},
        {"kind": "range", "signal": "mem", "min": 50, "look": "review", "say": ""}],
    "gpu": [
        {"kind": "range", "signal": "gpu", "min": 95, "look": "failed", "say": "gpu {gpu}%"},
        {"kind": "range", "signal": "gpu", "min": 60, "look": "running", "say": "gpu {gpu}%"},
        {"kind": "range", "signal": "gpu", "min": 30, "look": "review", "say": ""},
        {"kind": "when", "if": "gpu == null", "state": "idle", "say": "no gpu here"}],
}
_TOKEN = re.compile(r"\s*(>=|<=|==|!=|&&|\|\||~|[()!<>]|-?\d+(?:\.\d+)?|'[^']*'|\"[^\"]*\"|[A-Za-z_][\w.]*)")


def tokenize_expr(src):
    out, pos, n = [], 0, len(src)
    while pos < n:
        m = _TOKEN.match(src, pos)
        if not m or m.end() == pos:
            if src[pos:].strip() == "": break
            raise ValueError(f"bad token near '{src[pos:pos + 8]}'")
        out.append(m.group(1)); pos = m.end()
    return out


def check_expr(src):
    """Parse like Pet.js evalExpr (same error messages) and return the identifiers it reads."""
    t = tokenize_expr(str(src or "")); i = [0]
    def peek(): return t[i[0]] if i[0] < len(t) else None
    def nxt():
        v = peek(); i[0] += 1; return v
    def atom():
        k = nxt()
        if k is None: raise ValueError("unexpected end")
        if k == "(":
            or_expr()
            if nxt() != ")": raise ValueError("missing )")
        elif k == "!": atom()
    def cmp():
        atom()
        if peek() in (">=", "<=", ">", "<", "==", "!=", "~"): nxt(); atom()
    def and_expr():
        cmp()
        while peek() == "&&": nxt(); cmp()
    def or_expr():
        and_expr()
        while peek() == "||": nxt(); and_expr()
    or_expr()
    if i[0] != len(t): raise ValueError(f"unexpected '{t[i[0]]}'")
    return [x for x in t if re.match(r"[A-Za-z_]", x) and x not in ("true", "false", "null")]
```

(`_num` already exists above `_check_field` — reuse it, and pass it a `float` so string inputs like `"30.0"` work. JS prints `Number(v)` with `String()`, so `95` → `95` and `2.2` → `2.2`; `_num(float(v))` matches.)

```python
def _has_num(v):
    if v is None or v == "" or isinstance(v, bool): return False
    try: float(v); return True
    except (TypeError, ValueError): return False


def _is_set(v): return v is not None and v != ""


def _q(s): return "'" + str(s).replace("'", "") + "'"


def pet_key(name): return re.sub(r"[^a-z0-9_]+", "_", str(name or "").strip().lower())


def resolve_look(state, present):
    for name in [str(state)] + PET_FALLBACK.get(str(state), ["idle"]):
        if not present or name in present: return name
    return "idle"


def compile_rule(row):
    if not isinstance(row, dict): return None
    kind = str(row.get("kind") or "when"); state = row.get("look")
    if kind in ("when", "on"):
        out = {"kind": kind, "if": str(row.get("if") or ""), "state": str(row.get("state") or "idle")}
        if kind == "on": out["beat"] = float(row["beat"]) if _has_num(row.get("beat")) and float(row["beat"]) else 1.6
        out["say"] = str(row.get("say") or ""); return _tidy(out)
    sig = str(row.get("signal") or "").strip()
    if kind == "range":
        has_min, has_max = _has_num(row.get("min")), _has_num(row.get("max"))
        mn = _num(float(row["min"])) if has_min else None; mx = _num(float(row["max"])) if has_max else None
        if has_min and has_max:
            test = f"({sig} >= {mn} || {sig} < {mx})" if float(row["min"]) > float(row["max"]) else f"({sig} >= {mn} && {sig} < {mx})"
        elif has_min: test = f"{sig} >= {mn}"
        elif has_max: test = f"{sig} < {mx}"
        else: test = f"{sig} != null"
    elif kind == "flag":
        test = f"{sig} == " + ("false" if row.get("is") is False or str(row.get("is")) == "false" else "true")
    elif kind == "keyword":
        words = [w.strip() for w in str(row.get("words") or "").split(",") if w.strip()]
        match = str(row.get("match") or "any")
        if not words: test = "false"
        else:
            parts = [f"{sig} ~ {_q(w)}" for w in words]
            test = "(" + " && ".join(parts) + ")" if match == "all" else ("!(" + " || ".join(parts) + ")" if match == "none" else "(" + " || ".join(parts) + ")")
    elif kind == "pet":
        test = f"pets.{pet_key(row.get('pet'))}.state == {_q(row.get('look'))}"; state = row.get("then")
    else: return None
    if _is_set(row.get("and")): test = f"{test} && ({row['and']})"
    beat = float(row["beat"]) if _has_num(row.get("beat")) and float(row["beat"]) > 0 else None
    out = {"kind": "on" if beat else "when", "if": test, "state": str(state or "idle")}
    if beat: out["beat"] = beat
    out["say"] = str(row.get("say") or "")
    return _tidy(out)


def _tidy(rule):
    """Match the JS shape after JSON round-trip: integral beats print as ints."""
    if "beat" in rule and float(rule["beat"]).is_integer(): rule["beat"] = int(rule["beat"])
    return rule


def compile_rules(rows):
    return [r for r in (compile_rule(x) for x in (rows or [])) if r]


def _identifiers(src): return check_expr(src)


def _known_signal(path, ctx):
    sigs = (ctx or {}).get("signals")
    if sigs is None: return True
    if path in sigs: return True
    m = re.match(r"^pets\.([a-z0-9_]+)\.(state|say|watch)$", path)
    if m: return ctx.get("pets") is None or m.group(1) in ctx["pets"]
    return False


def validate_rules(rows, ctx):
    """[{row, message}] — same messages as Pet.validateRules; ctx keys looks/signals/pets, None skips."""
    out = []
    if not isinstance(rows, list): return out
    ctx = ctx or {}; looks = ctx.get("looks")
    push = lambda i, m: out.append({"row": i, "message": m})
    def check_look(i, name):
        if not looks or not _is_set(name): return
        if str(name) not in looks: push(i, f"look '{name}' is not on this sheet (shows {resolve_look(name, looks)})")
    def check_signal(i, sig):
        if not _known_signal(sig, ctx): push(i, f"unknown signal '{sig}'")
    def check_expr(i, src):
        try:
            for ident in _identifiers(src): check_signal(i, ident)
        except ValueError as e: push(i, f"bad expression: {e}")
    for i, r in enumerate(rows):
        if not isinstance(r, dict): push(i, "not a row"); continue
        kind = str(r.get("kind") or "when")
        if kind not in ROW_KINDS: push(i, f"unknown kind '{kind}'"); continue
        if kind in ("when", "on"):
            src = str(r.get("if") or "").strip()
            if not src: push(i, "empty test")
            else: check_expr(i, src)
            check_look(i, r.get("state")); continue
        if kind == "pet":
            if not _is_set(r.get("pet")): push(i, "needs a pet")
            elif ctx.get("pets") is not None and pet_key(r.get("pet")) not in ctx["pets"]: push(i, f"unknown pet '{r.get('pet')}'")
            check_look(i, r.get("then"))
        else:
            sig = str(r.get("signal") or "").strip()
            if not sig: push(i, "needs a signal")
            else: check_signal(i, sig)
            if kind == "range":
                if _is_set(r.get("min")) and not _has_num(r.get("min")): push(i, "min must be a number")
                if _is_set(r.get("max")) and not _has_num(r.get("max")): push(i, "max must be a number")
                if _has_num(r.get("min")) and _has_num(r.get("max")) and float(r["min"]) >= float(r["max"]) and sig != "hour": push(i, "min must be below max")
            if kind == "keyword" and not any(w.strip() for w in str(r.get("words") or "").split(",")): push(i, "needs words")
            check_look(i, r.get("look"))
        if _is_set(r.get("and")): check_expr(i, r["and"])
    return out


def rule_ctx_for(widgets, index, looks=None):
    """Validation context for widget `index`: signal catalogue (+ its custom keys) and the other pets' names."""
    entry = widgets[index]
    sigs = list(SIGNAL_KEYS) + [f"custom.{s.get('key')}" for s in entry.get("signals") or [] if isinstance(s, dict) and s.get("key")]
    pets = [pet_name_of(w) for j, w in enumerate(widgets) if isinstance(w, dict) and w.get("type") == "pet" and j != index]
    return {"looks": looks, "signals": sigs, "pets": pets}


def pet_name_of(entry):
    n = str(entry.get("name") or "").strip()
    if n: return pet_key(n)
    parts = [p for p in str(entry.get("sheet") or "").rstrip("/").split("/")]
    return pet_key(parts[-2] if len(parts) >= 2 else (parts[-1] if parts and parts[-1] else "pet"))


def cmd_pet(args, ctx):
    if args.op == "expand":
        if args.index is None: print("pet expand needs a widget index", file=sys.stderr); return 2
        def fn(doc, widgets):
            e = index_arg(widgets, args.index)
            if e.get("type") != "pet": raise ValueError(f"widget {args.index} is not a pet")
            watch = str(e.get("watch") or "claude")
            if watch == "custom": raise ValueError(f"widget {args.index} is already custom (edit its rules)")
            e["rules"] = json.loads(json.dumps(PET_WATCH.get(watch, []))); e["watch"] = "custom"
        return mutate(args, ctx, fn)
    if args.op == "check":
        try: parsed, _ = read_config(ctx["path"])
        except ValueError as e: print(f"ERROR   {e}", file=sys.stderr); return 1
        widgets = parsed.get("widgets", []) if isinstance(parsed, dict) else (parsed or [])
        report = {}
        for i, w in enumerate(widgets):
            if not isinstance(w, dict) or w.get("type") != "pet": continue
            if args.index is not None and i != args.index: continue
            looks = None
            info = sheet_looks(os.path.expanduser(str(w.get("sheet") or ""))) if w.get("sheet") else None
            if info and info.get("measured"): looks = [l["name"] for l in info["looks"] if l["present"]]
            report[str(i)] = validate_rules(w.get("rules") or [], rule_ctx_for(widgets, i, looks)) if str(w.get("watch") or "claude") == "custom" else []
        if args.json: print(json.dumps({"widgets": report})); return 0
        for i, msgs in report.items():
            for m in msgs: print(f"widget {i} row {m['row']}: {m['message']}" if args.index is None else f"row {m['row']}: {m['message']}")
        if not any(report.values()): print("rules ok")
        return 0
    return 2
```

`sheet_looks` arrives in Task 6 (`pets --looks`); until then define a stub at the top of the pets section: `def sheet_looks(path): return None` (Task 6 replaces it). Parser, next to `pets`:

```python
    pe = sub.add_parser("pet", help="pet helpers: expand <index> (preset rules → editable custom rows) | check [index] (validate rules) | fetch <petdex url or slug>")
    pe.add_argument("op", choices=["expand", "check", "fetch"]); pe.add_argument("index", nargs="?", type=int); pe.add_argument("--json", action="store_true"); pe.add_argument("--force", action="store_true")
    pe.set_defaults(fn=cmd_pet)
```
(`fetch` gains its own arguments in Task 7; argparse's `index` positional doubles as the URL there — Task 7 changes `index` to a string `target` and converts.)

Because `mutate()` maps `ValueError` containing "must be" to exit 1 and everything else to 2, "already custom" exits 2 as the test expects.

- [ ] **Step 5: Run both suites**

Run: `python3 -m unittest discover -s tests -v 2>&1 | tail -3 && node --test tests/*.test.js 2>&1 | tail -3`
Expected: both green (JS fixture tests pick up the two new validate fixtures too).

- [ ] **Step 6: Commit**

```bash
git add bin/desktop-widgets widgets/registry.json tests/test_cli.py tests/fixtures/validate/pet-structured-rules.json tests/fixtures/validate/pet-bad-rule-kind.json
git commit -m "CLI: pet rule compiler/validator twin (shared fixtures), pet expand/check, registry rules row kinds + rowFields, signals rows field"
```

---

### Task 5: Custom command signals and one sampler for all pets

**Files:**
- Modify: `bin/dw-signals` (`--command key=<shell>`)
- Modify: `Service.qml` (sampler), `widgets/PetWidget.qml` (consume service signals)
- Test: `tests/test_signals.py`

**Interfaces:**
- Produces (Python): `custom_signals(specs, timeout=2.0) → dict` where `specs` = list of `"key=shell command"` strings; numeric-looking stdout → `float` (int when integral), else stripped text, failure/timeout → `None`; output merged as `out["custom"][key]`.
- Produces (QML): `Service.signals` (object or null), `Service.signalCommands` (string[] of `key=cmd`), `Service.signalsInterval` (ms); pets read `service.signals` via `Connections`.

- [ ] **Step 1: Write the failing test** (append to `tests/test_signals.py` class)

```python
    def test_custom_signals(self):
        got = G.custom_signals(["n=echo 12", "f=echo 3.5", "t=printf 'YouTube — Firefox'", "bad=exit 3", "slow=sleep 3", "noeq", "empty=true"], timeout=0.5)
        self.assertEqual(got["n"], 12); self.assertIsInstance(got["n"], int)
        self.assertEqual(got["f"], 3.5); self.assertEqual(got["t"], "YouTube — Firefox")
        self.assertIsNone(got["bad"]); self.assertIsNone(got["slow"]); self.assertNotIn("noeq", got); self.assertEqual(got["empty"], "")
        out = json.loads(subprocess.run([sys.executable, str(ROOT / "bin" / "dw-signals"), "--command", "x=echo 7"], capture_output=True, text=True, timeout=10).stdout)
        self.assertEqual(out["custom"]["x"], 7)
```

- [ ] **Step 2: Run to verify it fails** — `python3 -m unittest tests.test_signals -v 2>&1 | tail -4` → `AttributeError: custom_signals`.

- [ ] **Step 3: Implement in `bin/dw-signals`** — add after `count_agents`:

```python
def custom_signals(specs, timeout=2.0):
    """['key=shell command', ...] -> {key: number|text|None}; each command runs in a shell with a timeout."""
    out = {}
    for spec in specs:
        if "=" not in spec: continue
        key, cmd = spec.split("=", 1)
        key = key.strip()
        if not key: continue
        try:
            r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
            if r.returncode != 0: out[key] = None; continue
            text = r.stdout.strip()
        except Exception:
            out[key] = None; continue
        try:
            v = float(text); out[key] = int(v) if v.is_integer() else v
        except ValueError:
            out[key] = text
    return out
```

In `main`, collect `--command` values: replace the `agent = …` line with

```python
    agent, commands, i = "claude", [], 0
    while i < len(argv):
        if argv[i] == "--agent" and i + 1 < len(argv): agent = argv[i + 1]; i += 2
        elif argv[i] == "--command" and i + 1 < len(argv): commands.append(argv[i + 1]); i += 2
        else: i += 1
```
and before `print(json.dumps(out))`: `if commands: out["custom"] = custom_signals(commands)`. Update the module docstring's Options line.

- [ ] **Step 4: Run** — `python3 -m unittest tests.test_signals -v 2>&1 | tail -4` → pass (the `slow` case costs 0.5 s).

- [ ] **Step 5: Service sampler** — in `Service.qml`, next to `petStates`:

```qml
  // One signals sampler for every pet (was one dw-signals process per pet per tick).
  // Commands from every pet's `signals` rows are merged; each pet reads custom.<key>.
  property var signals: null
  readonly property var signalCommands: {
    var seen = {}, out = []
    for (var i = 0; i < widgets.length; i++) {
      var w = widgets[i]
      if (!w || w.type !== "pet" || w.enabled === false) continue
      var rows = w.signals && typeof w.signals.length === "number" ? w.signals : []
      for (var r = 0; r < rows.length; r++) { var s = rows[r]; if (s && s.key && s.command && !seen[s.key]) { seen[s.key] = true; out.push(String(s.key) + "=" + String(s.command)) } }
    }
    return out
  }
  readonly property int signalsInterval: {
    var best = 0
    for (var i = 0; i < widgets.length; i++) { var w = widgets[i]; if (w && w.type === "pet" && w.enabled !== false) { var s = Math.max(2, parseInt(w.intervalSec) || 5); if (!best || s < best) best = s } }
    return (best || 5) * 1000
  }
  readonly property bool hasPets: signalsInterval > 0 && widgets.some(function(w) { return w && w.type === "pet" && w.enabled !== false })
  Process {
    id: sampler
    command: [String(Qt.resolvedUrl("bin/dw-signals")).replace(/^file:\/\//, "")].concat(root.signalCommands.reduce(function(a, c) { return a.concat(["--command", c]) }, []))
    stdout: StdioCollector { onStreamFinished: { try { root.signals = JSON.parse(text) } catch (e) { root.log("signals: bad json") } } }
  }
  Timer { interval: root.signalsInterval; running: root.hasPets; repeat: true; triggeredOnStart: true; onTriggered: if (!sampler.running) sampler.running = true }
```
(`widgets` is the validated, defaults-applied list at `Service.qml:169`; check its element shape — entries carry `type`, `enabled`, `signals`, `intervalSec` after `applyDefaults`.)

- [ ] **Step 6: PetWidget consumes it** — replace the widget's own `Process { id: signals … }` + its `Timer` with:

```qml
  // Signals come from the service's shared sampler; a pet without a service (tests, drop-in hosts) samples on its own.
  Connections { target: root.service; function onSignalsChanged() { if (root.service.signals) root.applySignals(root.service.signals) } }
  Process {
    id: ownSampler
    command: [String(Qt.resolvedUrl("../bin/dw-signals")).replace(/^file:\/\//, "")]
    stdout: StdioCollector { onStreamFinished: root.apply(text) }
  }
  Timer { interval: root.intervalSec * 1000; running: root.sheetPath !== "" && !root.service; repeat: true; triggeredOnStart: true; onTriggered: if (!ownSampler.running) ownSampler.running = true }
```
and split `apply(text)` into `apply(text)` (parse then call) and `applySignals(s)` (the existing body from `s.pets = …` on). Also add `Component.onCompleted: { publish(); if (service && service.signals) applySignals(service.signals) }` (replacing the existing `Component.onCompleted: publish()`).

- [ ] **Step 7: Live check**

```bash
python3 -c 'import json;json.load(open("manifest.json"))' && omarchy restart shell; sleep 6
ps -eo pid,etimes,args | grep -c '[d]w-signals'        # ≤1 at any instant (one sampler), not one per pet
journalctl --user _COMM=quickshell --since "-20s" | grep -i 'desktop-widgets' | tail -5
desktop-widgets set <pet index> signals='[{"kind":"command","key":"window","command":"hyprctl activewindow -j | jq -r .title"}]' --force 2>/dev/null || desktop-widgets edit  # rows via `set` need JSON; if `set` refuses, add the row through the editor IPC instead:
omarchy-shell shell call homelab.desktop-widgets call '{"op":"set","key":"signals","value":[{"kind":"command","key":"window","command":"hyprctl activewindow -j | jq -r .title"}]}'
```
Then watch the pets keep animating and the journal stay clean. Remove the test row afterwards.

- [ ] **Step 8: Commit**

```bash
git add bin/dw-signals tests/test_signals.py Service.qml widgets/PetWidget.qml
git commit -m "Signals: one shared sampler in the service for every pet; dw-signals --command key=<shell> → custom.<key>"
```

---

### Task 6: `pets --looks` and sheet probing in the CLI

**Files:**
- Modify: `bin/desktop-widgets` (pets section: `image_geometry`, `sheet_looks`, `pets --looks`; `list_pets` gains `license`/`source`)
- Test: `tests/test_cli.py`

**Interfaces:**
- Produces: `image_geometry(head: bytes) → (fmt, w, h) | None` for PNG (IHDR), WebP `VP8 ` (frame header), `VP8L` (bitstream header), `VP8X` (canvas fields) — pure Python; `sheet_looks(path) → { "rows": k, "looks": [{name,row,frames,present}], "measured": bool } | None`; pixel probe via Pillow if importable, else `magick <path> -crop 192x208 +repage -format '%[fx:maxima.a]\n' info:` (timeout 20 s), else geometry only (`measured: False`, all present, frames 6); `desktop-widgets pets --looks [slug]` prints `slug  looks: idle ×6, running ×6, … (7 of 9)` or `(geometry only — install Pillow or ImageMagick to measure)`.

- [ ] **Step 1: Write the failing tests** (in `tests/test_cli.py`, new class)

```python
import struct, zlib

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
```
and in `Cli`:

```python
    def test_pets_looks_listing(self):
        pets = self.home / ".config" / "omarchy" / "desktop-widgets.pets" / "boba"; pets.mkdir(parents=True)
        (pets / "spritesheet.png").write_bytes(_png(1536, 1872, blank_cells={(4, c) for c in range(8)}))
        (pets / "pet.json").write_text(json.dumps({"id": "boba", "displayName": "Boba", "source": {"site": "petdex", "license": "CC0"}}))
        code, out, _ = self.run_cli("pets", "--looks", "boba")
        self.assertEqual(code, 0); self.assertIn("boba", out); self.assertIn("looks:", out); self.assertIn("idle", out)
        code, out, _ = self.run_cli("pets", "--json")
        p = [x for x in json.loads(out)["pets"] if x["slug"] == "boba"][0]
        self.assertEqual(p["license"], "CC0"); self.assertEqual(p["source"], "petdex")
```

- [ ] **Step 2: Run to verify failure** — `python3 -m unittest tests.test_cli.SheetProbe tests.test_cli.Cli.test_pets_looks_listing 2>&1 | tail -4` → attribute errors.

- [ ] **Step 3: Implement** — in the pets section of `bin/desktop-widgets` (replace the Task 4 stub):

```python
FRAME_W, FRAME_H, COLS = 192, 208, 8
CODEX_ROWS = ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review"]
LEGACY_ROWS = ["idle", "waving", "running", "failed", "review", "jumping", "extra1", "extra2"]


def image_geometry(head):
    """(fmt, w, h) from the first bytes of a PNG or WebP file, or None."""
    import struct
    try:
        if head[:8] == b"\x89PNG\r\n\x1a\n" and head[12:16] == b"IHDR":
            w, h = struct.unpack(">II", head[16:24]); return ("png", w, h)
        if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
            tag = head[12:16]
            if tag == b"VP8X":
                w = int.from_bytes(head[24:27], "little") + 1; h = int.from_bytes(head[27:30], "little") + 1; return ("webp", w, h)
            if tag == b"VP8L":
                if head[20] != 0x2f: return None
                b = int.from_bytes(head[21:25], "little"); return ("webp", (b & 0x3fff) + 1, ((b >> 14) & 0x3fff) + 1)
            if tag == b"VP8 ":
                if head[23:26] != b"\x9d\x01\x2a": return None
                w, h = struct.unpack("<HH", head[26:30]); return ("webp", w & 0x3fff, h & 0x3fff)
    except (struct.error, IndexError): return None
    return None


def row_names(rows):
    if rows == 8: return LEGACY_ROWS
    return CODEX_ROWS + [f"extra{r}" for r in range(10, rows + 1)]


def _cell_alpha(path, rows):
    """Max alpha per cell (row-major), via Pillow or ImageMagick; None when neither is available."""
    try:
        from PIL import Image
        im = Image.open(path).convert("RGBA"); out = []
        for r in range(rows):
            for c in range(COLS):
                cell = im.crop((c * FRAME_W, r * FRAME_H, (c + 1) * FRAME_W, (r + 1) * FRAME_H))
                out.append(cell.getchannel("A").getextrema()[1])
        return out
    except ImportError: pass
    except Exception: return None
    if shutil.which("magick"):
        try:
            r = subprocess.run(["magick", path, "-crop", f"{FRAME_W}x{FRAME_H}", "+repage", "-format", "%[fx:maxima.a]\n", "info:"], capture_output=True, text=True, timeout=20)
            vals = [float(x) for x in r.stdout.split()]
            if r.returncode == 0 and len(vals) >= rows * COLS: return [round(v * 255) for v in vals[:rows * COLS]]
        except Exception: return None
    return None


def sheet_looks(path):
    """Rows and user-facing looks of a sheet; measured=False means presence/frames are assumed (no pixel tool)."""
    try:
        with open(path, "rb") as fh: head = fh.read(64)
    except OSError: return None
    g = image_geometry(head)
    if not g or g[1] != FRAME_W * COLS or g[2] % FRAME_H or not 8 <= g[2] // FRAME_H <= 11: return None
    rows = g[2] // FRAME_H; names = row_names(rows)
    alpha = _cell_alpha(path, rows)
    counts, present = [], []
    for r in range(rows):
        n = 0
        if alpha:
            for c in range(min(COLS, 8)):
                if alpha[r * COLS + c] > 8: n = c + 1
        counts.append(max(1, n) if alpha else 6); present.append(n > 0 if alpha else True)
    looks = []
    if rows == 8:
        looks = [{"name": names[r], "row": r, "frames": counts[r], "present": present[r]} for r in range(rows)]
    else:
        run = next((r for r in (7, 1, 2) if present[r]), None)
        for r, name in enumerate(names):
            if name in ("running", "running-right", "running-left"): continue
            looks.append({"name": name, "row": r, "frames": counts[r], "present": present[r]})
        looks.insert(1, {"name": "running", "row": run if run is not None else 7, "frames": counts[run] if run is not None else 6, "present": run is not None})
    return {"rows": rows, "looks": looks, "measured": bool(alpha)}
```

In `list_pets`, add to the appended dict: `"license": (meta.get("source") or {}).get("license", ""), "source": (meta.get("source") or {}).get("site", "")`. In `cmd_pets`:

```python
def cmd_pets(args, ctx):
    pets = list_pets() + list_props()
    if args.looks is not None:
        want = [p for p in pets if not p.get("prop") and (args.looks == "" or p["slug"] == args.looks)]
        if not want: print(f"no pet '{args.looks}'", file=sys.stderr); return 2
        for p in want:
            info = sheet_looks(p["sheet"])
            if not info: print(f"{p['slug']:<20} not a {FRAME_W * COLS}×k·{FRAME_H} sheet"); continue
            have = [l for l in info["looks"] if l["present"]]
            tail = "" if info["measured"] else "  (geometry only — install Pillow or ImageMagick to measure)"
            print(f"{p['slug']:<20} looks: " + ", ".join(f"{l['name']} ×{l['frames']}" for l in have) + f" ({len(have)} of {len(info['looks'])}){tail}")
        return 0
    if args.json: print(json.dumps({"pets": pets})); return 0
    if not pets:
        print("no sprite sheets found — `desktop-widgets pet fetch <petdex url>` downloads one, or /hatch one in Hermes"); return 0
    for p in pets: print(f"{p['slug']:<20} {p['origin']:<14} {('prop: ' if p.get('prop') else '') + p['name']:<20} {p.get('license') or '':<9} {p['sheet']}")
    return 0
```
Parser: `pt.add_argument("--looks", nargs="?", const="", metavar="SLUG", help="rows and frames per look (all pets, or one slug)")`.

- [ ] **Step 4: Run both suites** — expected green; `SheetProbe.test_sheet_looks_geometry_and_pixels` measures on this laptop (magick present) and takes the geometry branch elsewhere.

- [ ] **Step 5: Live** — `desktop-widgets pets --looks` → every local sheet lists its looks (jill-stingray, teto, hermes-girl, hanna: expect 7 of 9 or fewer, measured). Then `desktop-widgets pet check` on the live config.

- [ ] **Step 6: Commit**

```bash
git add bin/desktop-widgets tests/test_cli.py
git commit -m "CLI: pets --looks (PNG/WebP header parse, Pillow/magick pixel probe, geometry fallback); licence/source columns"
```

---

### Task 7: Editor — per-key row controls, kind-specific add buttons, warnings, "Customise these rules"

**Files:**
- Modify: `editor/FieldControl.qml` (rows editor), `editor/EditorForm.qml`, `Editor.qml`

**Interfaces:**
- Consumes: registry `rowFields`, `Pet.validateRules`, `Pet.presetRows`, `Pet.SIGNAL_KEYS`, `service.petStates`.
- Produces: FieldControl `property var rowContext: ({ looks: [], signals: [], pets: [] })` and `property var warnings: []` (`[{row, message}]`); EditorForm `property var rowContext`, `property var ruleWarnings`; Editor computes both for the selected pet.

- [ ] **Step 1: FieldControl.qml** — extend `rowKeys`:

```qml
  readonly property var rowKeys: ({ heading: ["text"], text: ["text"], kv: ["label", "value"], bar: ["label", "value", "text", "max", "warnAt"], spacer: ["height"],
    when: ["if", "state", "say"], on: ["if", "state", "beat", "say"],
    range: ["signal", "min", "max", "look", "beat", "say", "and"], flag: ["signal", "is", "look", "beat", "say", "and"], keyword: ["signal", "words", "match", "look", "beat", "say", "and"], pet: ["pet", "look", "then", "beat", "say"],
    image: ["image", "z", "x", "y", "scale"], sheet: ["sheet", "z", "x", "y", "scale", "follow"], command: ["key", "command"] })
  readonly property var numericKeys: ({ warnAt: true, height: true, min: true, max: true, beat: true })
  property var rowContext: ({ looks: [], signals: [], pets: [] })
  property var warnings: []
  function hint(k) { var rf = root.field.rowFields || {}; return rf[k] || null }
  function enumFor(k, current) {
    var h = hint(k), list = []
    if (!h) return null
    if (h.options) list = h.options.slice()
    else if (h.enum === "looks") list = (root.rowContext.looks || []).slice()
    else if (h.enum === "signals") list = (root.rowContext.signals || []).slice()
    else if (h.enum === "pets") list = (root.rowContext.pets || []).slice()
    if (!list.length && !h.options) return null                       // nothing known yet: fall back to a text box
    if (current !== "" && list.indexOf(current) === -1) list.unshift(current)
    return list.map(function(o) { return { value: o, label: o } })
  }
```

In the rows delegate, replace the inner `Repeater { model: root.rowKeys[…]; delegate: TextField {…} }` with a Loader per key that picks the control:

```qml
          Repeater {
            model: root.rowKeys[String(modelData.kind || "text")] || ["text"]
            delegate: Loader {
              required property var modelData
              readonly property string k: String(modelData)
              readonly property var rowRef: parent.modelData
              readonly property int rowIndex: parent.index
              readonly property string current: rowRef[k] === undefined ? "" : String(rowRef[k])
              readonly property var opts: root.enumFor(k, current)
              readonly property bool isBool: (root.hint(k) || {}).type === "boolean"
              Layout.fillWidth: !opts && !isBool && (k === "text" || k === "value" || k === "label" || k === "if" || k === "words" || k === "and" || k === "command")
              Layout.preferredWidth: Layout.fillWidth ? -1 : (opts ? Style.space(120) : Style.space(64))
              function commit(v) {
                var a = root.rowsArray(); var row = a[rowIndex]
                if (v === "" || v === undefined) delete row[k]
                else if (root.numericKeys[k]) { var n = parseFloat(v); if (!isNaN(n)) row[k] = n }
                else row[k] = v
                if (JSON.stringify(a[rowIndex]) !== JSON.stringify(root.rowsArray()[rowIndex])) root.emitRows(a)
              }
              sourceComponent: isBool ? rowBool : (opts ? rowEnum : rowText)
              Component { id: rowBool; Item { implicitWidth: sw.implicitWidth + hintText.implicitWidth + Style.spacing.xs; implicitHeight: sw.implicitHeight
                RowLayout { spacing: Style.spacing.xs; Text { id: hintText; text: k; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  ToggleSwitch { id: sw; checked: rowRef[k] !== false && rowRef[k] !== "false"; onToggled: commit(!(rowRef[k] !== false && rowRef[k] !== "false")) } } } }
              Component { id: rowEnum; Dropdown { showLabel: false; value: current; options: opts; onChanged: function(v) { commit(v) } } }
              Component { id: rowText; TextField { placeholderText: k; text: current
                onEditingFinished: commit(text)
                Keys.onEscapePressed: function(e) { focus = false; e.accepted = true } } }
            }
          }
```
(`Loader` items need `Layout.*` attached properties on the Loader itself — they are, above. Inside the components, `k`, `rowRef`, `current`, `opts`, `commit` resolve through the Loader's scope.) Note: a flag row's `is` key is absent when true; the toggle writes `false` explicitly and deletes the key for true via `commit("")`? No — `commit(true)` stores `true`, which is fine: the compiler treats anything but `false` as true.

Under the rows, a warnings block and kind-specific add buttons — replace the single `Button { text: "+ row" … }` with:

```qml
      Repeater {
        model: root.warnings
        delegate: Text { required property var modelData; text: "row " + modelData.row + ": " + modelData.message; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; Layout.fillWidth: true }
      }
      RowLayout {
        spacing: Style.spacing.xs
        Repeater {
          model: (root.field.options || []).indexOf("range") !== -1 ? ["range", "flag", "keyword", "pet", "when"] : [String((root.field.options || [])[0] || "text")]
          delegate: Button {
            required property var modelData
            text: "+ " + modelData; bordered: true
            onClicked: { var a = root.rowsArray(); a.push(root.newRow(String(modelData))); root.emitRows(a) }
          }
        }
      }
```
with a helper on the root:

```qml
  function newRow(kind) {
    switch (kind) {
      case "range": return { kind: "range", signal: "cpu", min: 60, look: "running" }
      case "flag": return { kind: "flag", signal: "battery.charging", is: true, look: "running" }
      case "keyword": return { kind: "keyword", signal: "claude.label", words: "", match: "any", look: "review" }
      case "pet": return { kind: "pet", pet: (root.rowContext.pets || [])[0] || "", look: "failed", then: "waving", beat: 2 }
      case "when": return { kind: "when", if: "", state: "idle" }
      case "command": return { kind: "command", key: "", command: "" }
      case "image": return { kind: "image", image: "" }
      case "sheet": return { kind: "sheet", sheet: "" }
      default: return { kind: kind, text: "" }
    }
  }
```
(This also fixes the layers/signals fields, whose "+ row" used to add a `text` row of an unknown kind.)

- [ ] **Step 2: EditorForm.qml** — add `property var rowContext: ({ looks: [], signals: [], pets: [] })`, `property var ruleWarnings: []`, `property var presetRows: null` (function) and pass them: in the delegate, `FieldControl { …; rowContext: root.rowContext; warnings: modelData.key === "rules" ? root.ruleWarnings : [] }`. After the FieldControl add the customise button:

```qml
        Button {
          visible: modelData.key === "watch" && root.entry && String(root.entry.type) === "pet" && String(Model.valueOf(root.entry, "watch", root.registry)) !== "custom"
          text: "Customise these rules"; bordered: true; tooltipText: "copies the preset's rows into Rules and switches to custom"
          Layout.leftMargin: Style.space(190) + Style.spacing.md
          onClicked: { root.edited("rules", Pet.presetRows(Model.valueOf(root.entry, "watch", root.registry))); root.edited("watch", "custom") }
        }
```
with `import "../widgets/Pet.js" as Pet` at the top.

- [ ] **Step 3: Editor.qml** — compute the context and warnings for the selected pet and pass them:

```qml
  readonly property var petRowContext: {
    var e = selectedEntry
    if (!e || String(e.type) !== "pet") return { looks: [], signals: [], pets: [] }
    var me = Pet.petName(e), states = service ? service.petStates : {}
    var pets = [], sigs = Pet.SIGNAL_KEYS.slice()
    for (var k in states) if (k !== me) { pets.push(k); sigs.push("pets." + k + ".state"); sigs.push("pets." + k + ".say") }
    var rows = e.signals && typeof e.signals.length === "number" ? e.signals : []
    for (var i = 0; i < rows.length; i++) if (rows[i] && rows[i].key) sigs.push("custom." + rows[i].key)
    var lk = states[me] && states[me].looks ? states[me].looks.filter(function(l) { return l.present }).map(function(l) { return l.name }) : Pet.LOOKS.slice()
    return { looks: lk, signals: sigs, pets: pets }
  }
  readonly property var petRuleWarnings: selectedEntry && String(selectedEntry.type) === "pet" && String(Model.valueOf(selectedEntry, "watch", registry)) === "custom"
    ? Pet.validateRules(Array.prototype.slice.call(selectedEntry.rules || []), petRowContext) : []
```
and on the `EditorForm { … rowContext: root.petRowContext; ruleWarnings: root.petRuleWarnings }`. (`Model` is already imported in Editor.qml as `EditorModel.js`; check the alias name at the top of the file and use it.) Because `doc` is re-sliced on every `touch()`, `selectedEntry` changes and both properties recompute.

- [ ] **Step 4: Live check** — restart the shell, open the editor, select a pet on a preset, click **Customise these rules** → rows appear as range/flag rows with dropdowns for `look` listing that sheet's looks and a `signal` dropdown; add a `pet` row → the `pet` dropdown lists the other pets; type `nope` into a raw `when` test → a red "row N: unknown signal 'nope'" line; Save. Verify the file via `desktop-widgets list` and `desktop-widgets pet check`.

- [ ] **Step 5: Commit**

```bash
git add editor/FieldControl.qml editor/EditorForm.qml Editor.qml
git commit -m "Editor: structured rule rows with look/signal/pet dropdowns, per-kind add buttons, inline rule warnings, Customise these rules"
```

---

### Task 8: petdex fetcher — `desktop-widgets pet fetch`

**Files:**
- Modify: `bin/desktop-widgets` (petdex section after the pets section; `cmd_pet` fetch branch; parser)
- Create: `tests/fixtures/petdex/install-curated.sh`, `install-community.sh`, `install-404.sh`, `install-badhost.sh`, `install-missing.sh`
- Test: `tests/test_cli.py`

**Interfaces:**
- Produces: `petdex_slug(text) → slug` (raises `ValueError` with the reason); `parse_install_script(text) → {"petjson": url, "sheet": url, "displayName": str}` (raises `ValueError`); `petdex_license(html) → "CC0"|"CC-BY"|"CC-BY-SA"|"CC-BY-NC"|"unknown"`; `fetch_pet(target, dest_root, http, force=False) → dict` with keys `slug, name, path, sheet, rows, looks, license, url`; `http(url, headers, limit) → bytes` is injectable (default `_http_get` on `urllib.request` with `Referer: https://petdex.dev/`, 15 s timeout, 25 MB cap); exit codes 0 ok · 2 not a petdex URL · 3 not found · 4 network · 5 invalid pet · 6 exists. `FetchError(code, message)` exception carries the exit code. `--json` prints the result dict; `--add` appends a pet widget (`sheet`, `name` = slug); `--widget N` sets `sheet` + `name` on widget N.

- [ ] **Step 1: Fixtures** — `tests/fixtures/petdex/install-curated.sh`:

```sh
#!/bin/sh
set -e
PETDEX_REFERER="https://petdex.dev/"
DISPLAY_NAME='Boba'
PET_DIR="$HOME/.hermes/pets/boba"
mkdir -p "$PET_DIR"
curl -fsSL -e "$PETDEX_REFERER" -o "$PET_DIR/pet.json" 'https://assets.petdex.dev/curated/boba/petjson-v2.json'
curl -fsSL -e "$PETDEX_REFERER" -o "$PET_DIR/spritesheet.webp" 'https://assets.petdex.dev/curated/boba/sprite-v2.webp'
echo "Installed $DISPLAY_NAME"
```
`install-community.sh`: same with `DISPLAY_NAME='Cat Sam'`, `PET_DIR="$HOME/.hermes/pets/cat-sam"`, URLs `https://assets.petdex.dev/pets/cat-sam-9f3a1c/petjson.json` and `…/sprite.webp`. `install-404.sh`: `#!/bin/sh\necho "Pet not found" >&2\nexit 1`. `install-badhost.sh`: the curated script with the sheet URL host changed to `https://evil.example/curated/boba/sprite-v2.webp`. `install-missing.sh`: the curated script without the `spritesheet.webp` line.

- [ ] **Step 2: Write the failing tests** (new class in `tests/test_cli.py`)

```python
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
            "https://petdex.dev/pets/boba": b"<html>… <span>CC0</span> …</html>",
            "https://petdex.dev/pets/cat-sam": b"<html>licensed CC-BY-NC by someone</html>",
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
        self.assertEqual(dw.petdex_license("<b>CC-BY-SA</b>"), "CC-BY-SA"); self.assertEqual(dw.petdex_license("cc0 1.0"), "CC0"); self.assertEqual(dw.petdex_license("nothing"), "unknown")

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
        self.assertEqual(dw.fetch_pet("boba", str(self.root), self.http, force=True)["slug"], "boba")

    def test_fetch_size_cap(self):
        big = b"x" * (dw.PETDEX_MAX_BYTES + 1)
        with self.assertRaises(dw.FetchError) as cm: dw._check_size(big)
        self.assertEqual(cm.exception.code, 5)
```
and in `Cli`:

```python
    def test_pet_fetch_cli_add_and_widget(self):
        fx = ROOT / "tests" / "fixtures" / "petdex"
        pages = {"https://petdex.dev/install/boba": (fx / "install-curated.sh").read_bytes(), "https://petdex.dev/pets/boba": b"CC0",
                 "https://assets.petdex.dev/curated/boba/petjson-v2.json": json.dumps({"id": "boba", "displayName": "Boba", "spritesheetPath": "spritesheet.webp"}).encode(),
                 "https://assets.petdex.dev/curated/boba/sprite-v2.webp": _png(1536, 1872)}
        old = dw.HTTP_GET; dw.HTTP_GET = lambda url, headers=None, limit=None: pages[url]
        try:
            code, out, err = self.run_cli("pet", "fetch", "https://petdex.dev/pets/boba", "--json", "--add")
            self.assertEqual(code, 0, err); r = json.loads(out)
            self.assertEqual(r["slug"], "boba"); self.assertTrue(r["path"].startswith(str(self.home)))
            w = json.loads(self.cfg.read_text())["widgets"][-1]
            self.assertEqual((w["type"], w["name"], w["sheet"]), ("pet", "boba", str(self.home / ".config" / "omarchy" / "desktop-widgets.pets" / "boba" / "spritesheet.webp")))
            code, out, err = self.run_cli("pet", "fetch", "boba", "--force", "--widget", "0")
            self.assertEqual(code, 2); self.assertIn("not a pet", err)                      # widget 0 is the clock
            code, out, err = self.run_cli("pet", "fetch", "boba", "--force", "--widget", "2")
            self.assertEqual(code, 0, err); w2 = json.loads(self.cfg.read_text())["widgets"][2]
            self.assertEqual((w2["type"], w2["name"], w2["sheet"].endswith("boba/spritesheet.webp")), ("pet", "boba", True))
            code, out, err = self.run_cli("pet", "fetch", "https://evil.dev/x")
            self.assertEqual(code, 2); self.assertIn("petdex", err)
        finally:
            dw.HTTP_GET = old
```

- [ ] **Step 3: Run to verify failure** — `python3 -m unittest tests.test_cli.Petdex 2>&1 | tail -3` → attribute errors.

- [ ] **Step 4: Implement** — add after the pets section:

```python
# ---------------------------------------------------------------- petdex fetcher (parse the installer as a manifest; never run it)
PETDEX_MAX_BYTES = 25 * 1024 * 1024
PETDEX_SLUG = re.compile(r"^[a-z0-9][a-z0-9-]{0,63}$")
_CURL_LINE = re.compile(r"""curl\s[^\n]*-o\s+"\$PET_DIR/([A-Za-z0-9_.-]+)"\s+'([^']+)'""")


class FetchError(Exception):
    def __init__(self, code, message): super().__init__(message); self.code = code


def _http_get(url, headers=None, limit=PETDEX_MAX_BYTES):
    import urllib.request, urllib.error
    req = urllib.request.Request(url, headers={"User-Agent": "desktop-widgets/petdex-fetch", "Referer": "https://petdex.dev/", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = r.read(limit + 1)
    except urllib.error.HTTPError as e:
        raise FetchError(3 if e.code == 404 else 4, f"{'not on petdex' if e.code == 404 else 'network'}: HTTP {e.code} for {url}")
    except Exception as e:
        raise FetchError(4, f"network: {e}")
    return data


HTTP_GET = _http_get


def _check_size(data):
    if len(data) > PETDEX_MAX_BYTES: raise FetchError(5, f"file larger than {PETDEX_MAX_BYTES // (1024 * 1024)} MB")
    return data


def petdex_slug(text):
    t = str(text or "").strip()
    if not t: raise ValueError("no petdex URL or slug given")
    if "://" in t or t.startswith(("petdex.dev/", "www.petdex.dev/")):
        from urllib.parse import urlparse
        u = urlparse(t if "://" in t else "https://" + t)
        if u.scheme != "https" or u.netloc not in ("petdex.dev", "www.petdex.dev"): raise ValueError("not a petdex.dev https URL")
        m = re.match(r"^/(?:[a-z]{2}/)?(?:pets|install)/([^/]+)/?$", u.path)
        if not m: raise ValueError("not a petdex pet page (expected petdex.dev/pets/<slug>)")
        t = m.group(1)
    if not PETDEX_SLUG.match(t): raise ValueError(f"'{t}' is not a petdex slug (lowercase letters, digits, dashes)")
    return t


def parse_install_script(text):
    files = {name: url for name, url in _CURL_LINE.findall(text)}
    m = re.search(r"^DISPLAY_NAME='([^']*)'", text, re.M)
    if "pet.json" not in files or "spritesheet.webp" not in files: raise ValueError("installer is missing the pet.json or spritesheet line")
    for url in files.values():
        if not url.startswith("https://assets.petdex.dev/"): raise ValueError(f"refusing asset host in {url}")
    return {"petjson": files["pet.json"], "sheet": files["spritesheet.webp"], "displayName": m.group(1) if m else ""}


def petdex_license(html):
    t = str(html or "").upper().replace("‑", "-")
    for lab in ("CC-BY-NC-SA", "CC-BY-NC", "CC-BY-SA", "CC-BY", "CC0"):
        if lab in t or lab.replace("-", " ") in t: return lab
    return "unknown"


def fetch_pet(target, dest_root, http=None, force=False):
    http = http or HTTP_GET
    try: slug = petdex_slug(target)
    except ValueError as e: raise FetchError(2, str(e))
    page_url = f"https://petdex.dev/pets/{slug}"
    script = http(f"https://petdex.dev/install/{slug}").decode("utf-8", "replace")
    if "exit 1" in script and "curl" not in script: raise FetchError(3, f"'{slug}' is not on petdex")
    try: manifest = parse_install_script(script)
    except ValueError as e: raise FetchError(5, str(e))
    meta_raw = _check_size(http(manifest["petjson"])); sheet_raw = _check_size(http(manifest["sheet"]))
    try: meta = json.loads(meta_raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError): raise FetchError(5, "pet.json is not JSON")
    if not isinstance(meta, dict) or not meta.get("id"): raise FetchError(5, "pet.json has no id")
    g = image_geometry(sheet_raw[:64])
    if not g: raise FetchError(5, "sheet is not a PNG or WebP")
    if g[1] != FRAME_W * COLS or g[2] % FRAME_H or not 8 <= g[2] // FRAME_H <= 11: raise FetchError(5, f"sheet is {g[1]}×{g[2]}, expected {FRAME_W * COLS}×(8..11×{FRAME_H})")
    license_ = "unknown"
    try: license_ = petdex_license(http(page_url, limit=2 * 1024 * 1024).decode("utf-8", "replace"))
    except Exception: pass
    dest = os.path.join(dest_root, slug)
    if os.path.exists(dest) and not force: raise FetchError(6, f"{dest} exists (use --force to replace)")
    os.makedirs(dest_root, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix=".fetch-", dir=dest_root)
    try:
        meta["displayName"] = meta.get("displayName") or manifest["displayName"] or slug
        meta["spritesheetPath"] = "spritesheet.webp"
        meta["source"] = {"site": "petdex", "url": page_url, "fetchedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"), "license": license_}
        with open(os.path.join(tmp, "pet.json"), "w") as fh: json.dump(meta, fh, indent=2); fh.write("\n")
        with open(os.path.join(tmp, "spritesheet.webp"), "wb") as fh: fh.write(sheet_raw)
        if os.path.exists(dest): shutil.rmtree(dest)
        os.replace(tmp, dest)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True); raise
    info = sheet_looks(os.path.join(dest, "spritesheet.webp")) or {"rows": g[2] // FRAME_H, "looks": []}
    return {"slug": slug, "name": meta["displayName"], "path": dest, "sheet": os.path.join(dest, "spritesheet.webp"), "rows": info["rows"], "looks": info["looks"], "license": license_, "url": page_url}
```
(`sheet_looks` accepts a `.webp` name with PNG bytes because it reads the header, not the extension; petdex serves WebP anyway.)

The `fetch` branch in `cmd_pet` (the `index` positional becomes `target`, a string; `expand`/`check` convert with `int()`):

```python
    if args.op == "fetch":
        if not args.target: print("pet fetch needs a petdex URL or slug", file=sys.stderr); return 2
        root_dir = os.path.join(_config_base(), "omarchy", "desktop-widgets.pets")
        try: r = fetch_pet(args.target, root_dir, force=args.force)
        except FetchError as e: print(str(e), file=sys.stderr); return e.code
        if args.add or args.widget is not None:
            def fn(doc, widgets):
                if args.widget is not None:
                    e = index_arg(widgets, args.widget)
                    if e.get("type") != "pet": raise ValueError(f"widget {args.widget} is not a pet")
                    e["sheet"] = r["sheet"]; e["name"] = r["slug"]
                else: widgets.append({"type": "pet", "sheet": r["sheet"], "name": r["slug"]})
            code = mutate(args, ctx, fn, create=True)
            if code: return code
        if args.json: print(json.dumps(r)); return 0
        have = [l for l in r["looks"] if l["present"]]
        print(f"{r['slug']}  {r['name']}  {r['license']}\n{r['path']}\n{len(have)} looks: " + ", ".join(l["name"] for l in have)); return 0
```
Parser (replace Task 4's `pet` parser):

```python
    pe = sub.add_parser("pet", help="pet helpers: expand <index> (preset rules → editable rows) | check [index] (validate rules) | fetch <petdex url or slug> [--add | --widget N] [--force]")
    pe.add_argument("op", choices=["expand", "check", "fetch"]); pe.add_argument("target", nargs="?", help="widget index, or for fetch a petdex.dev URL / slug")
    pe.add_argument("--json", action="store_true"); pe.add_argument("--force", action="store_true"); pe.add_argument("--add", action="store_true", help="fetch: append a pet widget using it"); pe.add_argument("--widget", type=int, metavar="N", help="fetch: point pet widget N at it")
    pe.set_defaults(fn=cmd_pet)
```
and at the top of `cmd_pet`: `args.index = int(args.target) if args.op != "fetch" and args.target not in (None, "") else None` (wrap in `try/except ValueError` → print "index must be a number", return 2).

- [ ] **Step 5: Run both suites** → green.

- [ ] **Step 6: Live (network, free, one curated + one community pet)**

```bash
desktop-widgets pet fetch https://petdex.dev/pets/boba          # expect: boba  Boba  <licence>, path under ~/.config/omarchy/desktop-widgets.pets/boba, N looks
desktop-widgets pets --looks boba
desktop-widgets pet fetch <a community pet URL from petdex.dev/pets>  # pick one from the site's listing
```
If petdex has changed its installer shape, the parser raises exit 5 with the reason — fix the regex, do not loosen the host check.

- [ ] **Step 7: Commit**

```bash
git add bin/desktop-widgets tests/test_cli.py tests/fixtures/petdex
git commit -m "CLI: desktop-widgets pet fetch <petdex url|slug> — installer parsed as a manifest, assets host-pinned, sheet validated, provenance + licence label; --add / --widget"
```

---

### Task 9: Editor — paste + Download

**Files:**
- Modify: `widgets/registry.json` (pet `petdex` field), `editor/FieldControl.qml` (`petdex` control), `widgets/Registry.js` + `bin/desktop-widgets` (ignore `petdex` as a stored key — it is a control, not a config key)

**Interfaces:**
- Registry: `{ "key": "petdex", "type": "petdex", "label": "Get a pet", "description": "paste a petdex.dev pet URL and press Download; the sheet lands in ~/.config/omarchy/desktop-widgets.pets/<slug>/ and this pet points at it" }` placed **before** `sheet` in `pet.fields`.
- Both validators: fields of type `petdex` are never stored — `applyDefaults` skips them (no default), `_check_field`/`checkField` ignore the type, and `known` keys exclude them so a stray `petdex` key in a file warns like any unknown key. `desktop-widgets types pet` lists it as `petdex (editor control)`.
- FieldControl `petdexComp`: TextField (placeholder `https://petdex.dev/pets/<slug>`) + `Download` Button + status Text + an "Installed…" Dropdown (from `pets --json`, non-prop entries) that sets `sheet`/`name` directly. Download runs `[cli, "pet", "fetch", url, "--json", "--force"]`; on exit 0 parses stdout and emits `edited("sheet", r.sheet)` then `edited("name", r.slug)`; status `"<name> · <n> looks · <licence>"`; on failure the CLI's first stderr line.

- [ ] **Step 1: Registry + validators** — insert the field; in `Registry.js` `fieldsFor`/`validateEntry` nothing needs to change for an unknown type (the `default:` branch ignores it) — verify with a fixture: `tests/fixtures/validate/pet-petdex-key-is-stray.json`:

```json
{ "config": { "widgets": [ { "type": "pet", "sheet": "/x/spritesheet.webp", "petdex": "https://petdex.dev/pets/boba" } ] },
  "expect": { "widgets": 1, "errors": 0, "warnings": 1, "messages": [ "widget 0: unknown key 'petdex'" ] } }
```
To make that true, both `fieldsFor` implementations must drop `type: "petdex"` fields from the stored-key set: in `Registry.js` `validateEntry`, build `known` only from fields whose type is not `petdex`; in Python `validate_config`, same filter on the `known` set. Also `EditorModel.newEntry`/`setValue` never store it because the control emits `sheet`/`name`, not `petdex`. Python `cmd_types` prints `petdex` fields with a `(editor control)` suffix.

- [ ] **Step 2: FieldControl** — add `case "petdex": return petdexComp` to the Loader switch (and include it in `wide`), then:

```qml
  readonly property string cliPath: String(Qt.resolvedUrl("../bin/desktop-widgets")).replace(/^file:\/\//, "")
  Component {
    id: petdexComp
    ColumnLayout {
      spacing: Style.spacing.xs
      property string status: ""
      property var installed: []
      RowLayout {
        spacing: Style.spacing.sm
        TextField { id: urlField; Layout.fillWidth: true; placeholderText: "https://petdex.dev/pets/<slug>"; enabled: !fetcher.running
          onAccepted: if (text.trim() !== "") fetcher.start(text.trim()) }
        Button { text: fetcher.running ? "Downloading…" : "Download"; bordered: true; enabled: !fetcher.running && urlField.text.trim() !== ""; onClicked: fetcher.start(urlField.text.trim()) }
        Dropdown { showLabel: false; implicitWidth: Style.space(150); value: ""; placeholderText: "Installed…"
          options: [{ value: "", label: "Installed…" }].concat(installed.map(function(p) { return { value: p.sheet + "|" + p.slug, label: p.name + (p.license ? " · " + p.license : "") } }))
          onChanged: function(v) { if (!v) return; var parts = v.split("|"); root.edited("sheet", parts[0]); root.edited("name", parts[1]); status = "using " + parts[1] }
          Component.onCompleted: lister.running = true }
      }
      Text { visible: status !== ""; text: status; color: status.indexOf("ERROR") === 0 ? Color.urgent : Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; Layout.fillWidth: true }
      Process {
        id: fetcher
        property string url: ""
        function start(u) { url = u; status = "downloading " + u + "…"; running = true }
        command: [root.cliPath, "pet", "fetch", url, "--json", "--force"]
        stdout: StdioCollector { id: fetchOut }
        stderr: StdioCollector { id: fetchErr }
        onExited: function(code) {
          if (code !== 0) { status = "ERROR " + String(fetchErr.text || "").trim().split("\n")[0]; return }
          var r; try { r = JSON.parse(String(fetchOut.text || "")) } catch (e) { status = "ERROR bad reply from the CLI"; return }
          root.edited("sheet", r.sheet); root.edited("name", r.slug)
          var have = (r.looks || []).filter(function(l) { return l.present }).length
          status = r.name + " · " + have + " looks · " + r.license
          lister.running = true
        }
      }
      Process { id: lister; command: [root.cliPath, "pets", "--json"]; stdout: StdioCollector { id: listOut }
        onExited: { var l = []; try { l = (JSON.parse(String(listOut.text || "{}")).pets || []).filter(function(p) { return !p.prop }) } catch (e) {} installed = l } }
    }
  }
```
`Dropdown` may lack `placeholderText`; if the shell's `qs.Ui.Dropdown` rejects it, drop that property (the first option carries the label).

- [ ] **Step 3: Live check** — restart the shell, open the editor, select a pet, paste `https://petdex.dev/pets/boba`, Download → status shows name · looks · licence, `sheet` and `name` fields update, Save; the pet on the desktop changes to Boba. Pick another sheet from **Installed…** → fields update. Paste `https://evil.dev/x` → "ERROR not a petdex.dev https URL".

- [ ] **Step 4: Run both suites, commit**

```bash
git add widgets/registry.json widgets/Registry.js bin/desktop-widgets editor/FieldControl.qml tests/fixtures/validate/pet-petdex-key-is-stray.json
git commit -m "Editor: petdex paste + Download control on the pet type (runs the CLI; shell does no networking); Installed… picker"
```

---

### Task 10: Docs, changelog, vault, push

**Files:**
- Modify: `README.md` (pet section: looks, structured rules with the kinds table, `signals`, `pet expand|check|fetch`, `pets --looks`), `CHANGELOG.md` (Unreleased block), `docs/ROADMAP.md` (pet looks/petdex → DONE, link this plan), this plan's status table, vault `03 Resources/Tool Guides/Omarchy Desktop Widgets.md` + `01 Projects/Omarchy Desktop Widgets.md`.

- [ ] **Step 1: README** — in the pet bullet list add:

```
  **Looks**: a look is a sheet row with at least one drawn cell; `desktop-widgets pets --looks` and the editor
  (under the sheet field) show which looks a sheet has and how many frames each has. A rule that names a look the
  sheet lacks falls back: jumping → waving, waiting → review, failed → waiting, then idle.
  **Rules without expressions**: with `watch: custom` the `rules` rows can be `range` (`signal`, `min`/`max`;
  `min > max` wraps, so `hour` 23→6 is night), `flag` (`signal`, `is`), `keyword` (`signal`, comma-separated
  `words`, `match` any|all|none — case-insensitive substrings), `pet` (`pet`, `look`, `then`), or raw `when`/`on`.
  Every row takes `look` (`then` for pet rows), `say`, `beat` (seconds; makes it a one-shot) and `and` (an extra raw
  test). Top-down, first steady match wins. **Customise these rules** in the editor (or `desktop-widgets pet expand N`)
  copies the preset you were watching into editable rows. `desktop-widgets pet check` lists rule problems; the editor
  shows them under the rows. Extra text/number signals: `signals` rows (`key`, `command`) become `custom.<key>` —
  e.g. the focused window title for a keyword rule. One `dw-signals` sampler serves every pet. Rules that read
  another pet see its *previous* tick, so a chain of three pets reacts in three intervals. Two pets on the same
  sheet folder publish as `teto` and `teto_2` (set `name` to choose).
  **petdex**: paste a `https://petdex.dev/pets/<slug>` URL into the editor's *Get a pet* box and press Download, or
  `desktop-widgets pet fetch <url|slug> [--add | --widget N]`. The installer script is parsed as a manifest (never
  run), assets must come from `assets.petdex.dev`, the sheet is validated, and the licence label from the pet page is
  stored in `pet.json` (`source.license`; shown by `desktop-widgets pets`). Art stays under
  `~/.config/omarchy/desktop-widgets.pets/<slug>/`, never in the plugin.
```
CLI table rows: `pet expand <i>`, `pet check [i] [--json]`, `pet fetch <url|slug> [--add|--widget N] [--force] [--json]`, `pets --looks [slug]`.

- [ ] **Step 2: CHANGELOG** — top:

```
## Unreleased
- **Pet looks**: looks are measured from the sheet (rows with drawn cells; frames per look), published as `pets.<name>.looks`, shown under the sheet field and by `desktop-widgets pets --looks`; missing looks fall back along a chain instead of row 0.
- **Structured rules**: `range` / `flag` / `keyword` / `pet` rows compile onto the existing rule engine (`~` = case-insensitive contains); presets are now rows you can copy and edit (**Customise these rules**, `pet expand`); `pet check` + inline editor warnings (unknown signal, bad expression, look not on this sheet, min ≥ max…); `and` extra test on any row; held edges — a beat that starts while another plays no longer disappears.
- **Extra signals**: `signals` rows on a pet run commands (`custom.<key>`); one shared sampler per service instead of one per pet.
- **petdex fetcher**: `desktop-widgets pet fetch <url|slug>` and the editor's *Get a pet* paste + Download; installer parsed as a manifest, host-pinned assets, sheet validated, provenance + licence label in `pet.json`; `--add` / `--widget N`.
- Registry: `rowFields` hints (dropdowns/toggles/numbers per row key) for `rows` fields; drop-ins get them too. Editor adds rows per kind (no more `text` rows in layers/signals).
```

- [ ] **Step 3: ROADMAP + plan status table** — mark the pet looks/petdex item DONE with the plan path; fill this plan's status table (below).

- [ ] **Step 4: Vault** — Tool Guide: new "Pet looks and rules" + "Getting a pet from petdex" subsections mirroring the README; project note: a dated section "2026-09-13 — Pet looks + petdex fetcher BUILT on `feat/pet-looks-petdex`" and the pick-up list (agent Skill still next).

- [ ] **Step 5: Run both suites, commit, push both remotes**

```bash
node --test tests/*.test.js 2>&1 | tail -3; python3 -m unittest discover -s tests 2>&1 | tail -3
git add README.md CHANGELOG.md docs/ROADMAP.md docs/superpowers/plans/2026-09-13-pet-looks-and-petdex-fetch.md
git commit -m "docs: pet looks, structured rules, extra signals, petdex fetcher"
git push github feat/pet-looks-petdex; git push origin feat/pet-looks-petdex   # origin = Forge; if DNS still fails, say so and push later
```

## Status

| Task | State | Notes |
|---|---|---|
| 1 Looks inventory (Pet.js) | | |
| 2 Widget publishes looks; editor looks line | | |
| 3 Compiler, `~`, presets as rows, validator, held edges (JS) | | |
| 4 Python twin + `pet expand/check` + registry | | |
| 5 Custom command signals + shared sampler | | |
| 6 `pets --looks` + sheet probe | | |
| 7 Editor rule rows | | |
| 8 `pet fetch` CLI | | |
| 9 Editor Download | | |
| 10 Docs + push | | |
