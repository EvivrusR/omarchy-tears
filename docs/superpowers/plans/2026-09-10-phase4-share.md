# Desktop Widgets Phase 4: Make It Shareable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A stranger with Omarchy 4.x installs this with one `omarchy plugin add`, runs one `desktop-widgets install`, and has widgets, the editor, the keybinds and the menu rows — with nothing of Michael's machine baked in.

**Architecture:** Everything machine-specific moves into an idempotent `install` command (symlink, menu rows, keybinds, starter config) with an `uninstall` that reverses it exactly, using marker comments so hand edits around ours survive. First run is covered twice: `install` writes the starter layout if none exists, and the editor offers it when the list is empty. The repo is scrubbed, re-shot, versioned and tagged; the public mirror is the only step needing Michael's inputs.

**Spec:** `docs/ROADMAP.md` → Phase 4 table.

## Status (handoff block — update after every task)

**PHASE 4 COMPLETE 2026-09-10.** Public home `https://github.com/EvivrusR/omarchy-tears` (author EvivrusR). Push habit: `git push origin master && git push github master` (tags likewise) — Forge stays origin, GitHub is the public mirror pushed from the laptop with the deploy key. Open: Michael's yes/no on publishing the Teto wallpaper screenshot (DQ-026).

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 CLI `install` / `uninstall` / `init` with markers, tests | done | aaa289a | 24 python tests; real-machine run reports already for every step |
| 2 First-run: editor "Start with the example layout", service hint | done | 451f9a9 | live: config aside → empty state → init → 5 widgets; editor follows the file |
| 3 Scrub, clean screenshots, README install/compat, CHANGELOG, manifest 0.4.0, tag v0.4.0 | done | 451f9a9 | tag v0.4.0 pushed to Forge |
| 4 Backlog into ROADMAP + vault Tool Ideas; DQ for mirror inputs; vault/board/memory | done | 1ecb29a | |
| 5 GitHub mirror | done | 81c166b | `github` remote via a repo-scoped deploy key; master + v0.4.0 pushed; fresh public clone validates and both suites pass |

**How to resume:** read this file; run both test suites; continue at the first task not done. Code changes need `omarchy restart shell`.

## Global Constraints

- `install`/`uninstall` never touch a line they did not write: all insertions sit between `// desktop-widgets:begin` / `// desktop-widgets:end` (menu JSONC) and `-- desktop-widgets:begin` / `-- desktop-widgets:end` (bindings.lua) markers; `uninstall` removes exactly those blocks. Both are idempotent.
- `install` backs up each file it edits once (`<file>.desktop-widgets.bak`) if no backup exists.
- No personal hostnames, paths, names or colours outside `docs/` history; theme tokens in examples.

---

### Task 1: `install` / `uninstall` / `init`

**Files:** Modify `bin/desktop-widgets`, `tests/test_cli.py`.

**Behaviour:**
- `init [--force]`: copy `desktop-widgets.example.jsonc` to the config path when missing (or with `--force`, keeping `.bak`). Prints the path.
- `install [--no-menu] [--no-keys] [--no-init] [--no-link]`: (1) symlink `~/.local/bin/desktop-widgets` → `bin/desktop-widgets`; (2) menu rows: if `~/.config/omarchy/extensions/omarchy-menu.jsonc` has a `"household"` key put rows under `household.widgets.*`, else create a top-level `widgets` submenu; rows are inserted as a marker block before the final `}` (file created with `{}` if missing); (3) keybinds: append a marker block to `~/.config/hypr/bindings.lua` with SUPER+ALT+W (editor) and SUPER+ALT+A (arrange) unless those chords already appear in the file; (4) `init`. Each step reports `done` / `already` / `skipped`.
- `uninstall [--keep-config]`: remove the symlink (only if it points at us), both marker blocks, and nothing else; config and `.d/` stay unless `--purge`.
- Menu row actions use `$HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets` (the plugin dir is fixed by `omarchy plugin add`), never the symlink.

**Tests** (temp HOME): install creates symlink + blocks + config; running twice changes nothing (file contents identical); uninstall removes exactly the blocks and the link; a bindings file that already has `SUPER + ALT + W` gets only the arrange bind; a menu without `household` gets a top-level `widgets` submenu; `init` refuses to overwrite without `--force`.

- [ ] tests → red → implement → green → commit `"CLI: install/uninstall/init with marker blocks"`.

### Task 2: First run

- `Editor.qml`: when `doc.length === 0`, the form host shows "No widgets yet." and a Button "Start with the example layout" → runs `[cliPath, "init"]` via Process; the service's file watcher then loads it. IPC op `init` for scripted testing.
- `Service.qml`: when no config, the log line adds `run: desktop-widgets init  (or install)`.
- Live: move the live config aside, restart, open the editor → button → widgets appear; restore the real config.
- Commit `"First run: example layout from the editor; hint in the log"`.

### Task 3: Scrub, screenshots, versioning

- `manifest.json` author → `"Michael"` (public handle to be swapped when known), version `0.4.0`; `LICENSE` unchanged (name is fine).
- README: Install section becomes "from Forge (homelab)" + "from GitHub (coming)" placeholder line; add "Requires Omarchy 4.0.3 or newer (Quattro)"; replace `#F99957` in the config example with `"accent"`; remove the `(SUPER+SHIFT+W is Omawrite…)` aside into a note.
- Screenshots: re-shoot `docs/editor.png` and `docs/arrange.png` on an empty workspace (they currently show a terminal session); keep `docs/screenshot.png` (wallpaper is Michael's own art — his call, noted in DQ-026).
- `CHANGELOG.md` with 0.1.0 → 0.4.0 entries; `git tag v0.4.0`; push tag.
- Commit `"Release prep: scrub, clean screenshots, changelog, 0.4.0"`.

### Task 4: Backlog + vault

- ROADMAP: new "Backlog (Michael, 2026-09-10)" section: (1) **layout presets** — whole-screen templates (a preset = a full `widgets[]` layout you can apply, with `desktop-widgets preset list|apply|save`) and **widget variants** — e.g. stats vertical vs horizontal (`orientation` field on stats; variants as registry-level alternatives); (2) an **agent Skill** for extending the plugin — guidelines for building widget types, drop-ins, and forks with an AI agent (contract, test rules, restart rule, what never to do), shipped as `skills/desktop-widgets/SKILL.md` in the repo so any agent can pick it up.
- Vault `03 Resources/Tool Ideas.md`: both items parked with a link back. DQ-026: mirror inputs (handle, repo name, PAT, wallpaper screenshot ok?). Vault guide, board, memory, journal, this plan.
- Commit `"Roadmap backlog: layout presets + widget variants, agent Skill"`; push.
