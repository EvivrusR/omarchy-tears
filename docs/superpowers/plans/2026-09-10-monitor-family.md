# Desktop Widgets: Monitor family (battery, sysinfo, monitor) — Implementation Plan

**Spec:** `docs/superpowers/specs/2026-09-10-round2-design.md` §2. Looks from the ricing survey: pixel battery glyph, fetch panel (logo left or above, key/value table), stat card with filled sparkline, headline numbers in a footer, net down/up as a colour pair.

**Architecture:** one sampler `bin/dw-sample` (Python stdlib, one JSON object per run: cpu/mem/load/temp/net counters/battery/gpu) shared by `battery` and `monitor`; `bin/dw-sysinfo` wraps `fastfetch --format json` (+ builtin logo lines) for `sysinfo`. Pure maths in `widgets/Monitor.js` (net rates from counters, unit formatting, time-to-empty) and `widgets/Series.js` (time-keyed ring buffer) — node-tested. `widgets/Sparkline.qml` draws a series (QtQuick.Shapes, filled area, right edge = now).

## Status

| Task | State | Notes |
|---|---|---|
| 1 `bin/dw-sample` + `bin/dw-sysinfo` (+ python tests on fixture text) | done | sampler 0.26 s; fastfetch uptime is ms |
| 2 `Series.js`, `Monitor.js` (+ node tests), `Sparkline.qml` | done | 51 node |
| 3 `battery`, `sysinfo`, `monitor` widgets + registry entries; live | done | ops preset applied live: 6 layers, sysinfo 572×264, monitor 224×298, battery 158×84; gotcha: `top` is a FINAL property name on Items — don't declare it |
| 4 Preset `ops`, README/CHANGELOG/vault | done | visual look owed a human eye (`desktop-widgets preset apply ops` / `apply michael`) |

**How to resume:** run both suites; continue at the first task not done; restart the shell after QML changes.

## Constraints
- Sampler must finish well under 1 s (cpu delta uses a 0.2 s pause) and never fail the whole object: each section is best-effort with `null` on error.
- GPU: `nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits` → amdgpu `gpu_busy_percent` → `null`. Intel shows "n/a".
- Default interface = default route; `iface` config overrides.
- Widgets keep the outlined-text contract; graphs use `textColor`/`mutedColor`, net up/down get accent/urgent-tinted pair unless overridden.
