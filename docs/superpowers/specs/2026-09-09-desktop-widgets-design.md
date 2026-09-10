# Omarchy desktop widgets — design

Date: 2026-09-09. Status: approved in chat (Michael picked clock, stats, command).

## Goal

Theme-aware widgets drawn on the wallpaper layer of Omarchy 4.x (Quattro),
delivered as a third-party shell plugin that never touches Omarchy's own
files, can be switched off with one stock command, and is removed cleanly.

## Non-goals

- Replacing or cloning `omarchy.background`.
- Interactive widgets (clicks, drag-to-move). Bottom-layer windows do not
  take keyboard focus and the windows are content-sized so the desktop's
  own double-click handlers keep working around them.
- Any dependency on Omarchy internals beyond the public plugin contract
  (`manifest.json`, `kinds: ["service"]`) and the `qs.Commons` theme
  singletons (`Color`, `Style`, `Util`) that every third-party plugin uses.

## Upgrade safety and rollback

| Concern | Answer |
|---|---|
| Omarchy update overwrites it | Code lives in `~/.config/omarchy/plugins/homelab.desktop-widgets/`, a git checkout. `/usr/share/omarchy` is never written. |
| Plugin breaks the shell | Third-party services are created with a null parent behind a scoped facade. A compile failure logs `service plugin load failed` and the shell carries on. Each widget renders inside its own `Loader`, so one bad widget type cannot take the others down. |
| Turn it off | `omarchy plugin disable homelab.desktop-widgets` destroys the instance immediately (stock command, one line removed from `plugins[]` in `shell.json`). |
| Remove it | `omarchy plugin remove homelab.desktop-widgets --yes`. |
| Update it | `omarchy plugin update homelab.desktop-widgets` (fast-forward pull with a diff preview). |
| Config survives update | Layout lives outside the checkout in `~/.config/omarchy/desktop-widgets.json`, watched for changes and hot-reloaded. |
| Theme changes | Colours and fonts are bound to `Color.*` and `Style.*`, so `omarchy theme set` recolours the widgets live. |

Known limit (measured 2026-09-09): the shell's local-plugin watcher only sees
the top level of the plugin directory, and compiled QML under `widgets/` stays
cached across rescans and disable/enable. **Code** changes therefore need
`omarchy restart shell`. Config changes hot-reload.

## Rendering

For every enabled widget entry and every screen it targets, the service
creates one `PanelWindow`:

- `WlrLayershell.layer: WlrLayer.Bottom` (above wallpaper, below windows)
- `WlrLayershell.namespace: "homelab-desktop-widgets"`
- `keyboardFocus: None`, `exclusionMode: Ignore`, `color: transparent`
- anchored to the configured corner, offset with `margins`, sized to
  the widget's implicit size.

A shared `WidgetCard` draws an optional rounded backdrop using
`Color.popups.background` at a configurable alpha (default 0, i.e. text
straight on the wallpaper) with `Style.cornerRadius`.

## Config file

`~/.config/omarchy/desktop-widgets.json`

```json
{
  "version": 1,
  "widgets": [
    { "type": "clock",   "corner": "top-right",    "x": 48, "y": 64,
      "timeFormat": "HH:mm", "dateFormat": "dddd d MMMM", "scale": 1.0 },
    { "type": "stats",   "corner": "bottom-left",  "x": 48, "y": 48,
      "show": ["cpu", "mem", "disk", "battery"], "intervalSec": 3, "diskPath": "/" },
    { "type": "command", "corner": "bottom-right", "x": 48, "y": 48,
      "title": "Render queue", "command": "cat ~/.cache/queue.txt",
      "intervalSec": 60, "maxLines": 8, "timeoutSec": 10 }
  ]
}
```

Common keys: `type` (required), `corner` (`top-left|top-right|bottom-left|bottom-right`, default `top-right`),
`x`/`y` margins in px, `enabled` (default true), `screen` (output name, default every screen),
`scale` (font multiplier, default 1), `backdrop` (0..1 alpha, default 0).

Missing file → no widgets, one log line. Malformed JSON → keep the last
good layout, log the parse error. Unknown `type` → skipped with a log line.

## Widget types

- **clock**: time on one line, date beneath. Qt date formats. One `Timer`
  per widget at 1 s.
- **stats**: CPU %, memory %, disk %, battery % as labelled bars. One
  `Process` per widget runs a small bash one-liner every `intervalSec`
  emitting one JSON line; CPU % is computed in QML from the delta between
  consecutive `/proc/stat` samples. Parsing and maths live in `widgets/Stats.js`
  so they can be unit-tested with plain node.
- **command**: runs `bash -lc <command>` under `timeout` every
  `intervalSec`, shows trimmed stdout (up to `maxLines`), optional title.
  Non-zero exit shows the last good output plus a muted "!" marker.

## Verification

- `omarchy plugin validate <repo>` passes.
- `node --test tests/` passes for `Stats.js` parsing.
- Live on the dev laptop: enable, see widgets; `omarchy theme set` recolours;
  `omarchy plugin disable` removes them; `enable` restores; `hyprctl reload`
  leaves them in place; journal shows no `service plugin load failed`.
- Malformed config edit keeps the last layout and logs.
