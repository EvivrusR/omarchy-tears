# Changelog

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
