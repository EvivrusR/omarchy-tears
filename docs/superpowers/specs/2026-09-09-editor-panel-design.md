# Desktop widgets — editor panel design (Phase 2)

Date: 2026-09-09. Approved direction: native Quickshell panel inside the same
plugin (Michael, DQ-024). Builds on Phase 1 (registry, JSONC, CLI `write`).

## Goal

A panel summoned like every other Omarchy panel that lets a human add,
remove, reorder, reposition and configure widgets without touching JSON,
with the desktop updating as they edit.

## Non-goals (Phase 3)

Drag-to-place on the desktop, template widgets, drop-in widget types.

## Shape

The plugin manifest gains a second kind:

```json
"kinds": ["service", "panel"],
"entryPoints": { "service": "Service.qml", "panel": "Editor.qml" }
```

The shell loads `Editor.qml` on demand when summoned and unloads it when
hidden (no `keepLoaded`), and injects `service` — the plugin's own running
`Service.qml` instance — so the editor reads the registry and the parsed
widgets straight from it instead of parsing again. Summon paths:

```
omarchy-shell shell toggle homelab.desktop-widgets '{}'    # keybind + menu row
desktop-widgets editor                                     # CLI wrapper for the above
```

`Editor.qml` root is an `Item` with `open(payloadJson)`, `close()` and an
`opened` bool, which is what the shell's summon/hide/toggle call. The visible
part is one `PanelWindow` on the Overlay layer with keyboard focus, centred,
sized around its content, drawn with `Color.popups.*` and `Style.cornerRadius`
so it matches Settings and Agents.

## Data flow

```
config file ──FileView──▶ Service.qml (strip → validate → defaults) ──▶ service.widgets
                                                                        service.registry
Editor.qml  ◀── reads both on open, copies widgets into an editable `doc`
   │ edits `doc` in memory (form fields, list ops)
   ├─ apply-on-change ON  → save() after every change (debounced 250 ms)
   └─ apply-on-change OFF → save() on Save; Revert reloads from service
save() ──Process──▶ desktop-widgets write  (stdin = JSON of doc)
                         │ validates, writes .bak, atomic rename
                         ▼
config file changes ──▶ Service hot-reloads ──▶ desktop updates
```

One writer for everything (CLI, editor): `desktop-widgets write`. The editor
never writes the file itself. Because the service watches the file, the
editor does not need to tell it anything after saving.

The editor keeps its own `doc` rather than binding to `service.widgets`
because the service's copy is default-filled and error-filtered; the editor
must show the user's raw entries, including disabled ones and ones with
errors, so they can fix them. Raw entries come from `service.rawWidgets`
(new property: the validated-but-unfiltered list plus its messages).

Comment loss: if the file contains comments (`service.configHasComments`),
the editor shows a one-line notice "saving from here drops comments" and
saves anyway on explicit Save; apply-on-change starts OFF in that case.

## Layout

```
┌ Desktop widgets ─────────────────────────────────────────── esc closes ┐
│ Widgets                        │  Clock                                 │
│ ● Clock          top-right     │  Corner    [TL] [TR] [BL] [BR]         │
│ ● System stats   bottom-left   │  X  [ 48 ]     Y  [ 64 ]               │
│ ● Uptime         bottom-right  │  Scale [1.0]   Backdrop [0.0]          │
│ ○ Claude         top-left  ⚠   │  Text colour [#F99957]  Muted [muted]  │
│                                │  Outline [#000000]  Halo [0.7]         │
│ [+ Add ▾] [Duplicate] [Remove] │  Align [auto ▾]   Screen [        ]    │
│ [↑] [↓]                        │  ── Clock ──────────────────────────   │
│                                │  Time format [HH:mm]                   │
│ Apply on change  (● on)        │  Date format [dddd d MMMM]             │
│ ⚠ widget 3: agent must be …    │                     [Revert]  [Save]   │
└────────────────────────────────────────────────────────────────────────┘
```

- **Left list**: one row per raw entry: enabled dot (click toggles
  `enabled`), display name from the registry (`types[type].displayName`,
  or the `title` when set), corner, and a ⚠ when that entry has validation
  errors. Selection drives the right form. `↑`/`↓` reorder (list order is
  z-order-free; it only affects the file order and index numbers).
- **Add** opens a dropdown of registry types; adding appends a default-filled
  entry (`{type, corner: top-right}`) and selects it.
- **Right form**: generated from `Registry.fieldsFor(type)`, common fields
  first, then a section header with the type's display name, then its
  fields. Field type → component mapping (final names confirmed by the
  shell survey; see "Components"):

| registry `type` | control |
|---|---|
| `boolean` | Toggle |
| `integer` | NumberField with min/max/step 1 |
| `number` | NumberField with min/max/step 0.05 |
| `enum` (corner) | ButtonGroup of four |
| `enum` (other) | Dropdown |
| `multi-enum` | MultiSelect |
| `string`, `path`, `command`, `color` | TextField (color gets a swatch preview) |

  Every control shows the registry `label`, and `description` as a tooltip
  or caption. Values write into `doc[selected][key]`; a value equal to the
  registry default is removed from the entry so the file stays minimal.
- **Footer**: apply-on-change toggle, the first validation error for the
  selected entry (or none), Revert, Save. Save is enabled only when `doc`
  differs from the last saved document.

## Keyboard

Esc closes (unsaved changes with apply-on-change OFF → ConfirmDialog
"Discard changes?"). Tab/Shift-Tab moves between controls. `j`/`k` move the
list selection when the list has focus. Ctrl+S saves.

## Error handling

- `desktop-widgets write` exits 1 → its stderr lines show in the footer,
  the doc stays as edited, nothing is written (the CLI guarantees that).
- Service not loaded (`service === null`, e.g. plugin disabled while the
  panel is open) → panel shows "plugin disabled" and a button that runs
  `omarchy plugin enable homelab.desktop-widgets`.
- Registry missing → panel shows the error and no form.

## Testing

- Pure logic in `widgets/EditorModel.js` (node-tested): `newEntry(type,
  registry)`, `setValue(entry, field, value)` with default-stripping,
  `moveEntry(list, i, dir)`, `entryLabel(entry, registry)`, `firstError(messages, i)`,
  `dirty(doc, saved)`.
- Live checks on the dev laptop: summon via IPC, add a clock, see it appear
  (apply-on-change), move it, disable it, Revert, Esc, and confirm the file
  and `.bak` contents; `omarchy plugin disable` while open closes cleanly.

## Risks

- Third-party panels receive the scoped shell facade, not the trusted
  shell. Nothing here needs more than `service` injection and `Process`.
- Development loop: panel code under the plugin root reloads on file
  change; if not, `omarchy restart shell` (known from Phase 1).
- Quickshell 0.3.1 `Process` must support writing to stdin for the `write`
  command; fallback is passing the JSON through a temp file the CLI reads
  (`write --file`). Decided by the survey.
