# Desktop Widgets: Layout presets + widget variants — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** (a) whole-screen **presets** — apply a complete `widgets[]` layout in one go and save the current desktop as one; a few shipped, yours under `~/.config/omarchy/desktop-widgets.presets/`; picker in the editor. (b) The first **widget variant**: `stats` gets `orientation: horizontal|vertical` (bars stacked under their labels for a narrow column).

**Architecture:** A preset is a config document (`{ "version": 1, "description": "…", "widgets": [...] }`, JSONC allowed). Shipped ones live in `presets/<name>.jsonc` in the repo; user ones in `$XDG_CONFIG_HOME/omarchy/desktop-widgets.presets/<name>.jsonc` and shadow shipped names. `desktop-widgets preset list [--json] | show <name> | apply <name> | save <name> [--force] | remove <name>`. `apply` validates against the merged registry and writes through the same writer as everything else (`.bak` kept). The editor gets a **Presets ▾** dropdown fed by `preset list --json`; choosing one runs `preset apply` and the panel follows the file. Variants are just registry fields, so the editor form and CLI pick them up unchanged.

**Spec:** `docs/ROADMAP.md` → Backlog #1.

## Status (handoff block — update after every task)

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 CLI `preset` (list/show/apply/save/remove), shipped presets, tests | done | (feat/presets) | 28 python; shipped presets validate in-suite |
| 2 Stats `orientation` variant (registry + QML); live check | done | (feat/presets) | `column` applied live: 4 layers, vertical stats 204×144; Michael's layout saved as user preset `michael` and restored |
| 3 Editor Presets dropdown; docs (README, CHANGELOG, vault); ROADMAP #1 closed; tag v0.5.0 after merge | done | (feat/presets) | IPC ops `preset{name}` / `presets`; tag after Michael's visual check |

**How to resume:** read this file; run `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -p 'test_*.py'`; continue at the first task not done. Code changes need `omarchy restart shell`; validate `manifest.json` first.

## Global Constraints

- One writer: `apply` goes through `write_config`; the editor never touches the file.
- Preset names `^[a-z][a-z0-9-]{0,39}$`. `save` refuses to overwrite a user preset without `--force`; shipped presets are never written to.
- Every shipped preset must validate against the built-in registry (a test loops over `presets/*.jsonc`).

---

### Task 1: CLI + shipped presets
- [x] `presets/minimal.jsonc`, `presets/dashboard.jsonc`, `presets/column.jsonc`.
- [x] `bin/desktop-widgets`: `preset_dirs()`, `load_presets()`, `cmd_preset`.
- [x] Tests in `tests/test_cli.py`: shipped presets validate; list/--json; apply writes + .bak; save/--force; user shadows shipped; bad/unknown names exit 2; remove.

### Task 2: Stats orientation
- [x] Registry field `orientation` on `stats` (enum, default `horizontal`).
- [x] `widgets/StatsWidget.qml`: vertical layout (label + value line, bar beneath, full column width).
- [x] Live: apply `column` preset on envi-laptop (after saving the current layout as `michael`), screenshot, restore.

### Task 3: Editor + docs
- [x] `Editor.qml`: Presets dropdown (list from CLI, apply via CLI, status line).
- [x] README (Presets section, `orientation` in stats), CHANGELOG, vault guide, ROADMAP #1 → done.
