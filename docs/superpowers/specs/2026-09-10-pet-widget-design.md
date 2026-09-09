# Pet widget — scope and plan (draft for Michael, 2026-09-10)

**Ask:** "something like Hermes Pets: sprites that do actions depending on specific things."

## What Hermes Pets actually is (researched 2026-09-10)

Shipped June 2026; engine at `~/.hermes/hermes-agent/agent/pet/`. A pet is a **purely cosmetic
sprite that mirrors what the agent is doing**. It is only a sprite sheet (`pet.json` +
`spritesheet.webp`, 192×208 px cells, 8 cols × 9 rows, one row per state: idle, running-right,
running-left, waving, jumping, failed, waiting, running, review; 6 frames, ~1.1 s per loop).
**The pet carries zero logic**: the host derives one state from a handful of boolean signals
(error > celebrate > just-completed > awaiting-input > tool-running > reasoning > busy > idle),
flashes transient beats (wave/jump/failed) for 1.6 s, and shows that row. ~3,000 community sheets
share the contract via the petdex gallery; `/hatch <description>` generates new ones.
Sources: Nous announcement, `website/docs/user-guide/features/pets.md`, local `agent/pet/*.py`.

## Proposal: a `pet` widget type

Keep Hermes' best property — **the sprite has no logic; rules live in config** — and reuse its
sprite contract so any petdex / hatched sheet drops in.

```jsonc
{ "type": "pet", "corner": "bottom-right", "x": 120, "y": 8,
  "sheet": "~/.hermes/pets/kiwi/spritesheet.webp",   // or a petdex slug once we add a fetcher
  "scale": 0.5, "fps": 6, "roam": false,
  "rules": [                                          // top-down, first match wins
    { "when": "claude.session >= 95", "state": "failed" },
    { "when": "battery.discharging && battery.pct < 20", "state": "waiting" },
    { "when": "agents.active > 0", "state": "running" },
    { "when": "claude.session >= 80", "state": "review" },
    { "on": "claude.reset", "state": "jumping", "beat": 1.6 },
    { "on": "battery.full", "state": "waving", "beat": 1.6 }
  ],
  "bubble": true }                                     // optional speech bubble with the matched rule's text
```

- **Signals** (polled every 2–5 s by one `bin/dw-signals` script, JSON out, same pattern as
  `dw-sample`): `claude.session/weekly` % and `claude.reset` (usage JSON + resetsAt), `battery.*`
  (sysfs), `agents.active` (running claude/codex processes, or Agent Board active claims),
  `net.busy` (byte deltas), `hour` (time of day), `cmd:<name>` (exit code of a user command).
- **Rules**: tiny expression grammar (`a.b OP number`, `&&`, `||`, `!`), evaluated in
  `widgets/Pet.js` (pure, node-tested). `when` = steady state; `on` = edge → beat for N s.
- **Rendering**: Qt `AnimatedSprite` over the sheet (`frameWidth 192`, `frameHeight 208`,
  `frameY = row × 208`, `frameDuration 183`), trailing blank cells trimmed once at load. No
  per-frame JS; only the signal timer and a one-shot beat timer. Optional `roam`: a
  `NumberAnimation` on x along the bottom edge, paused while "busy".
- **Editor**: registry type with `sheet` (path), `rules` (a rows-style editor like template rows:
  kind when/on, expression, state dropdown, beat), `bubble`, `roam`, `fps`.
- **Sheets**: ship one small CC0 sheet in `examples/pets/`; `desktop-widgets pet fetch <petdex-slug>`
  later (needs a look at petdex's download terms).

## Effort and order

1. Signals script + `Pet.js` rule engine + tests (½ evening).
2. `PetWidget.qml` with `AnimatedSprite`, beat timer, bubble (½ evening).
3. Editor rules control (reuse the template-rows editor) + docs + a shipped example sheet (½ evening).
4. Later: roam, petdex fetcher, ASCII-frame sheets for people without images.

## Decisions for Michael

- Reuse Hermes' sprite contract (recommended — thousands of sheets, and his hatched pets work) vs
  our own ASCII frame format (on-brand with outlined text, but no library).
- First signals to wire: Claude session %, battery, active agents (recommended trio) — others?
- Where the first sheet comes from: a Hermes pet already hatched on Hanna, or a petdex pick.
