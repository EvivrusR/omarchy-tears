# Changelog

## Unreleased
- **Launcher dock**: `dock` widget (app icons from desktop entries, click to launch; hover zoom/tooltips or labels; bar-wide `iconStyle` themed / mono / original), `desktop-widgets apps`, editor app picker; registry types may declare `input: true` and per-type `defaults` for common keys; `top-center` / `bottom-center` corners.
- **Weather**: `weather` widget (Open-Meteo, typed place, no location detection, cached, attribution) with an optional full-screen animated ASCII **weather effect** (`effect`, `effectPlacement` back/front/custom, opacity × preset, density, fps).
- Stacking fix: a z change or a new window that belongs behind an old one now recreates the windows in order (the shell otherwise appends new windows on top).
- Registry fields may declare `showWhen: {key: value}`; the editor's type header now lands correctly for types with `omitCommon`.
- **Monitor family**: `battery` (glyph styles, time to empty/full), `sysinfo` (fastfetch-style block with logo or custom ASCII art), `monitor` (cpu/mem/gpu/temp/load/net rows with filled sparklines, adjustable poll and window); shared sampler `bin/dw-sample`, `bin/dw-sysinfo`; `ops` preset.
- **Grid snapping** in arrange mode: `desktop-widgets grid on|off|<px>`, Grid button in the editor, `G` / `[` / `]` while armed; top-level config settings (`grid`) are preserved by every writer.
- **Presets**: `desktop-widgets preset list|show|apply|save|remove`; three shipped (`minimal`, `dashboard`, `column`), yours under `~/.config/omarchy/desktop-widgets.presets/`; **Presets…** dropdown in the editor.
- **Stats `orientation`**: `vertical` stacks each bar under its label (first widget variant).
- **Shape widgets**: `shape` type (rect / pill / circle / line; fill + alpha, border, radius, soft shadow) for translucent panels and dividers behind other widgets.
- **`z` stacking** on every widget: windows are created in ascending `z`, so "behind" is explicit; the editor list shows `z` when it is not 0, and `desktop-widgets list` prefixes the summary with `z=n`.
- Registry types may declare `omitCommon` to drop common keys they do not use (the editor form and `types` help follow; stray keys warn).
- Menu rows now install under Omarchy's own **Style** submenu by default (it exists on every install); `desktop-widgets install --menu-parent <id>` for anywhere else. Existing hand-placed `*.widgets` rows are left alone.

## 0.4.0 — 2026-09-10
- Public home: https://github.com/EvivrusR/omarchy-tears
- `desktop-widgets install` / `uninstall` / `init`: one-command setup (CLI link, menu rows, keybinds, starter layout) with marker blocks that uninstall removes exactly.
- Editor: first-run screen with "Start with the example layout"; follows the file when it changes underneath.
- Drop-in widget types (`~/.config/omarchy/desktop-widgets.d/<name>/type.json` + `Widget.qml`), `desktop-widgets new`, merged registry via `registry --json`.
- Template widget type: rows from a command's JSON with `{placeholders}` and filters; rows editor in the panel.
- Arrange mode: armed drag-to-place with live preview, snap to corner, optional bar companion.
- Scrubbed for sharing; requires Omarchy 4.0.3+.

## 0.3.0 — 2026-09-09
- Arrange mode (Phase 3a), template widgets (3b) first cut, bar companion.

## 0.2.0 — 2026-09-09
- Native editor panel: list, registry-generated form, apply-on-change, discard confirm, IPC `call` ops.
- Registry, JSONC config, `desktop-widgets` CLI (list/types/validate/add/set/move/enable/disable/remove/duplicate/edit/status/toggle/write).

## 0.1.0 — 2026-09-09
- Clock, stats, command, agents widgets on the wallpaper layer; outlined theme text; per-widget colour tokens.
