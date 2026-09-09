# Desktop widgets — round 2 design (2026-09-10)

Michael's brief after seeing shape widgets + presets: grid snapping; "looks" from the
ricing world (battery, fetch-style system details with custom ASCII art, a system
monitor with GPU/network toggles and time-series graphs); a bottom launcher dock;
a weather widget with an optional animated ASCII weather effect across the wallpaper.

Decisions taken with Michael: dock stays a **wallpaper-layer** widget (clickable where
no window covers it, never reserves space); build order **grid → monitor family →
weather → dock**; merge + v0.5.0 tag held until this round lands.

Research (subagents, 2026-09-10): Hyprland repo gallery = three Hall-of-Fame rices
(bare outlined clock, pixel battery glyph, fetch panel logo-above-table, filled
net sparklines). Open-Meteo: keyless, lat/lon only, geocoder for typed places,
CC-BY attribution, ~100 calls/day at 15-min refresh. Omarchy Apps menu = Quickshell
`DesktopEntries` minus `launcher.hides`; webapps are plain .desktop files; launch =
`uwsm-app -- gtk-launch <id>.desktop`. Omarchy's own background takes clicks, so a
Bottom-layer surface with a non-empty input region receives pointer input.

## Shared groundwork

- **Top-level settings.** The config gains top-level keys besides `version`/`widgets`
  (first: `grid`). Every writer preserves them: CLI mutators already write the parsed
  document back; `preset apply` and the service's `saveDoc` must carry them over.
  Presets never contain settings.
- **Series module** `widgets/Series.js`: fixed-window ring buffer keyed by time
  (`push(t, v)`, `window(seconds)`, `latest`, `max`), node-tested; used by monitor,
  battery (time-to-empty smoothing) and weather (hourly strip).
- **Sparkline** `widgets/Sparkline.qml`: `QtQuick.Shapes` path + filled area under the
  line, right edge = now, no axes; colour per series.

## 1. Grid snap (`feat/grid-snap`)

`"grid": { "enabled": false, "size": 24 }` at top level (size 4..256). Snap applies to
the *offset from the chosen corner* (`Arrange.snapPlace(place, size)`), so `x: 48`
stays 48 on a 24-grid and layouts never drift. Overlay: dotted grid while armed when
enabled, hint mentions `G` = toggle grid, `[`/`]` = size −/+ (both persist via the
one writer). CLI: `desktop-widgets grid [on|off|<px>]`. Editor: toggle + size field
in the header row. IPC: `grid on|off|toggle|<px>`.

## 2. Monitor family (`feat/monitor-family`)

One sampler script `bin/dw-sample` (Python stdlib) prints one JSON line per poll:
cpu %, mem %, per-interface net bytes (delta computed in JS), battery
(capacity, status, current_now, charge_now → time-to-empty/full), gpu (nvidia-smi
→ amdgpu sysfs `gpu_busy_percent` → else `null`), load, temps.

- **`battery`**: glyph styles `pixel | outline | text`; percent, charging arrow,
  time-to-empty/full; colour thresholds; hidden when no battery.
- **`sysinfo`**: fetch-style block — art left (`art`: lines, or `artFile`; default
  bundled Omarchy logo), key/value right, `fields` multi-enum (os, host, kernel,
  uptime, packages, shell, wm, cpu, gpu, memory, disk, ip, battery), optional
  `user@host` title line + rule + colour swatch row. Values via `bin/dw-sysinfo`
  (cached, refresh hourly; uptime/memory live).
- **`monitor`**: stats v2. `rows` multi-enum (cpu, mem, gpu, net-down, net-up,
  load, temp), `intervalSec` 10, `windowSec` 300, `graph: sparkline | bars | none`,
  `iface` (auto = default route), footer with headline numbers. `stats` stays as the
  simple widget; a preset shows both.

## 3. Weather + effects (`feat/weather`)

- **`weather`** widget: `place` (default `Tokyo, Japan`), `units` (metric/imperial),
  `refreshMin` 15, `show` (temp, feels, humidity, wind, hours strip, attribution),
  `layout: stacked | inline`. `bin/dw-weather` geocodes `place` once (Open-Meteo
  geocoder, cached under `~/.cache/desktop-widgets/weather/`), fetches current +
  next 12 h, prints JSON; never uses IP/location detection. Attribution line
  "Weather data by Open-Meteo.com" on by default.
- **Effect**: keys on the weather widget (`effect: true`, `effectOpacity` 0..1,
  `effectPlacement: back | front | custom`, `effectFps` 4..8). Rendered by a
  separate full-screen window from the service: `back` → created first, `front`
  → created last, `custom` → the widget's own `z`; the editor hides `z` unless
  custom. Opacity = user × preset. Effects by WMO group: sun/stars, clouds,
  overcast, fog, drizzle, rain (slant on wind), snow (sway), storm (flash).
  Particle field = one Text rebuilt per tick; clouds/sun/bolt = sprite Texts.
  Timer paused when the effect is static or the window hidden.

## 4. Launcher dock (`feat/dock`)

`dock` widget: `apps` (list of desktop-entry ids; new registry field type `apps`
whose editor control lists `DesktopEntries` minus Omarchy's hide list), `iconSize`,
`spacing`, `labels` on/off, `backdrop` default 0.5, default corner bottom-centre
(new `corner` value `bottom-center`? → no: add `align: center` support on the x
axis via a new common `anchor: corner | bottom-center | top-center`). Click →
`uwsm-app -- gtk-launch <id>.desktop`. First widget with a non-empty input region;
arrange mode still owns drags (overlay is above).

## Out of scope this round

Clock/agents layout variants; the agent Skill; reserved-space or auto-hide dock.
