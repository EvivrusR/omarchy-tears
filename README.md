# Omarchy desktop widgets

Theme-aware widgets drawn on the wallpaper layer of Omarchy 4.x (Quattro):
a clock, system stats bars, and the output of any shell command. They sit
above the wallpaper and below every window, recolour with `omarchy theme set`,
and never touch Omarchy's own files.

![clock top-right, stats bottom-left, command bottom-right](docs/screenshot.png)

## Install

Requires Omarchy 4.0.3 or newer (the Quattro shell). Three commands:
(Source of record: `https://github.com/EvivrusR/omarchy-tears`; the plugin id stays `homelab.desktop-widgets`.)

```bash
omarchy plugin add https://github.com/EvivrusR/omarchy-tears.git --yes
omarchy plugin enable homelab.desktop-widgets
~/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets install
```

`install` links the CLI into `~/.local/bin`, adds a *Desktop widgets* submenu to
the Omarchy menu, binds SUPER+ALT+W (editor) and SUPER+ALT+A (arrange), and
writes the example layout if you have no config. Every edit sits between
`desktop-widgets:begin/end` markers and `desktop-widgets uninstall` removes
exactly those again. Then `hyprctl reload` and press SUPER+ALT+W.

## Turn off, roll back, update

```bash
omarchy plugin disable homelab.desktop-widgets   # widgets vanish immediately
omarchy plugin enable  homelab.desktop-widgets   # and come back
omarchy plugin remove  homelab.desktop-widgets --yes
omarchy plugin update  homelab.desktop-widgets   # fast-forward pull with a diff preview
```

Disable and enable edit one entry in `plugins[]` of `~/.config/omarchy/shell.json`.
Nothing under `/usr/share/omarchy` is changed, so `omarchy update` and this plugin
cannot step on each other. If the plugin ever fails to compile, the shell logs
`service plugin load failed for homelab.desktop-widgets` and carries on without it.

## Configure

Edit `~/.config/omarchy/desktop-widgets.json`. It hot-reloads on save; a
malformed edit keeps the last good layout on screen and logs the parse error.
Comments (`//`, `/* */`) and trailing commas are allowed. Entries with invalid
values are skipped and the reason is logged (`journalctl --user _COMM=quickshell | grep desktop-widgets`);
unknown keys only warn. Every key's type, default and range comes from
`widgets/registry.json`.

```json
{
  "version": 1,
  "widgets": [
    { "type": "clock",   "corner": "top-right",    "x": 48, "y": 64,
      "timeFormat": "HH:mm", "dateFormat": "dddd d MMMM", "color": "accent" },
    { "type": "stats",   "corner": "bottom-left",  "x": 48, "y": 48,
      "show": ["cpu", "mem", "disk", "battery"], "intervalSec": 3, "backdrop": 0.35 },
    { "type": "command", "corner": "bottom-right", "x": 48, "y": 48,
      "title": "UPTIME", "command": "uptime -p", "intervalSec": 60, "maxLines": 4 },
    { "type": "agents", "corner": "top-left", "x": 48, "y": 64, "agent": "claude" }
  ]
}
```

Keys every widget accepts:

| key | default | meaning |
|---|---|---|
| `type` | required | `clock`, `stats`, `command`, `agents`, `template`, or any drop-in |
| `corner` | `top-right` | `top-left`, `top-right`, `bottom-left`, `bottom-right` |
| `x`, `y` | 48 | offset from that corner, px |
| `enabled` | true | `false` hides the widget without deleting it |
| `screen` | all | output name (`hyprctl monitors`) to draw on |
| `scale` | 1 | font and spacing multiplier |
| `backdrop` | 0 | alpha of a rounded themed card behind the widget |
| `color` | `foreground` | text colour: theme token (`foreground`, `background`, `accent`, `muted`, `urgent`) or any colour string |
| `mutedColor` | `muted` | secondary text colour, same forms |
| `outline` | `#000000` | crisp outline around all text, theme token or colour; `""` disables outline and halo |
| `halo` | 0.7 | strength (0..1) of the soft dark halo behind text, uses the outline colour |
| `align` | by corner | `left` or `right` text alignment |

Per type:

- **clock**: `timeFormat` (`HH:mm`), `dateFormat` (`dddd d MMMM`, empty string hides it). Qt date format strings.
- **stats**: `show` (any of `cpu`, `mem`, `disk`, `battery`), `intervalSec` (3), `diskPath` (`/`).
  Battery only appears when a `/sys/class/power_supply/BAT*` exists.
- **command**: `command` (run with `bash -lc`), `intervalSec` (60), `timeoutSec` (10), `maxLines` (8),
  `maxWidth` (420 px), `title`. A non-zero exit keeps the last good output and shows a red `!` by the title.
- **agents**: the current AI-agent session, same data as the shell's Agents bar widget. `agent` (`claude`;
  `codex` also works), `showWeekly` (false), `timeFormat` (`HH:mm`), `title`. Shows percent of the rolling
  session used, a meter, and `ends in 3h 31m · 23:59`. Display-only: it watches
  `~/.local/state/omarchy/agents/usage/<agent>.json`, which the bar widget refreshes every 15 minutes.
  If you disable the bar widget, set `refreshIntervalSec` (e.g. 900) so this widget triggers
  `omarchy-agent-usage-update --limits-only` itself.

## Editor panel

A native Omarchy panel edits the same file: list on the left, a form generated
from `widgets/registry.json` on the right, the desktop updating as you edit.

![editor panel](docs/editor.png)

```bash
desktop-widgets editor                                   # toggle it
omarchy-shell shell toggle homelab.desktop-widgets '{}'  # what that runs
```

- **Add** picks a type; **Duplicate**, **Remove**, **↑/↓** act on the selected row; the dot toggles `enabled`.
- **Apply on change** (default on) saves after every edit through `desktop-widgets write`, so an invalid value is refused with its reason in the footer and the file is left alone. Off, edits wait for **Save**; **Revert** reloads the file; Esc asks before discarding.
- Values equal to the registry default are dropped from the file, so it stays minimal.
- Keys: `j`/`k` select, Tab moves through fields, Ctrl+S saves, Esc closes (or leaves a text field).
- If the file has comments the panel starts with apply-on-change off and warns that saving from it drops them.
- Scriptable: `omarchy-shell shell call homelab.desktop-widgets call '{"op":"add","type":"clock"}'`
  (ops: `select{index}`, `add{type}`, `remove`, `duplicate`, `move{dir}`, `set{key,value}`, `toggleEnabled{index}`, `save`, `revert`, `applyOnChange{value}`, `state`).

Menu: *Desktop widgets* › **Editor** (under Household if you have that submenu). `desktop-widgets install` adds the SUPER+ALT+W / SUPER+ALT+A binds; SUPER+SHIFT+W is Omawrite on a stock Omarchy, which is why ALT.

## Arrange mode (drag-to-place)

Off by default and impossible to trigger by accident: widget windows have an
empty input region, so nothing on the desktop is draggable until you arm it.

![arrange mode](docs/arrange.png)

Arm it from the editor's **Arrange on desktop** button, **SUPER+ALT+A**,
the menu's *Desktop widgets › Arrange* row, or `desktop-widgets arrange on`. Every
widget gets a dashed frame; drag one and it follows live, snaps to the nearest
corner on release, and saves `corner`/`x`/`y` through `desktop-widgets write`.
Esc or Enter finishes; it also disarms itself after a minute idle and never
survives a shell restart.

Scriptable (same path as the mouse): `omarchy-shell desktop-widgets drag <index> <dx> <dy>`,
`omarchy-shell desktop-widgets arrange on|off|toggle`, `omarchy-shell desktop-widgets state`.

**Optional bar companion.** The plugin also ships a bar widget that shows 󰆾
only while arrange mode is armed (click finishes, right-click opens the
editor). Add it by putting `{ "id": "homelab.desktop-widgets" }` into a bar
section of `~/.config/omarchy/shell.json` (hot-reloads); leave it out if you
don't want it. Omarchy 4.0.3's `omarchy plugin enable … right` / `omarchy bar put`
do not place it because the plugin is already listed under `plugins[]` for its
service — a known quirk of mixed-kind plugins.

## Template widgets (no code)

Any command that prints JSON becomes a widget: describe rows in the config and
use `{placeholders}` from the output.

![template widget](docs/template.png)

```jsonc
{ "type": "template", "corner": "bottom-right", "intervalSec": 10,
  "command": "python3 -c 'import json,os; l=os.getloadavg(); print(json.dumps({\"l1\":l[0],\"l5\":l[1],\"cpus\":os.cpu_count()}))'",
  "rows": [
    { "kind": "heading", "text": "LOAD" },
    { "kind": "kv",  "label": "1 / 5 min", "value": "{l1|fixed:2} / {l5|fixed:2}" },
    { "kind": "bar", "label": "1m", "value": "{l1}", "text": "{l1|fixed:2}", "max": "{cpus}", "warnAt": 0.9 }
  ] }
```

| kind | keys |
|---|---|
| `heading` | `text` |
| `text` | `text` |
| `kv` | `label`, `value`, `labelWidth` |
| `bar` | `label`, `value` (number for the meter), `text` (display, defaults to value), `min` (0), `max` (100), `warnAt` (0.9 → red), `suffix`, `labelWidth` |
| `spacer` | `height` (px) |

Placeholders: `{path}` with dotted paths and indices (`{disks.0.pct}`), filters
`{v|fixed:2}` `{v|round}` `{v|int}` `{v|pct}` `{v|upper}` `{v|lower}` `{v|human}`
(1234567 → 1.2M) `{v|secs}` (3725 → 1h 02m) `{v|default:none}`. Missing values
show `—`; literal braces are `{{` `}}`. Output that isn't a JSON object is still
available as `{output}` and `{lines.N}`. A failing command keeps the last values
and marks the heading with a red `!`.

The editor renders template rows as an inline list (kind dropdown, the kind's
keys, reorder, remove, `+ row`).

## Drop-in widget types (your own QML, no fork)

Add a widget *type* by dropping a folder under `~/.config/omarchy/desktop-widgets.d/<name>/`:

```
desktop-widgets.d/hello/
├── type.json     # its fields, registry-style (common keys are added for you)
└── Widget.qml    # the same contract the built-in widgets use
```

```bash
desktop-widgets new hello          # scaffolds both files from examples/drop-in/hello
desktop-widgets types              # lists it as "Hello (drop-in)"; reports broken drop-ins
desktop-widgets add hello --set name=sir
```

`Widget.qml` is a `WidgetCard { ... }` like `widgets/ClockWidget.qml`. It gets the
plugin's kit through a relative import that is identical on every install:

```qml
import "../../plugins/homelab.desktop-widgets/widgets"   // WidgetCard, WidgetText, …
WidgetCard {
  id: root
  readonly property string name: String(config.name || "world")   // your type.json fields, defaults applied
  Column { WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: "hello, " + root.name; color: root.textColor } }
}
```

`type.json`:

```json
{ "displayName": "Hello", "description": "A greeting.",
  "fields": [ { "key": "name", "type": "string", "label": "Name", "default": "world" } ] }
```

Field types are the registry's (`string`, `integer`, `number`, `boolean`, `enum`, `multi-enum`,
`color`, `path`, `command`, `rows`), so the CLI validates your keys and the editor
generates a form for them automatically. Names must match `^[a-z][a-z0-9-]{0,39}$` and
cannot shadow a built-in type. A broken drop-in is reported and skipped, never fatal.

A **new** drop-in shows up as soon as you add a widget of that type; **editing** an
existing drop-in's QML needs `omarchy restart shell` (the shell caches compiled QML).
`omarchy-shell desktop-widgets rescan` re-reads the registry by hand.

## CLI

`bin/desktop-widgets` (Python 3, no dependencies) edits and checks the config for you.
Put it on your PATH once:

```bash
mkdir -p ~/.local/bin && ln -sf ~/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets ~/.local/bin/desktop-widgets
desktop-widgets status
```

| command | what it does |
|---|---|
| `list` | index, type, on/off, corner, offsets, one-line summary per widget |
| `types [type]` | every widget type (built-in and drop-in), or one type's keys with type, default, range and description |
| `registry [--json]` | the merged registry; `--json` is what the service consumes |
| `new <name> [--force]` | scaffold a drop-in widget type under `~/.config/omarchy/desktop-widgets.d/` |
| `validate [file]` | check the config; exit 1 with per-widget messages on errors |
| `add <type> [--corner C] [--x N] [--y N] [--set key=value ...]` | append a widget |
| `set <index> key=value ...` | change values; typed by the registry (`show=cpu,mem`, `enabled=false`, `scale=1.5`) |
| `move <index> [--corner C] [--x N] [--y N]` | reposition |
| `enable <index>` / `disable <index>` | keep the widget in the file but hide it |
| `remove <index>` / `duplicate <index>` | delete, or copy into the next slot |
| `edit` | open in `$VISUAL`/`$EDITOR`, validate on save, keep `.bak`; comments survive |
| `status [--enabled]` | plugin enabled?, config health, windows on screen, last log lines; `--enabled` is a plain exit code for scripts |
| `toggle` | `omarchy plugin enable`/`disable` the plugin |
| `arrange [on\|off\|toggle]` | arm/disarm drag-to-place (asks the running shell) |
| `editor` | open or close the editor panel (`omarchy-shell shell toggle homelab.desktop-widgets`) |
| `write` | replace the whole config with a JSON document read from stdin; validated, `.bak` kept (the editor panel's write path) |
| `install` / `uninstall [--purge]` | link the CLI, add/remove menu rows and keybinds (marker blocks), write the example layout |
| `init [--force]` | write the example layout as your config |
| `path` | print the config path |

Every write is atomic and leaves the previous file at `desktop-widgets.json.bak`.
Mutating commands write plain JSON, so they refuse to touch a file that contains
comments unless you pass `--force` (use `edit` to keep comments). A write that
would produce an invalid config is refused with the reasons.

## Omarchy menu

Rows for the Omarchy menu (`~/.config/omarchy/extensions/omarchy-menu.jsonc`, hot-reloads).
Absolute paths via `$HOME` because the shell's environment need not include `~/.local/bin`.

```jsonc
"household.widgets":         {"icon":"󱂬","label":"Desktop widgets","aliases":["widgets"],"description":"Wallpaper-layer widgets"},
"household.widgets.editor":  {"icon":"󰏫","label":"Editor","action":"omarchy-shell shell toggle homelab.desktop-widgets '{}'"},
"household.widgets.edit":    {"icon":"","label":"Edit config","action":"omarchy-launch-terminal $HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets edit"},
"household.widgets.status":  {"icon":"󰋼","label":"Status","action":"omarchy-launch-floating-terminal-with-presentation \"$HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets status; read -n1 -s -r -p 'press any key'\""},
"household.widgets.enabled": {"icon":"󰔡","label":"Enabled","checked":"$HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets status --enabled","action":"$HOME/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets toggle"},
"household.widgets.restart": {"icon":"","label":"Restart shell","action":"omarchy-restart-shell"},
```

Replace `household` with whichever submenu you keep such rows in.

## Developing

Code lives in the plugin directory as a git checkout. Config changes hot-reload.
**Code** changes need `omarchy restart shell`: the shell's plugin reload only
watches the top level of the plugin directory and keeps already-compiled QML
under `widgets/` cached, so a disable/enable or a rescan is not enough.

```bash
node --test tests/*.test.js              # pure-JS parsing and formatting
omarchy plugin validate .                # manifest schema
journalctl --user _COMM=quickshell -f | grep desktop-widgets
hyprctl layers | grep homelab-desktop-widgets
```

Design notes: `docs/superpowers/specs/2026-09-09-desktop-widgets-design.md`. Where this is going (registry, CLI, native editor, drop-in widget types): `docs/ROADMAP.md`.
