# Widget kit — the contract a widget is written against

**Kit api 1** (since plugin 0.8.0, 2026-09-13). Everything on this page is that surface; the exact
list is `tests/fixtures/kit/api-1.json` in the plugin, and both test suites keep it true.

Built-in widgets under `widgets/` and drop-ins under `~/.config/omarchy/desktop-widgets.d/<name>/`
use the same contract. Start a drop-in with `desktop-widgets new <name>` (copies
`examples/drop-in/hello`). Names match `^[a-z][a-z0-9-]{0,39}$` and cannot shadow a built-in.

## type.json (registry fragment)

```json
{ "displayName": "WaniKani", "description": "Reviews due now.",
  "requires": { "api": 1 },
  "fields": [
    { "key": "url",         "type": "string",  "label": "Summary URL", "default": "http://host:39101/api/summary" },
    { "key": "intervalSec", "type": "integer", "label": "Refresh (s)", "default": 120, "min": 15, "max": 86400 },
    { "key": "warnAt",      "type": "integer", "label": "Warn above",  "default": 100, "min": 0, "max": 100000, "description": "turns red above this" },
    { "key": "showNext",    "type": "boolean", "label": "Show next review", "default": true }
  ] }
```

Field types: `string integer number boolean enum multi-enum color path command text rows apps`
(`enum`/`multi-enum` take `options`; numbers take `min`/`max`; `showWhen: {key: value}` hides a
field until another has that value). The common keys are added for you. Adding a field here is
all it takes for the CLI to validate it and the editor to show a control — no other wiring.
`desktop-widgets types <name>` shows the merged result; `desktop-widgets types` reports a broken
drop-in instead of loading it.

**`requires.api`** pins the kit version this file was written against (`desktop-widgets types`
prints the plugin's as `kit api N`; `tests/fixtures/kit/api-N.json` in the plugin is the exact
list). A mismatch is a warning from `types`/`validate` and in the journal — the drop-in still loads.
The number only moves on a breaking change to the surface below; leave `requires` out for a
private drop-in, put it in for one you share.

## Sharing a drop-in

The folder is the repo (`type.json` + `Widget.qml` at the root). `desktop-widgets ext add <git url> [name]`
clones it into `desktop-widgets.d/<name>/` and validates it (exit 2 usage/name, 4 git, 5 invalid, 6 exists);
`ext update [name]` pulls (`--ff-only`) and says when a shell restart is needed; `ext list` shows
name/api/origin/commit/in-use; `ext remove <name>` refuses while widgets use the type, `--force` removes
them through the one writer first. Nothing from the repo runs except its QML — read it before installing.

## Widget.qml

Before writing a fetcher, hit the data source once by hand (`curl -sf <url> | head -c 300`) and
build against what it really returns, not what the request describes.

```qml
import QtQuick
import Quickshell.Io                                            // Process, StdioCollector
import qs.Commons                                               // Color, Style, Util
import "../../plugins/homelab.desktop-widgets/widgets"          // WidgetCard, WidgetText, Sparkline (same path on every install)

WidgetCard {                                    // frame: backdrop card, padding, scale; `config` is the JSON entry with defaults applied
  id: root
  readonly property string url: String(config.url || "")
  readonly property int warnAt: Number(config.warnAt)
  property var data: null
  property bool failed: false
  readonly property bool warn: !!data && Number(data.reviews_due) > warnAt

  Process {                                     // argv, never a shell string; non-zero exit keeps the last data + shows "!"
    id: fetcher
    command: ["curl", "-sf", "--max-time", "10", root.url]
    stdout: StdioCollector { id: out }
    onExited: function(code) { root.failed = code !== 0; if (code === 0) { try { root.data = JSON.parse(out.text) } catch (e) { root.failed = true } } }
  }
  Timer { interval: Math.max(15, Number(config.intervalSec)) * 1000; running: root.url !== ""; repeat: true; triggeredOnStart: true
          onTriggered: if (!fetcher.running) fetcher.running = true }

  Column {
    spacing: Math.round(Style.space(2) * root.scale_)
    Row { spacing: Math.round(Style.space(6) * root.scale_)
      WidgetText { outlineColor: root.outlineColor; halo: root.halo; color: root.warn ? Color.urgent : root.mutedColor; text: "WANIKANI"
                   font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_) }
      WidgetText { visible: root.failed; outlineColor: root.outlineColor; halo: root.halo; color: Color.urgent; text: "!"
                   font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_) }
    }
    WidgetText { outlineColor: root.outlineColor; halo: root.halo; color: root.warn ? Color.urgent : root.textColor
                 text: root.data ? String(root.data.reviews_due) + " reviews" : "…"
                 font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.displayLarge * root.scale_); font.weight: Font.DemiBold }
  }
}
```

What `WidgetCard` gives you (read-only unless noted) — this table, the `WidgetText` properties
(`outlineColor`, `halo`, `outlineMinPx`) and `Sparkline`'s (`points`, `lineColor`, `outlineColor`,
`fillAlpha`, `lineWidth`, `px()`, `py()`) are the api-1 surface:

| property | meaning |
|---|---|
| `config` | the widget's JSON entry, registry defaults filled in; arrays may arrive as Qt lists — use `listOf(config.key)` |
| `scale_` | `config.scale`, clamp ≥ 0.25; multiply every pixel size by it |
| `textColor`, `mutedColor` | `color` / `mutedColor` resolved (token or colour string) |
| `outlineColor`, `halo` | pass both to every `WidgetText` so text keeps its outline; the halo itself is drawn once for the whole card |
| `groupHalo` (writable) | `true`: one halo pass over everything in the card. Set `false` when the content is not text (images, icons) and give the `WidgetText`s `ownHalo: true` |
| `align` | `left`/`right`, derived from the corner unless `align` is set |
| `resolveColor(value, fallback)` | token → theme colour, else `Qt.color`, else fallback |
| `pad` (writable) | inner padding; `0` for pure-form widgets |
| `topInset` (writable) | transparent room above the card inside the window (tooltips) |
| `service` | declare `property var service: null` and the service injects itself (pet states, `signals`, `sample` = the latest `bin/dw-sample` object from the shared stream — sample from it rather than starting your own process); only when you need it |
| `behindWindows` | declare `property bool behindWindows: false` and the service keeps it true while a window is open on the widget's screen; stop animations then |

Theme: `Color.foreground/background/accent/muted/urgent` are the active theme's tokens (`urgent` is
red on most themes, not all — say "the theme's urgent colour" when the user asked for red), `Color.popups.*`; `Util.alpha(c, a)`;
`Style.space(px)` (scaled spacing), `Style.cornerRadius`, `Style.font.resolvedFamily`,
`Style.font.caption/body/heading/displayLarge`. Widgets are separate layer-shell windows with an
**empty input region** — never add a MouseArea expecting clicks unless the type declares
`"input": true` in its registry entry (only `dock` does). Hidden items still count in
`childrenRect`; use `visible` on the whole row, not on a child.

## Testing a state you cannot trigger live

Point the widget at a fixture instead of waiting for the real condition:

```bash
echo '{"reviews_due":150,"lessons_due":7}' > /tmp/summary.json
python3 -m http.server 8765 --bind 127.0.0.1 --directory /tmp       # run it in the foreground of a spare terminal
desktop-widgets set 7 url=http://127.0.0.1:8765/summary.json         # red state (7 = the index `list` shows for the new widget)
desktop-widgets set 7 url=http://127.0.0.1:1/x                       # failure path: "!" shows, numbers stay
desktop-widgets set 7 url=http://host:39101/api/summary               # back
```

For a screenshot: `grim /tmp/shot.png` (workspace with no windows over the corner), or read the
window list with `hyprctl layers | grep homelab-desktop-widgets`.

## Where the built-ins live (copy the closest one)

| want | look at |
|---|---|
| text + date from a timer | `widgets/ClockWidget.qml` |
| a command's output, error marker | `widgets/CommandWidget.qml` |
| rows from JSON with placeholders | `widgets/TemplateWidget.qml` + `widgets/Template.js` |
| a colour that flips on a threshold | `widgets/BatteryWidget.qml` (`low → Color.urgent`) |
| sparklines / bars over time | `widgets/MonitorWidget.qml` + `widgets/Sparkline.qml` |
| a second full-screen window (effects) | `widgets/WeatherWidget.qml` + `WeatherEffect.qml` |
| sprites + rules over signals | `widgets/PetWidget.qml` + `widgets/Pet.js` (signals list: `Pet.SIGNAL_KEYS`) |
