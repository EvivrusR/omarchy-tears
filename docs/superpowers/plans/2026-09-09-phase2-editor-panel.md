# Desktop Widgets Phase 2: Native Editor Panel — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Quickshell panel inside the plugin that adds, removes, reorders, positions and configures widgets through registry-generated forms, saving through `desktop-widgets write`, with the desktop updating as you edit.

**Architecture:** `Editor.qml` is a second entry point (`kinds: ["service","panel"]`). The shell injects the running `Service.qml` as `service`; the editor copies `service.rawWidgets` into an editable `doc`, renders a list on the left and a form generated from `widgets/registry.json` on the right, and saves by piping the document into `desktop-widgets write` over a `Process` stdin. The service's file watcher then reloads the desktop.

**Tech Stack:** Quickshell 0.3.1 (PanelWindow on Overlay layer, Process with `stdinEnabled`), Omarchy `qs.Ui` components (TextField, NumberField, Dropdown, MultiSelect, ButtonGroup, Toggle, ToggleSwitch, Button, ConfirmDialog, BorderSurface), `widgets/EditorModel.js` (already tested), Node tests.

**Spec:** `docs/superpowers/specs/2026-09-09-editor-panel-design.md`.

## Status (handoff block — update after every task)

**PHASE 2 COMPLETE 2026-09-09.** Next: Phase 3 (drag-to-place edit mode, `template` widget type, drop-in types under `desktop-widgets.d/`) — needs Michael's priority call (DQ-024 left that open).

| Task | State | Commit | Notes |
|---|---|---|---|
| 1 Manifest + panel shell (open/close/Esc/scrim) | done | 02cd07a | service injected into panel confirmed |
| 2 List + doc model + Save/Revert via CLI write | done | 884be86 | scripted live test: add→5 layers, set, default-strip, invalid refused, revert, remove |
| 3 Generated form (FieldControl/EditorForm) + apply-on-change | done | 884be86 | screenshot docs/editor.png |
| 4 Polish: comments notice, disabled state, Ctrl+S, menu row, keybind, docs | done | 884be86 + next | keybind SUPER+ALT+W (SHIFT+W = Omawrite) |

**How to resume:** read this file, the spec, `README.md`; run `node --test tests/*.test.js` and `python3 -m unittest discover -s tests -p 'test_*.py'`; continue at the first task not done. Code changes anywhere in the plugin need `omarchy restart shell`; summon the panel with `desktop-widgets editor` (or `omarchy-shell shell toggle homelab.desktop-widgets '{}'`); watch `journalctl --user _COMM=quickshell -f | grep -E "desktop-widgets|panel plugin"`.

## Global Constraints

- Same as Phase 1 (no runtime dependency beyond the shell and Python 3; nothing under `/usr/share/omarchy` written; config path unchanged; every write via the CLI keeps `.bak`).
- The panel never writes the config file directly. Only `desktop-widgets write`.
- The panel must not break the service: a panel load failure is logged by the shell and the widgets keep rendering.
- Commit per task with the session trailer; push to Forge.

---

## File structure

| File | Responsibility |
|---|---|
| `manifest.json` | add `"panel"` kind and `entryPoints.panel: "Editor.qml"` |
| `Editor.qml` | root Item: `opened`, `open()`, `close()`, `service`; PanelWindow + scrim + card; doc model; list; footer; save/revert; keys |
| `editor/EditorForm.qml` | Column of FieldControl rows for one entry, generated from the registry |
| `editor/FieldControl.qml` | one registry field → the right control; emits `edited(key, value)` |
| `widgets/EditorModel.js` | (exists) pure helpers |
| `bin/desktop-widgets` | (exists) `write`, `editor` |
| `README.md`, vault guide | docs |

Shell facts this relies on (measured 2026-09-09): the panel Loader calls `open(payloadJson)` and `close()`, reads `opened`, and injects `service` (`shell.qml:1349`). `Ui/NumberField` is integer-only (`value: int`, `modified(int)`); floats use a TextField. `Ui/Toggle` emits `clicked()` and the caller flips `checked`. `Ui/Dropdown`/`ButtonGroup` emit `changed(string)`, `MultiSelect` emits `changed(var values)`. Process has `stdinEnabled` and `write()`.

---

### Task 1: Manifest and panel shell

**Files:** Modify `manifest.json`; Create `Editor.qml`.

**Interfaces:** Produces the root with `property bool opened`, `function open(payloadJson)`, `function close()`, `property var service`, `property var manifest`, `property var shell`. Card geometry properties `cardWidth`, `cardHeight`, `pad`.

- [ ] **Step 1: manifest**

```json
"kinds": ["service", "panel"],
"entryPoints": { "service": "Service.qml", "panel": "Editor.qml" }
```

- [ ] **Step 2: Editor.qml skeleton** (full file; later tasks replace the marked regions)

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "widgets/EditorModel.js" as Model

Item {
  id: root
  property var service: null
  property var manifest: null
  property var shell: null
  property bool opened: false

  readonly property var registry: service ? service.registry : null
  readonly property int pad: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(900), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(620), panel.height - Style.gapsOut * 2)
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  function open(payloadJson) {
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() { opened = false }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "homelab-desktop-widgets-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: root.borderSpec
      padding: root.pad
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) { root.close(); event.accepted = true }
        }

        Text {   // placeholder replaced in Task 2
          text: "Desktop widgets"
          color: Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }
      }
    }
  }
}
```

- [ ] **Step 3: Live check**: `omarchy plugin validate . && omarchy restart shell`, then `desktop-widgets editor` opens a centred card with the title, Esc closes, clicking the scrim closes, `desktop-widgets editor` again toggles. Journal shows no `panel plugin ... failed to load`. Widgets still on screen (4 layers).

- [ ] **Step 4: Commit** `git commit -am "Editor panel: manifest kind + window shell"`; update Status.

---

### Task 2: List, doc model, Save/Revert

**Files:** Modify `Editor.qml`.

**Interfaces:** `doc` (array of raw entries), `saved` (last written array), `selected` (index), `dirty`, `save()`, `revert()`, `addWidget(type)`, `removeSelected()`, `duplicateSelected()`, `moveSelected(dir)`, `toggleEnabled(i)`, `errorText`.

- [ ] **Step 1: model + actions** (inside root, above `PanelWindow`)

```qml
  property var doc: []
  property var saved: []
  property int selected: -1
  property bool applyOnChange: true
  property string statusText: ""
  property bool saving: false
  readonly property bool dirty: Model.dirty(doc, saved)
  readonly property var messages: service ? service.messages : []

  function loadFromService() {
    var raw = service && service.rawWidgets ? service.rawWidgets : []
    doc = JSON.parse(JSON.stringify(raw))
    saved = JSON.parse(JSON.stringify(raw))
    if (selected >= doc.length) selected = doc.length - 1
    if (selected < 0 && doc.length > 0) selected = 0
  }
  function open(payloadJson) {
    loadFromService()
    applyOnChange = !(service && service.configHasComments)
    statusText = service && service.configHasComments ? "file has comments — saving from here drops them" : ""
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function touch() {            // call after any doc mutation
    doc = doc.slice()           // new reference so bindings refresh
    if (applyOnChange) saveTimer.restart()
  }
  function addWidget(type) { doc.push(Model.newEntry(type, registry)); selected = doc.length - 1; touch() }
  function removeSelected() { if (selected < 0) return; doc.splice(selected, 1); if (selected >= doc.length) selected = doc.length - 1; touch() }
  function duplicateSelected() { if (selected < 0) return; doc.splice(selected + 1, 0, JSON.parse(JSON.stringify(doc[selected]))); selected += 1; touch() }
  function moveSelected(dir) { if (selected < 0) return; selected = Model.moveEntry(doc, selected, dir); touch() }
  function toggleEnabled(i) { var e = doc[i]; Model.setValue(e, "enabled", e.enabled === false, registry); touch() }
  function setField(key, value) { if (selected < 0) return; Model.setValue(doc[selected], key, value, registry); touch() }
  function revert() { loadFromService(); statusText = "reverted" }
  function save() {
    if (saving) { saveTimer.restart(); return }
    saving = true
    statusText = "saving…"
    writer.running = true
  }

  Timer { id: saveTimer; interval: 250; onTriggered: root.save() }

  Process {
    id: writer
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/homelab.desktop-widgets/bin/desktop-widgets", "write"]
    stdinEnabled: true
    onStarted: { writer.write(JSON.stringify({ version: 1, widgets: root.doc }) + "\n"); writer.stdinEnabled = false }
    stderr: StdioCollector { id: writerErr }
    onExited: function(code) {
      root.saving = false
      if (code === 0) { root.saved = JSON.parse(JSON.stringify(root.doc)); root.statusText = "saved" }
      else root.statusText = String(writerErr.text || "").trim().split("\n")[0] || ("write failed (" + code + ")")
    }
  }
```

Note: the CLI path is the plugin's own `bin/desktop-widgets` (the panel's source dir is not exposed as a plain path, and `$HOME/.config/omarchy/plugins/<id>` is where `omarchy plugin add` puts it). `stdinEnabled = false` after writing closes stdin so the CLI sees EOF.

- [ ] **Step 2: layout** (replace the placeholder Text inside keyCatcher)

```qml
        ColumnLayout {
          anchors.fill: parent
          spacing: Style.spacing.md

          RowLayout {   // header
            Layout.fillWidth: true
            Text { text: "Desktop widgets"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.title; font.weight: Font.DemiBold }
            Item { Layout.fillWidth: true }
            Text { text: "esc closes"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }

          RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Style.spacing.lg

            ColumnLayout {   // left: list + actions
              Layout.preferredWidth: Style.space(300); Layout.fillHeight: true
              spacing: Style.spacing.sm
              ListView {
                id: list
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: root.doc
                currentIndex: root.selected
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  width: list.width
                  height: Style.spacing.controlHeight
                  radius: Style.cornerRadius / 2
                  color: index === root.selected ? Color.menu.selectedBackground : "transparent"
                  RowLayout {
                    anchors.fill: parent; anchors.leftMargin: Style.spacing.sm; anchors.rightMargin: Style.spacing.sm
                    spacing: Style.spacing.sm
                    Text {
                      text: modelData.enabled === false ? "○" : "●"
                      color: modelData.enabled === false ? Color.muted : Color.accent
                      font.pixelSize: Style.font.body
                      MouseArea { anchors.fill: parent; onClicked: root.toggleEnabled(index) }
                    }
                    Text { text: Model.entryLabel(modelData, root.registry); color: index === root.selected ? Color.menu.selectedText : Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: String(modelData.corner || "top-right"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    Text { visible: Model.firstError(root.messages, index) !== ""; text: "⚠"; color: Color.urgent; font.pixelSize: Style.font.body }
                  }
                  MouseArea { anchors.fill: parent; z: -1; onClicked: root.selected = index }
                }
              }
              RowLayout {
                spacing: Style.spacing.sm
                Dropdown {
                  id: addType
                  showLabel: false
                  value: ""
                  options: { var o = [{ value: "", label: "+ Add…" }]; var t = root.registry ? root.registry.types : {}; for (var k in t) o.push({ value: k, label: t[k].displayName || k }); return o }
                  onChanged: function(v) { if (v) { root.addWidget(v); addType.value = "" } }
                }
                Button { text: "Duplicate"; bordered: true; enabled: root.selected >= 0; onClicked: root.duplicateSelected() }
                Button { text: "Remove"; bordered: true; enabled: root.selected >= 0; onClicked: root.removeSelected() }
                Button { iconText: "↑"; bordered: true; enabled: root.selected > 0; onClicked: root.moveSelected(-1) }
                Button { iconText: "↓"; bordered: true; enabled: root.selected >= 0 && root.selected < root.doc.length - 1; onClicked: root.moveSelected(1) }
              }
            }

            Rectangle { width: 1; Layout.fillHeight: true; color: Util.alpha(Color.popups.border, 0.4) }

            Item {   // right: form (Task 3 fills this)
              id: formHost
              Layout.fillWidth: true; Layout.fillHeight: true
            }
          }

          RowLayout {   // footer
            Layout.fillWidth: true
            spacing: Style.spacing.md
            ToggleSwitch { checked: root.applyOnChange; onToggled: { root.applyOnChange = !root.applyOnChange; if (root.applyOnChange && root.dirty) root.save() } }
            Text { text: "Apply on change"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
            Text {
              Layout.fillWidth: true
              text: root.selected >= 0 && Model.firstError(root.messages, root.selected) !== "" ? "⚠ " + Model.firstError(root.messages, root.selected) : root.statusText
              color: root.statusText.indexOf("ERROR") === 0 || Model.firstError(root.messages, root.selected) !== "" ? Color.urgent : Color.muted
              font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight
            }
            Button { text: "Revert"; bordered: true; enabled: root.dirty; onClicked: root.revert() }
            Button { text: "Save"; bordered: true; selected: root.dirty; enabled: root.dirty && !root.saving; onClicked: root.save() }
          }
        }
```

Check `Ui/Button.qml` for its click signal name before wiring (`clicked()` from BorderSurface/MouseArea; confirm with `grep -n "signal" Ui/Button.qml`).

- [ ] **Step 3: Live check**: restart shell; open the editor; the four widgets are listed with corners; Add → Clock appends and (apply-on-change on) a fifth clock appears on the desktop within a second; ↑ moves it; Remove deletes it and the desktop follows; `.bak` exists; Revert after toggling apply-on-change off restores. Journal clean.

- [ ] **Step 4: Commit** `"Editor panel: widget list, doc model, save through desktop-widgets write"`; update Status.

---

### Task 3: Generated form

**Files:** Create `editor/FieldControl.qml`, `editor/EditorForm.qml`; modify `Editor.qml` (formHost).

**Interfaces:** `EditorForm { entry, registry, messages, index; signal edited(string key, var value) }`. `FieldControl { field, value; signal edited(string key, var value) }`.

- [ ] **Step 1: FieldControl.qml**

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// One registry field → one control. `value` is the effective value
// (entry value or default); edits are reported, never applied locally.
RowLayout {
  id: root
  property var field: ({})
  property var value
  signal edited(string key, var value)
  spacing: Style.spacing.md
  readonly property string kind: String(field.type || "string")

  Text {
    text: field.label || field.key
    color: Color.popups.text
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    Layout.preferredWidth: Style.space(140)
    elide: Text.ElideRight
    ToolTipText { text: field.description || "" }   // see note below
  }

  Loader {
    id: control
    Layout.fillWidth: true
    sourceComponent: {
      switch (root.kind) {
        case "boolean": return boolComp
        case "integer": return intComp
        case "number": return numberComp
        case "enum": return root.field.key === "corner" ? cornerComp : enumComp
        case "multi-enum": return multiComp
        default: return textComp
      }
    }
  }

  Component { id: boolComp
    ToggleSwitch { checked: root.value === true; onToggled: root.edited(root.field.key, !(root.value === true)) } }
  Component { id: intComp
    NumberField { value: Number(root.value || 0); from: root.field.min !== undefined ? root.field.min : -100000; to: root.field.max !== undefined ? root.field.max : 100000; stepSize: 1; onModified: function(v) { root.edited(root.field.key, v) } } }
  Component { id: numberComp
    TextField { text: String(root.value === undefined ? "" : root.value); Layout.preferredWidth: Style.spacing.numberFieldWidth
      onEditingFinished: { var v = parseFloat(text); if (!isNaN(v)) root.edited(root.field.key, v) } } }
  Component { id: cornerComp
    ButtonGroup { value: String(root.value || "top-right"); options: [{ value: "top-left", label: "TL" }, { value: "top-right", label: "TR" }, { value: "bottom-left", label: "BL" }, { value: "bottom-right", label: "BR" }]; onChanged: function(v) { root.edited(root.field.key, v) } } }
  Component { id: enumComp
    Dropdown { showLabel: false; value: String(root.value || ""); options: (root.field.options || []).map(function(o) { return { value: o, label: o } }); onChanged: function(v) { root.edited(root.field.key, v) } } }
  Component { id: multiComp
    MultiSelect { showLabel: false; values: Array.isArray(root.value) ? root.value : []; options: (root.field.options || []).map(function(o) { return { value: o, label: o } }); onChanged: function(vals) { root.edited(root.field.key, vals) } } }
  Component { id: textComp
    RowLayout {
      spacing: Style.spacing.sm
      Rectangle { visible: root.kind === "color"; width: Style.space(16); height: width; radius: width / 2
        color: { var v = String(root.value || ""); var tok = { foreground: Color.foreground, background: Color.background, accent: Color.accent, muted: Color.muted, urgent: Color.urgent }; return tok[v] !== undefined ? tok[v] : (v ? v : "transparent") }
        border.width: 1; border.color: Util.alpha(Color.popups.text, 0.3) }
      TextField { Layout.fillWidth: true; text: String(root.value === undefined ? "" : root.value); onEditingFinished: root.edited(root.field.key, text) }
    } }
}
```

Note: there is no `ToolTipText` in `qs.Ui`; render `field.description` as a muted caption beneath the label instead (a second `Text` in a `ColumnLayout`), which is what the shell's own settings do. Adjust when writing.

- [ ] **Step 2: EditorForm.qml**

```qml
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../widgets/EditorModel.js" as Model

Flickable {
  id: root
  property var entry: null
  property var registry: null
  signal edited(string key, var value)
  contentHeight: column.implicitHeight
  clip: true

  readonly property var fields: entry && registry ? Model.fieldsFor(String(entry.type || ""), registry) : []
  readonly property string typeName: entry && registry && registry.types[entry.type] ? (registry.types[entry.type].displayName || entry.type) : String(entry ? entry.type : "")

  ColumnLayout {
    id: column
    width: root.width
    spacing: Style.spacing.sm
    Text { visible: !root.entry; text: "Select a widget, or add one."; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body }
    Repeater {
      model: root.fields.filter(function(f) { return f.type !== "type" })
      delegate: ColumnLayout {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        spacing: Style.spacing.xs
        PanelSectionHeader {
          visible: index === (root.registry ? root.registry.common.length - 1 : 0)   // first type-specific field
          text: root.typeName
        }
        FieldControl {
          Layout.fillWidth: true
          field: modelData
          value: Model.valueOf(root.entry, modelData.key, root.registry)
          onEdited: function(key, value) { root.edited(key, value) }
        }
      }
    }
  }
}
```

The section header index: common fields count minus the `type` field (filtered out) equals the index of the first type field; compute as `registry.common.length - 1`.

- [ ] **Step 3: mount in Editor.qml** (inside `formHost`)

```qml
              EditorForm {
                anchors.fill: parent
                entry: root.selected >= 0 ? root.doc[root.selected] : null
                registry: root.registry
                onEdited: function(key, value) { root.setField(key, value) }
              }
```

Add `import "editor"` to `Editor.qml`.

- [ ] **Step 4: Live check**: restart shell; select the clock; change corner via TL/TR/BL/BR → desktop moves within a second; set x with the spinner; type a colour and press Enter → colour changes; toggle Enabled; stats `show` multi-select drops battery; command `title` edits; a value reset to its default disappears from the file (`desktop-widgets list`/cat). Errors shown in the footer when e.g. scale typed as 9 (registry max 4 → CLI refuses → footer shows the reason, file unchanged).

- [ ] **Step 5: Commit** `"Editor panel: registry-generated form with apply-on-change"`; update Status.

---

### Task 4: Polish, integration, docs

- [ ] Ctrl+S saves; Esc with dirty + apply-on-change off → ConfirmDialog "Discard changes?" (use `Ui/ConfirmDialog`: `opened`, `message`, `confirmed()`, `canceled()`, `handleKey(event)`); `j`/`k` move selection when no text field has focus.
- [ ] `service === null` → card shows "plugin service not running" and a Button running `omarchy plugin enable homelab.desktop-widgets` via `Quickshell.execDetached`.
- [ ] Household menu: `"household.widgets.editor": {"icon":"","label":"Editor","action":"omarchy-shell shell toggle homelab.desktop-widgets '{}'"}` as the first row; keybind suggestion in README: `o.bind("SUPER + SHIFT + W", "Desktop widgets editor", "omarchy-shell shell toggle homelab.desktop-widgets '{}'")` in `~/.config/hypr/bindings.lua` (add on envi-laptop; check `hyprctl binds` for a clash first).
- [ ] README "Editor" section with a screenshot `docs/editor.png`; vault guide section; memory; board; plan status all done.
- [ ] Commit `"Editor panel: keyboard, disabled state, menu row, keybind, docs — Phase 2 complete"`; push.

## Self-review

- Spec coverage: summon/close (T1), data flow + single writer (T2), list ops + form generation + default stripping + apply-on-change (T2/T3), comment notice (T2 open()), keyboard (T1/T4), error handling (T2 footer, T4 disabled state), testing (EditorModel tests exist; live checks per task).
- Names used consistently: `doc`, `saved`, `selected`, `setField`, `touch`, `save`, `revert`, `EditorForm.edited(key, value)`, `FieldControl.edited(key, value)`, `Model.valueOf/setValue/newEntry/moveEntry/entryLabel/firstError/dirty`.
- Open risk: `Button` click signal name and `Dropdown` option object shape (`{value,label}` accepted per `optionValue/optionLabel` helpers) — verify in Task 2 step 2 before relying on them.
