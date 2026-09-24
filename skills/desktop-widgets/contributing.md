# Changing the plugin itself

Only for behaviour every user needs. Anything personal is a drop-in or template (see SKILL.md).
The checkout at `~/.config/omarchy/plugins/homelab.desktop-widgets/` is **the live plugin**:
what you leave on disk is what the shell runs after the next restart.

## Ground rules

1. **Branch first — from a clean, unclaimed tree.** The checkout is one shared working tree: run `git status`
   and read the Agent Board (`02 Areas/Agent Board.md`) before branching; someone else's uncommitted work
   must not ride along. (`~/.claude/skills/desktop-widgets` is a symlink into this repo's `skills/`, so editing
   the skill is editing the repo.) Then `git checkout -b feat/<name>` from `master`. `master` is what `omarchy plugin update`
   pulls on other machines, so it must always run. Merge `--no-ff` when done; releases bump
   `manifest.json` version + `CHANGELOG.md` and tag `vX.Y.Z`. Push branches and master to `origin`
   (Forge, the working remote). **Never push a branch or master to `github`**: GitHub is releases-only,
   one squashed commit per tag on the local `public` branch, published by the release procedure in the
   maintainer's notes (commit-tree of the tag's tree onto `public`, force-push `public:master` + the tag).
2. **Registry first.** A new key or type starts in `widgets/registry.json` (`common` for keys on every
   type, `types.<name>.fields` otherwise; `rowFields` hints for `rows` fields). The CLI validator,
   the service's defaults and the editor's form all read it — add it there and they follow. QML then
   reads `config.<key>` and never hand-rolls a default. One thing the registry does not drive: the one-line
   summaries `desktop-widgets list` prints are per-type lambdas in `bin/desktop-widgets` (search `"clock": lambda`) —
   extend that by hand when a new key belongs in the summary.
2b. **The kit has a version.** `widgets/registry.json` `"api"` names the surface drop-ins rely on;
   `tests/fixtures/kit/api-<n>.json` lists it (kit properties/functions, import path, field types,
   injected `config`/`service`) and both suites check it still exists. Renaming or removing any of it:
   bump `api`, add `api-<n+1>.json`, say so in the CHANGELOG. Adding is not breaking — extend the fixture.
3. **One writer.** New CLI verbs and editor actions go through the existing `commit`/`write` path
   (validated, atomic, `.bak`). The editor never talks to widget instances; the service never writes config.
4. **Pure logic lives in `.js`/Python with tests.** Parsing, formatting, rule evaluation, placeholder
   filters: `widgets/*.js` (also `require`-able from node) and `bin/desktop-widgets`. Shared fixtures
   under `tests/fixtures/` are run by **both** suites where a rule exists in both languages (pet rules).
   QML stays a thin view and pulls the logic in with `import "Clock.js" as Clock` next to the widget
   (`Template.js`/`TemplateWidget.qml` is the model: the `.js` ends with `if (typeof module !== "undefined") module.exports = {…}`).
5. **Run both suites, read both summary lines, before every commit:**
   ```bash
   node --test tests/*.test.js                                   # not `tests/` — the fixtures dir breaks the runner
   python3 -m unittest discover -s tests 2>&1 | tail -3
   omarchy plugin validate . && echo manifest-ok                 # silent on success — check the exit code; we broke it once
   ```
6. **Restart to see code.** `omarchy restart shell` after any change under the plugin dir (compiled QML
   is cached; disable/enable and `rescan` do not reload it). Then check
   `journalctl --user _COMM=quickshell -n 60 | grep -i "desktop-widgets\|error"` — a plugin that fails
   to compile is dropped with `service plugin load failed` and the desktop goes blank, silently.
7. **Screens are evidence.** For editor/desktop work, `grim` (`-o <output>` on multi-monitor) a screenshot and look at it; wheel/scroll
   states can be driven with a uinput virtual mouse if no tool is installed (the device needs REL_X,
   REL_Y and BTN_LEFT or Hyprland ignores it).

## Where things are

| area | files |
|---|---|
| service: load config, registry, windows per widget, z order, IPC | `Service.qml`, `widgets/Registry.js` |
| widget kit | `widgets/WidgetCard.qml`, `WidgetText.qml`, `Sparkline.qml` |
| editor panel | `Editor.qml` (doc model, IPC `call` ops, save), `editor/EditorForm.qml` (form from registry), `editor/FieldControl.qml` (one control per field type), `widgets/EditorModel.js` |
| arrange mode | `arrange/ArrangeOverlay.qml`, bar companion `Companion.qml` |
| CLI + samplers | `bin/desktop-widgets` (stdlib Python), `bin/dw-signals`, `bin/dw-sample`, `bin/dw-weather`, `bin/dw-sysinfo` |
| shipped content | `presets/*.jsonc`, `examples/pets/`, `examples/drop-in/hello` |
| design history | `docs/superpowers/specs/*` (why), `docs/superpowers/plans/*` (how, with status tables), `docs/ROADMAP.md` (backlog) |

## Gotchas already paid for

- Config arrays arrive in QML as Qt lists (`Array.isArray` false): `WidgetCard.listOf()`.
- `top` is final on Items; hidden items still count in `childrenRect`.
- Variants reuse windows, so a stacking (`z`) change bumps `gen` to recreate them in order.
- `Layout.minimumWidth` does not propagate through a `Loader`; use implicit widths for overflow maths.
- Bar-widget kind + service kind in one plugin: Omarchy's `plugin enable … right` will not place the bar widget; users add `{ "id": "homelab.desktop-widgets" }` to `shell.json` by hand.
- Editor IPC `call` answers only after the panel has been opened once (`desktop-widgets editor`).
- Editor Download never replaces an existing petdex download; the CLI needs `--replace`.

## PR / merge checklist

- [ ] Registry updated before QML; `desktop-widgets types <type>` shows the new key with default and range
- [ ] Both test suites green; new pure logic has tests; shared fixtures updated for both languages
- [ ] `omarchy plugin validate .` passes; `omarchy restart shell` clean in the journal; widget seen on screen
- [ ] README section for the feature (config keys, CLI verb) and a `CHANGELOG.md` line under Unreleased
- [ ] Kit surface unchanged, or `api` bumped with a new `tests/fixtures/kit/api-<n>.json`
- [ ] No hard-coded colours, `$HOME` paths, hostnames or personal defaults in core files
- [ ] Nothing under `/usr/share/omarchy` touched; no new input regions; arrange mode still armed-only
- [ ] Branch pushed to every remote; merged `--no-ff`; version + tag only on a release
