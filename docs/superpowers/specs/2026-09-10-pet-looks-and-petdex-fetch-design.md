# Pet looks, look rules, and the petdex fetcher — design (2026-09-10)

> **Status:** proposal for Michael. Nothing built. Decisions for him at the end.
> Branch `feat/pet-looks-petdex` (docs only so far).

**Ask:** (1) know how many *looks* a pet has and let the user say *when* each look plays with
basic logic — brackets for a percentage, keywords for text, "when that other pet does X" for a
linked pet; (2) a download path for petdex.dev: paste a URL, click Download, and the pet lands
with the right name and path.

## 0. What exists today (read from the code, 2026-09-10)

- A pet is one sheet (192×208 cells, 8 columns). Rows are the looks. `Pet.js` names them:
  Codex 9-row `idle, running-right, running-left, waving, jumping, failed, waiting, running,
  review`; legacy 8-row `idle, waving, running, failed, review, jumping, extra1, extra2`.
  Every sheet on this machine (jill-stingray, teto, hermes-girl) is 1536×1872 = 9 rows.
- The look is chosen by rules over `bin/dw-signals` JSON (`claude.*`, `battery.*`,
  `agents.active`, `cpu`, `mem`, `gpu`, `load`, `temp`, `hour`) plus `pets.<name>.{state,say,watch}`
  published by the other pets. `watch` picks a preset rule set; `watch: custom` uses free-text
  `when`/`on` rows whose `if` is an expression (`battery.pct < 20 && battery.discharging`).
- Editor: `rules` is a `rows` field — one dropdown (when/on) + text boxes per key. No hints,
  no validation, no dropdown of looks. A typo in `if` silently evaluates to false.
- petdex: only a link in the field description; the user downloads by hand into
  `~/.config/omarchy/desktop-widgets.pets/<name>/`.

## 1. Looks inventory

**Definition:** a look = one sheet row that has at least one non-blank cell. Frames per look =
trimmed cell count (already computed by the hidden Canvas). So "how many looks" is derived from
the sheet, never declared.

- `Pet.js`: `trimCounts` currently returns `max(1, n)`, which hides empty rows. Change to return
  `{ frames, present }` per row (keep the old array for callers) and add `looks(sheetHeight,
  counts)` → `[{ name, row, frames, present }]`. Row 1/2 (`running-right/left`) and row 7
  (`running`) collapse into **one user-facing look, `running`**, with direction handled by `flip`
  as today; extras on legacy sheets stay `extra1/extra2` (user-nameable later, not now).
- Missing look → explicit fallback chain instead of the silent row 0: `jumping→waving→idle`,
  `waiting→review→idle`, `failed→waiting→idle`, `running→idle`. `rowFor` takes the `present` list.
- **Publish it.** `PetWidget.publish()` adds `looks` to what it hands the service
  (`pets.<name>.looks`), so the editor and other pets can read which looks exist.
- CLI: `desktop-widgets pets --looks [slug]` prints rows/frames per look. Needs pixel access:
  try Pillow, else `dwebp`/`magick`, else geometry-only (rows from height) with a note. Pillow is
  **not** installed here today, so the geometry path must be the working default.
- Editor: the pet card shows "Looks: idle ×6, running ×6, waving ×4 … (7 of 9)" read from the
  live widget; before first render it shows the contract's 9 names.

## 2. Look rules (the user-settable logic)

**Principle:** one engine. Structured rows *compile* into the existing `when`/`on` rules and run
through `Pet.step` unchanged. No second evaluator; the tested expression engine stays the backend
and raw `when`/`on` rows remain for power users.

### Config

`rules` keeps its key; rows gain new kinds. Top-down, first steady match wins (as now).

```jsonc
"watch": "custom",
"rules": [
  // brackets — a % or any number. Omitted bound = open. Ordered rows are the brackets.
  { "kind": "range",   "signal": "battery.pct", "max": 10,             "look": "failed",  "say": "{battery.pct}%!" },
  { "kind": "range",   "signal": "battery.pct", "max": 20,             "look": "waiting", "say": "{battery.pct}%" },
  { "kind": "range",   "signal": "hour",        "min": 23, "max": 6,   "look": "waiting", "say": "zzz" },   // wraps midnight
  // flags — booleans
  { "kind": "flag",    "signal": "battery.charging", "is": true,       "look": "running" },
  // keywords — text signals; words comma-separated; match any|all|none; case-insensitive substring
  { "kind": "keyword", "signal": "custom.window", "words": "youtube, netflix", "match": "any", "look": "review", "say": "slacking?" },
  // another pet — steady follow, or a timed beat when `beat` is set
  { "kind": "pet",     "pet": "jill", "look": "failed", "then": "waving", "beat": 2, "say": "you ok?" },
  { "kind": "pet",     "pet": "jill", "look": "running", "then": "running" },
  // raw rows still work
  { "kind": "when",    "if": "cpu >= 95", "state": "failed", "say": "cpu {cpu}%" }
]
```

Compilation (`Pet.compileRule(row)` → `{kind: when|on, if, state, beat, say}`):

| row kind | compiles to |
|---|---|
| range | `sig >= min && sig < max`; `min > max` on `hour` wraps: `sig >= min \|\| sig < max` |
| flag | `sig == true` / `sig == false` (`!sig`) |
| keyword | `sig ~ 'a' \|\| sig ~ 'b'` (any), `&&` (all), `!(…)` (none) |
| pet | `pets.<pet>.state == '<look>'`; `on` with `beat` if set, else `when` |

Grammar change: one new operator `~` = case-insensitive substring on the string form of the left
side. Nothing else changes in the evaluator.

### Presets become editable templates

Rewrite the six `WATCH` presets as structured rows (range/flag/pet), so `desktop-widgets pet
expand <idx>` (and an editor button "Customise these rules") copies the preset's rows into the
widget and flips `watch` to `custom`. Users see the brackets the preset uses and nudge a number
instead of starting from a blank expression. Presets and custom rules stop being two worlds.

### Text signals worth watching

Today the only text signals are `claude.label`, `battery.status`, `pets.<n>.say/state`. Keyword
rules earn their keep with a user command source: `bin/dw-signals --command key=<shell>` runs
each command (2 s timeout, stdout trimmed, numeric-looking → number) and merges the result as
`custom.<key>`. Config: `"signals": [{ "key": "window", "command": "hyprctl activewindow -j | jq -r .title" }]`.
Still one process per tick per pet.

### Validation and feedback

- `Pet.validateRules(rows, looks, signals)` → `[{ row, message }]`: bad token, unknown signal
  path, look not present on this sheet (warn, names the fallback), unknown pet name, `min ≥ max`.
- Editor shows the messages under the rows; CLI `desktop-widgets pet check [idx]` prints them;
  `write` refuses nothing (warnings only) so a half-typed rule never blocks a save.

### Editor changes (`FieldControl.qml` rows)

- `rowKeys` gains `range/flag/keyword/pet`.
- Per-key control kinds instead of TextField for everything: `look`/`then`/`state` → dropdown of
  the sheet's present looks; `signal` → editable combo seeded from the signal catalogue (dw-signals
  keys + `custom.*` + `pets.*`); `pet` → dropdown of other pets' names from `service.petStates`;
  `is` → toggle; `match` → dropdown. Declared in the registry as `rowFields: { look: { enum:
  "looks" }, … }` so drop-in types get it too.
- Inline "+ range / + keyword / + pet" instead of one generic "+ row" that defaults to `text`.

### Issues found in the current engine (fix while in there)

1. **Lost beats.** In `step`, an `on` rule whose edge rises while another beat is running is
   swallowed: `edges[i]` records `true`, so the next tick sees no rising edge. Queue one pending
   beat per rule (or re-arm by leaving `edges[i]=false` until it can fire).
2. **Swallowed errors.** `try { … } catch { v = false }` hides every typo. Keep the catch (a pet
   must never crash the shell) but surface the message through `validateRules`.
3. **Name collisions.** Two pets on the same sheet folder both publish the same name; the second
   silently overwrites the first. Dedupe at publish (`teto`, `teto_2`) and warn in the editor.
4. **Polling cost.** Each pet spawns its own `dw-signals` (0.15 s CPU sample) every 5 s; three
   pets = three samplers, and custom commands would triple too. Move sampling to one
   service-level Process that publishes `service.signals`; pets just `step` on it. Optional but
   recommended before user commands land.
5. **Type coercion.** Custom command output is text; `>`/`<` on `"12"` vs `12` coerce in JS but
   `==` on `"12.0"` doesn't. The signal source parses numbers once; the compiler emits `Number()`
   semantics for range rows.
6. **Chained lag.** `pets.*` is the previous tick, so a three-pet chain reacts in 3×interval.
   Document; don't fix.
7. **Legacy `extra1/extra2`** rows on 8-row sheets are unusable from a dropdown of "looks" unless
   named; allow `looksNames: {extra1: "sleeping"}` later, not now.

## 3. petdex fetcher

### The contract (probed live 2026-09-10)

- Pet pages: `https://petdex.dev/pets/<slug>` (also `/en/pets/<slug>`); slug = `[a-z0-9-]+`.
- `GET https://petdex.dev/install/<slug>` → **200 `text/x-shellscript`** with two `curl -fsSL -e
  "$PETDEX_REFERER" -o "$PET_DIR/pet.json" '<url>'` / `… spritesheet.webp '<url>'` lines and
  `DISPLAY_NAME='…'`; unknown slug → **404** script (`exit 1`). Asset URLs are
  `https://assets.petdex.dev/curated/<slug>/{petjson-v2.json,sprite-v2.webp}` (curated) or
  `https://assets.petdex.dev/pets/<slug>-<hash>/{petjson.json,sprite.webp}` (community). Assets
  served without the Referer in my test, but send `Referer: https://petdex.dev/` anyway.
- `pet.json` v2: `{ id, displayName, description, spriteVersionNumber, spritesheetPath }`.
  **No licence field.** The page lists CC0 / CC-BY / CC-BY-NC / CC-BY-SA per pet; `/api/pets/<slug>`
  is 401. Licence is best-effort from the page HTML, else `unknown`.
- Sheets: recommended 1536×1872 (8×9). ChatGPT exports are 1536×2288 (11 rows at 208): accept
  height = k×208 for k in 8..11, name rows past 9 `extra…`.

### Rule: parse the script, never run it

The installer is a convenient *manifest*, not something to execute. Regex the two `curl … -o
"$PET_DIR/<file>" '<url>'` lines and `DISPLAY_NAME`; refuse the fetch unless both URLs are
`https://assets.petdex.dev/…`. Everything else in the script is ignored.

### CLI: `desktop-widgets pet fetch <url-or-slug>`

1. Normalise input: bare slug, `petdex.dev/pets/<slug>[/]`, `https://petdex.dev/en/pets/<slug>`,
   `https://petdex.dev/install/<slug>`. Reject any other host, scheme, or path (`/collections/…`)
   with exit 2 and a one-line reason. Slug regex enforced → no path traversal.
2. `GET /install/<slug>` (urllib, 15 s). 404 → exit 3 "not on petdex". Parse; bad shape → exit 5.
3. Download both files to a temp dir under `~/.config/omarchy/desktop-widgets.pets/` (size cap
   25 MB, only `assets.petdex.dev`). Validate: `pet.json` parses with `id`+`spritesheetPath`;
   sheet is WebP/PNG (magic bytes), width = 1536 (8×192), height = k×208, k∈8..11 — header parse
   in pure Python (no Pillow). Invalid → exit 5, temp removed.
4. Move to `…/desktop-widgets.pets/<slug>/{pet.json, spritesheet.webp}`; existing folder → exit 6
   unless `--force`. Add provenance to `pet.json`: `"source": {"site": "petdex", "url":
   "https://petdex.dev/pets/<slug>", "fetchedAt": …, "license": "<label|unknown>"}`.
5. Print `slug`, display name, path, rows/looks; `--json` for the editor. `--add` appends a pet
   widget (`sheet`, `name` = slug, `watch` default) via the existing `add`; `--widget N` points
   an existing pet at it instead.
6. Exit codes: 0 ok · 2 not a petdex URL · 3 not found · 4 network · 5 invalid pet · 6 exists.

Never writes under the plugin checkout (petdex art stays local; licence varies — consistent with
Michael's jill-stingray decision). `desktop-widgets pets` shows `license` and `source` columns.

### Editor: paste + Download

New field type `petdex` on the pet type, rendered above `sheet`: a TextField (placeholder
`https://petdex.dev/pets/<slug>`) + **Download** button + status line. Click → `Process [cli,
"pet", "fetch", url, "--json"]`; button disabled and text "Downloading…" while it runs; on exit 0
the editor `setField("sheet", path)` and `setField("name", slug)` on the selected widget (dirty →
normal save path), status "Boba · 9 looks · CC0"; on failure the CLI's message verbatim. A small
"Installed…" dropdown next to it (from `pets --json`) covers the "I already have it" case. The
shell does no networking of its own; the CLI does it.

### Tests (all offline; `urlopen` monkeypatched)

- URL normalisation table incl. rejects (`https://evil.dev/pets/boba`, `http://petdex.dev/…`,
  `petdex.dev/collections/x`, `../boba`).
- Install-script fixtures: curated, community, 404, script with a non-petdex asset host (reject),
  script missing a line (reject).
- Sheet validation: 1536×1872 ok, 1536×2288 ok with warning, 1000×1000 reject, PNG magic ok,
  oversize reject.
- Existing folder without/with `--force`; provenance written; `--add` produces a valid widget.
- One **manual** live run against `boba` (curated) and one community pet before merge.

## 4. Build order and effort

1. Looks inventory + fallback chain + publish (`Pet.js`, `PetWidget.qml`, `pets --looks`) — ½ evening.
2. Rule compiler + `~` operator + presets as rows + `validateRules` + lost-beat fix — 1 evening.
3. Editor rows: per-key controls, look/pet/signal dropdowns, add-buttons, warnings — 1 evening.
4. petdex fetcher CLI + tests — ½ evening. 5. Editor Download field — ½ evening.
6. Optional: service-level shared sampler + `--command` custom signals — 1 evening.

Each step is its own commit on this branch; 1–3 and 4–5 are independent and could be two
branches if he wants the fetcher sooner.

## 5. Decisions for Michael

1. **Structured rows compiled onto the existing engine** (recommended) vs a separate simple
   rule engine? Compiling keeps one tested path and lets raw expressions coexist.
2. **Shared sampler + custom command signals** now (step 6) or later? Without it, keyword rules
   only have `claude.label`, `battery.status` and other pets' `say` to chew on.
3. **Licence handling on fetch:** store best-effort label and show it, no gate (recommended), or
   refuse non-CC0 downloads unless `--accept-license`?
4. Fetcher **`--add` by default** from the editor (new widget) or only point the selected pet's
   `sheet` at the download? Proposal: editor sets the selected pet's sheet; CLI has both.
