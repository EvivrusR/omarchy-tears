# Desktop widgets — formalisation and editor roadmap

Written 2026-09-09 after the first cut shipped (clock, stats, command, agents).
Goal: turn a working plugin into something a human can configure without
reading QML — first through a formal config file and CLI, then a native
editor, then a way to create new widget kinds without touching this repo.

## The one idea everything hangs on: a widget registry

Today each widget type reads its own keys out of the JSON entry with ad-hoc
defaults inside the QML. That works but nothing else can know what a
`stats` widget accepts. The fix is one machine-readable description per type,
`widgets/registry.json`, and three consumers of it:

```json
{
  "clock": {
    "displayName": "Clock",
    "description": "Time with the date beneath.",
    "fields": [
      { "key": "timeFormat", "type": "string",  "label": "Time format", "default": "HH:mm" },
      { "key": "dateFormat", "type": "string",  "label": "Date format", "default": "dddd d MMMM", "description": "Empty hides the date" }
    ]
  },
  "stats": {
    "displayName": "System stats",
    "fields": [
      { "key": "show",        "type": "multi-enum", "label": "Rows", "options": ["cpu", "mem", "disk", "battery"], "default": ["cpu", "mem", "disk", "battery"] },
      { "key": "intervalSec", "type": "integer",    "label": "Refresh (s)", "default": 3, "min": 1, "max": 600 },
      { "key": "diskPath",    "type": "path",       "label": "Disk to watch", "default": "/" }
    ]
  }
}
```

Common fields (`corner`, `x`, `y`, `scale`, `backdrop`, `color`, `mutedColor`,
`outline`, `halo`, `align`, `screen`, `enabled`) live once under a `"*"` key.
Field types are the same set Omarchy's own bar-widget settings use
(`string`, `integer`, `number`, `boolean`, `enum`, `multi-enum`, `path`,
`color`, `command`), so the shell's form components can render them.

| Consumer | What it does with the registry |
|---|---|
| `Service.qml` / `WidgetCard` | Fills defaults, so widget QML stops hand-rolling `config.x \|\| 48`. Unknown keys are logged, not fatal. |
| `bin/desktop-widgets` CLI | Validates a config, prints per-type help, drives `add`/`set` with type checks. |
| Editor panel (phase 2) | Generates the form for each widget type. Adding a field to the registry adds it to the UI. |

## Phase 1 — formal config file and CLI (no UI yet)

**File.** Stays `~/.config/omarchy/desktop-widgets.json`, one file, hot-reloaded.
Two conveniences for humans:

- Comments and trailing commas are accepted (JSONC), stripped before parsing,
  the same way Omarchy's menu file works. `desktop-widgets.example.json`
  becomes a commented template you copy and prune.
- Every write the CLI or the editor makes goes through one writer that keeps
  `desktop-widgets.json.bak` (previous version) so a bad edit is one copy away
  from undone. Hand edits are still fine.

Why not a `.properties`/INI file: widgets are a list of objects with nested
values (`show: [...]`), which INI cannot express without inventing a syntax.
JSONC gives comments while staying what `shell.json` already is.

**CLI.** `bin/desktop-widgets`, Python 3 standard library only (Omarchy ships
Python; node is not guaranteed). Installed onto PATH by a one-line symlink the
README documents (`~/.local/bin/desktop-widgets`).

```
desktop-widgets list                       # index, type, corner, enabled, one-line summary
desktop-widgets add clock --corner top-right --set timeFormat=HH:mm
desktop-widgets set 2 intervalSec=5 color=accent
desktop-widgets move 2 --corner bottom-left --x 40 --y 40
desktop-widgets enable 2 | disable 2 | remove 2 | duplicate 2
desktop-widgets types                      # registry-driven help: fields, types, defaults
desktop-widgets validate [file]            # exit 1 with line-level messages
desktop-widgets edit                       # $EDITOR on the file, validate on save, keep .bak
desktop-widgets status                     # plugin enabled? layers on screen? last log lines
```

`validate` is also wired into `omarchy plugin validate`-style CI in the repo
(`tests/`), and `Service.qml` logs the same messages, so the file's rules live
in one place: the registry.

**Omarchy integration.** Three entries in the Household submenu
(`~/.config/omarchy/extensions/omarchy-menu.jsonc`): *Edit widgets*
(`desktop-widgets edit` in a terminal), *Toggle widgets* (`omarchy plugin
enable|disable`), *Reload shell*. Optional keybind for the first.

Effort: about an evening. No new runtime risk; the plugin's behaviour with a
valid file is unchanged.

## Phase 2 — native editor panel

A second entry point in the same plugin manifest (`kinds: ["service", "panel"]`),
summoned like every other Omarchy panel:

```
omarchy-shell shell toggle homelab.desktop-widgets '{}'
```

bound to a keybind and a Household menu row. It is a Quickshell window built
from the shell's own `qs.Ui` components (TextField, NumberField, Dropdown,
MultiSelect, Toggle, ButtonGroup, ConfirmDialog), so it looks like the
Settings and Agents panels rather than a foreign app.

```
┌ Desktop widgets ───────────────────────────────────────────────┐
│ Widgets                     │ Clock · top-right                 │
│ ● Clock        top-right    │ Corner   [TL] [TR] [BL] [BR]      │
│ ● System stats bottom-left  │ Offset   x [ 48 ]  y [ 64 ]       │
│ ● Uptime       bottom-right │ Scale    [ 1.0 ]  Backdrop [0.0]  │
│ ● Claude       top-left     │ Colour   [#F99957 ▾] Muted [...]  │
│                             │ Outline  [#000000] Halo [0.7]     │
│ [+ Add ▾] [Duplicate] [✕]   │ ── Clock ─────────────────────    │
│                             │ Time format [HH:mm]               │
│                             │ Date format [dddd d MMMM]         │
│ Apply on change  (●)        │                     [Revert] [Save]│
└────────────────────────────────────────────────────────────────┘
```

- The left list is the `widgets[]` array: reorder with drag or `j`/`k`, enable
  toggle on the dot, add opens a type picker fed by the registry.
- The right form is generated from the registry: common fields first, then the
  type's fields, grouped under the type's display name.
- **Apply on change** writes the file on every edit; because the service
  hot-reloads, the desktop updates as you type. Off, edits stay in the panel
  until Save. Revert reloads `.bak`.
- Writes go through the same writer as the CLI (one code path, one backup).
- The panel is display-and-write only. It never talks to widget instances,
  so a broken widget cannot break the editor and vice versa.

Risks to check before building: a third-party `panel` receives the scoped
shell facade, which is enough here (we only read and write our own file);
and panel code under a subdirectory needs `omarchy restart shell` to refresh
during development, as noted in the README.

Effort: two to three evenings, most of it the form generator, which phase 3
reuses.

## Phase 3 — placing by hand, and creating new parts

**Edit mode on the desktop — armed, never always-on.** (Michael, 2026-09-09:
"it would be annoying if it was always on and you accidentally dragged it.")

- Default state is *disarmed*: widget windows keep an empty input region
  (`mask: Region {}`), so a drag cannot even begin and the desktop's own
  double-click keeps working.
- Arming comes from three places, all explicit: an **Arrange on desktop**
  button in the editor panel, the keybind (SUPER+ALT+W held, or a second bind),
  and `desktop-widgets arrange` / the IPC `call {"op":"arrange","value":true}`.
- While armed every widget draws a dashed frame in `Color.accent`, the panel
  (if open) shrinks to a strip at the bottom, and dragging a widget moves it
  live; on release it snaps to the nearest corner and writes `corner`, `x`,
  `y` through the same `desktop-widgets write` path as everything else.
- It disarms on Esc, on Save, when the editor closes, and after 60 s idle,
  and the frames vanish with it.
- **Optional bar companion** (`kinds` gains `bar-widget`, `Companion.qml`):
  a bar icon that is hidden while disarmed and shows 󰆾 while armed; click
  disarms, right-click opens the editor. It reads arming state from the
  plugin's own service (bar widgets can look up their own service through
  the shell facade). It ships disabled in the bar layout; people add it with
  `omarchy plugin enable homelab.desktop-widgets right` if they want the
  visible reminder. It is a convenience, not the gate — the gate is the
  arming above.

**New parts without QML.** Two routes, both discovered at load so the repo
never needs a change:

1. A `template` widget type: rows described in config, values pulled from a
   command that prints JSON.
   ```json
   { "type": "template", "command": "curator-cli stats --json", "intervalSec": 300,
     "rows": [
       { "kind": "heading", "text": "CURATOR" },
       { "kind": "text",    "text": "{rated} rated · {loved} loved" },
       { "kind": "bar",     "label": "loved", "value": "{loved_rate}" }
     ] }
   ```
   Covers most readouts (render queue, Curator, WaniKani, weather) with zero code.
2. Drop-in QML types in `~/.config/omarchy/desktop-widgets.d/<Name>/`
   containing `Widget.qml` (extends `WidgetCard`) and `fields.json` (a registry
   fragment). The service merges these into the registry, so the CLI and the
   editor know about them immediately. This is how someone shares a widget
   without forking the plugin.

Effort: template type one evening; drop-in types half a day including docs.


## Phase 4 — make it something other people can grab

The plugin already has the shape Omarchy wants for sharing: a git repo with a
`manifest.json` at its root, installed with one command. What remains is the
distance between "works on envi-laptop" and "works on a stranger's laptop".

| Item | Why | Work |
|---|---|---|
| Public mirror | Forge is reachable only over Tailscale. | GitHub repo + Forgejo push mirror (same pattern as the LoRA Forge release plan); README install line points at GitHub. |
| One-line install | `omarchy plugin add https://github.com/<user>/omarchy-desktop-widgets.git --enable` | Already true. Verify on a fresh Omarchy VM or a second user account. |
| First run | An empty config is a blank desktop and a silent log line. | On first enable with no config, the service writes the starter layout (clock + stats + agents, theme-token colours) and logs where it put it; the editor shows "Start with the example layout" when the list is empty. |
| `desktop-widgets install` / `uninstall` | Today the CLI symlink, menu rows and keybind are three hand edits. | One idempotent command that links `~/.local/bin/desktop-widgets`, inserts the Household menu rows (or a top-level `widgets` row when there is no Household submenu), and appends the keybind to `bindings.lua` with a marker comment; `uninstall` reverses all three. |
| Registry-driven defaults everywhere | Michael's `#F99957` and `$HOME/.config/omarchy/plugins/homelab.desktop-widgets` are baked into docs and menu rows. | Docs use theme tokens; menu rows resolve the plugin dir from the manifest id; the install command writes real paths. |
| Scrub | `manifest.json` author, screenshots that show a terminal session, the Forge URL. | Author → a public handle; re-shoot screenshots on an empty workspace with a neutral wallpaper; README install URL → GitHub. `git log` is fine (no secrets; session trailers are harmless). |
| Versioning | People update with `omarchy plugin update`, which shows a diff. | Tag `v0.3.0` after Phase 3, keep `CHANGELOG.md`, bump `manifest.json` version per release. |
| Compatibility note | The plugin contract is Omarchy 4.x (Quattro). | State "Omarchy 4.0.3+" in README; the `agents` widget needs the shell's own usage collector, present on every 4.x. |
| Listing | Discoverability. | Ask on the Omarchy manual's Shell Plugins page / community list once public. |

Order: scrub + install command + first-run first (they make the public repo
honest), then the mirror and tag. About an evening on top of Phase 3.

## Backlog (Michael, 2026-09-10)

1. **Layout presets and widget variants.** **DONE 2026-09-10** (presets + stats `orientation`; plan `docs/superpowers/plans/2026-09-10-presets-and-variants.md`; clock/agents `layout` variants still open). Two related ideas: (a) *whole-screen
   templates* — a preset is a complete `widgets[]` layout (e.g. "minimal
   clock", "ops dashboard", "streamer") that you can apply in one go and save
   your current desktop as; `desktop-widgets preset list|apply <name>|save
   <name>` plus a preset picker in the editor, presets stored under
   `~/.config/omarchy/desktop-widgets.presets/` and a few shipped in
   `presets/`; (b) *single-widget swaps* — the same widget in another shape,
   the first being **stats vertical instead of horizontal** (bars stacked
   with labels above, for a narrow column). Modelling: variants as a registry
   field on the type (`orientation: horizontal|vertical` for stats;
   `layout: stacked|inline` for clock/agents) so the editor shows them as a
   dropdown and a preset can pin them. Estimate: presets one evening,
   variants half an evening per widget.

2. **An agent Skill for extending this tool.** Most of this plugin was built
   by an AI agent working from the contracts in this repo. Package that as a
   Skill so anyone can do the same — enhance the plugin, write a drop-in, or
   fork it for their own desktop — with guardrails baked in. Shipped in the
   repo as `skills/desktop-widgets/SKILL.md` (Claude Code / Hermes format,
   plain markdown so any agent can read it), covering: the widget contract
   (`WidgetCard`, `WidgetText`, injected `config`, colour/outline/scale
   properties), the registry (add a field → CLI, validator and editor follow),
   the one writer rule (`desktop-widgets write`), the test rules (pure logic
   in `.js`/Python with shared fixtures; both suites must stay green), the
   restart rule (`omarchy restart shell` after code changes; validate the
   manifest first — we broke it once), the drop-in path for anything that
   does not belong upstream, what never to do (write the config directly,
   touch `/usr/share/omarchy`, make arrange mode always-on, mix a bar-widget
   kind into `plugins[]` expectations), and a checklist for a PR. Estimate:
   an evening, mostly distilling the plans under `docs/superpowers/`.

3. **Menu home: Style, not Household.** (Michael, 2026-09-10.) **DONE 2026-09-10** (`feat/style-menu`). The *Desktop
   widgets* submenu belongs under Omarchy's own **Style** menu (which exists
   on every install) rather than Michael's Household submenu. Change
   `desktop-widgets install` to insert `style.widgets.*` rows by default
   (Style is a default submenu, so no "household exists?" branch), move
   Michael's rows on envi-laptop, update README/vault. Half an hour.

4. **Shape widgets for contrast and form.** (Michael, 2026-09-10.) **DONE 2026-09-10** — plan `docs/superpowers/plans/2026-09-10-shape-widgets-and-z.md`. Today each
   widget can only draw a card behind *itself* (`backdrop` alpha). Add a
   `shape` widget type that is pure form: `kind` (`rect`, `circle`, `line`,
   `pill`), `width`/`height`, `fill` (theme token or colour) + `alpha`,
   `border`/`borderAlpha`/`borderWidth`, `radius`, optional soft `shadow`,
   so people can lay a translucent panel behind a group of widgets, a divider
   line, or an accent block. Needs one decision on **stacking**: widgets are
   separate layer-shell windows on the same layer, so "behind" must be made
   explicit — add a common `z` key (lower first), honoured by creating windows
   in `z` order (and re-creating on change), and shown in the editor list.
   Shapes are content-free so they must never take input (same empty region
   as everything else). Estimate: an evening including the editor's colour
   swatches for fill/border and a `presets`-friendly default of a 40%
   `background`-token panel.

## Round 2 (2026-09-10, Michael's brief after presets)

Spec `docs/superpowers/specs/2026-09-10-round2-design.md`. Built the same day on stacked branches `feat/grid-snap` → `feat/monitor-family` → `feat/weather` → `feat/dock`: grid snapping; battery / sysinfo / monitor widgets (+ `ops` preset); weather widget + full-screen ASCII weather effect with back/front/custom placement; launcher dock (wallpaper-layer, first input-taking widget). Each has a plan with a status table under `docs/superpowers/plans/`.

## Backlog additions (2026-09-10, after v0.5.0)

5. **Pet widget** — **DONE 2026-09-10** (`feat/pets`): Hermes/petdex sheet contract, watch presets claude/battery/agents/cpu/mem/gpu + custom rules, multiple pets, variable size. Spec `docs/superpowers/specs/2026-09-10-pet-widget-design.md`, plan `docs/superpowers/plans/2026-09-10-pets.md`. Later: roam, petdex fetcher.

6. **Linked + layered pets** (Michael, 2026-09-10) — layers (body + outfit/prop sheets in lock-step via `currentFrame` + `sourceClipRect`, static PNG props, wardrobe swap-out) and links (pets publish `pets.<name>.state` for each other's rules). Scoped in `docs/superpowers/specs/2026-09-10-linked-and-layered-pets-design.md`; content (transparent-body outfit art) is the real blocker — props first.

## Order and what needs Michael's word

1. Phase 1 registry + CLI + JSONC — recommended to start now; no decisions needed beyond "go".
2. Phase 2 editor — decide: native shell panel (recommended, matches Omarchy) versus a small web page. The plan above assumes native.
3. Phase 3 — decide whether drag-to-place (armed edit mode, optional bar companion) matters more than template widgets; both are independent of each other.
4. Phase 4 — **in progress 2026-09-10**: install/uninstall/init, first run, scrub, screenshots, changelog and tag v0.4.0 are done; the GitHub mirror waits on the public handle, repo name and a token (DQ-026).
5. Backlog above — pick an order when Phase 4 closes.

Tracked in the vault Decision Queue as DQ-024 (Phases 1–2 answered and shipped 2026-09-09; Phase 3 priority and Phase 4 go still open).
