# Desktop Widgets: Shape widgets + `z` stacking — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `shape` widget type that is pure form — a translucent panel, divider line, pill or circle laid *behind* a group of widgets — plus a common `z` key so "behind" is explicit and shown in the editor.

**Architecture:** Widgets are separate layer-shell windows on the same layer; the compositor stacks them in creation order (verified with `hyprctl layers`: listed bottom-first in config order). So `Service.qml` orders `placements` by `(z, index)` (`Registry.stackOrder`) and, because every config reload rebuilds the windows, a `z` change re-stacks on save. `shape` extends `WidgetCard` with `pad: 0` and no text; its fields come from the registry like every other type. A type may declare `omitCommon` (list of common keys it does not use) so the editor and `types` help stay clean and stray keys warn.

**Spec:** `docs/ROADMAP.md` → Backlog #4.

## Status (handoff block — update after every task)

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 Registry: `z` common field, `shape` type, `omitCommon`; `stackOrder`; JS + Python + fixtures | todo | | |
| 2 `ShapeWidget.qml`, `WidgetCard.pad` overridable, Service loader + z-ordered placements; live check | todo | | |
| 3 Editor list shows z; CLI `list` summary for shape + z; example layout; docs (README, CHANGELOG, vault); ROADMAP #4 closed | todo | | |

**How to resume:** read this file; run `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -p 'test_*.py'`; continue at the first task not done. Code changes need `omarchy restart shell`; validate `manifest.json` first. Check stacking with `hyprctl layers | grep -A12 'level 1'` (bottom-first).

## Global Constraints

- Shapes never take input (same empty region as everything else). No new dependency: `MultiEffect` (already used by `WidgetText`) gives the optional shadow.
- `z` default 0, range −100..100; equal `z` keeps list order (today's behaviour), so existing layouts are unchanged.
- One writer, both suites green, both summary lines read before every commit.

---

### Task 1: Registry + engines
- [ ] `widgets/registry.json`: common `z`; `shape` type (`kind` rect|pill|circle|line, `width`, `height`, `fill`, `alpha`, `border`, `borderWidth`, `borderAlpha`, `radius`, `shadow`) with `omitCommon`.
- [ ] `widgets/Registry.js` + `widgets/EditorModel.js` + `bin/desktop-widgets`: `fieldsFor` honours `omitCommon`; `Registry.stackOrder(widgets)`.
- [ ] Tests: `tests/registry.test.js` (omitCommon, stackOrder), fixture `tests/fixtures/validate/shape.json` (bad kind, stray `color` warns, z out of range).

### Task 2: Shell
- [ ] `widgets/WidgetCard.qml`: `pad` becomes a plain property.
- [ ] `widgets/ShapeWidget.qml`.
- [ ] `Service.qml`: `placements` ordered by `stackOrder`; Loader case `shape`.
- [ ] Live: add a panel behind the stats/agents column on envi-laptop with `z: -1`, restart shell, `hyprctl layers` shows it first; screenshot.

### Task 3: Editor, CLI, docs
- [ ] `Editor.qml` list row: `z ±n` chip when z ≠ 0.
- [ ] CLI `summarize` for shape; `list` shows `z` when non-zero.
- [ ] `desktop-widgets.example.jsonc`: a 40% `background` panel behind the stats block, `z: -1`.
- [ ] README (Shape section + z under common keys), CHANGELOG, vault guide, ROADMAP backlog #4 → done.
