# Linked and layered pets — scope (draft for Michael, 2026-09-10)

**Ask:** "linked pets so that you can layer them and allow stuff like outfit or furniture swap-out."

Two separable ideas: **layers** (one pet drawn from several sheets: body + outfit + prop) and
**links** (pets that know about each other). Neither exists in Hermes or petdex — checked the
engine and the docs; a pet there is exactly one sheet. So this is ours to define, and the
definition should keep the Hermes contract for every individual sheet so hatched/petdex art still works.

## 1. Layers (composition)

A pet gets an optional `layers` list. Each layer is another sheet in the **same atlas contract**
(192×208 cells, rows per state) or a single static image, drawn in lock-step with the body.

```jsonc
{ "type": "pet", "sheet": "~/.config/omarchy/desktop-widgets.pets/jill/spritesheet.webp", "watch": "claude", "size": 128,
  "layers": [
    { "sheet": "~/.config/omarchy/desktop-widgets.pets/jill-outfits/raincoat/spritesheet.webp", "kind": "outfit", "z": "front" },
    { "image": "~/.config/omarchy/desktop-widgets.pets/props/bar-stool.png", "kind": "prop", "z": "back", "x": -20, "y": 6, "scale": 1 },
    { "sheet": "…/props/desk-lamp/spritesheet.webp", "kind": "prop", "z": "front", "follow": "idle" }
  ] }
```

- **Sync.** The body's `AnimatedSprite.currentFrame` is readable and signals changes; every
  `sheet` layer is an `Image` with `sourceClipRect = (frame×192, row×208, 192, 208)`, so all
  layers show the same row and frame — no drift, no second clock. A layer whose sheet lacks the
  current row falls back to its `follow` row (default idle) or its row 0.
- **z**: `back` (behind the body) or `front`; list order breaks ties. Static `image` layers are
  just positioned PNG/SVG with `x`/`y` offsets and `scale` relative to the body cell.
- **Swap-out** is config: change the layer's `sheet`. Editor: a rows-style layer editor plus a
  **wardrobe** dropdown per layer listing sheets found under `<pet-dir>/outfits/*` and
  `desktop-widgets.pets/props/*` (extend `desktop-widgets pets` to list those too).
- **Trim** per layer reuses the pet's Canvas trim; counts come from the body sheet (layers follow).

**The real blocker is content, not code.** Outfit layers need art drawn *over a transparent
body* at the same cell geometry. Options: (a) hatch them in Hermes — `/hatch "a raincoat only,
transparent body, for <pet>"` is an experiment worth one evening; the generator makes whole
pets, so results may need cleanup; (b) hand-made props (PNG, no animation) work today;
(c) a `mask` mode: the outfit sheet is a full pet variant and we cut it to the body's alpha —
gives "colour swaps" cheaply without transparent art. Recommend (b) first, (a) as the spike.

## 2. Links (pets reacting to each other)

Each pet publishes its state and rule text as signals every tick: `pets.<name>.state`,
`pets.<name>.say`, plus `pets.<name>.watchValue`. Rules can then read them:

```jsonc
{ "kind": "on",   "if": "pets.jill.state == 'failed'", "state": "waving", "beat": 2, "say": "you ok?" },
{ "kind": "when", "if": "pets.girl.state == 'running'", "state": "running" }
```

- Pets get a `name` (default: sheet folder). The service keeps a shared `petStates` map;
  `PetWidget` writes its own entry and reads others through the injected service (same
  mechanism the editor uses).
- Adds a tiny grammar extension: quoted strings in expressions. Ordering: a pet reads the
  *previous* tick's states, so two pets never wait on each other.
- Cheap: half an evening after layers, and it also gives "group" behaviours (all pets wave when
  the session resets).

## 3. Not now

Physical linking (a pet riding another, walking together) — needs roam first, then a
follow-the-leader offset; queue behind roam.

## Effort and order

1. Layers: static `image` props + `sheet` layers with frame sync + editor rows (one evening).
2. Wardrobe listing + `pets` CLI extension + docs (half an evening).
3. Links: published pet states + string literals in rules (half an evening).
4. Spike: hatch a transparent-body outfit in Hermes; decide whether outfits are viable art.

## Decisions for Michael

- Start with props (PNG furniture, works with any art today) before outfits? (recommended)
- Try the Hermes hatch spike for an outfit sheet, on Venni or the default profile?
- Links: is "reads other pets' states in rules" the behaviour you meant, or physical grouping?
