import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "widgets/EditorModel.js" as Model
import "widgets/Pet.js" as Pet
import "editor"

// Editor panel for desktop-widgets. Summoned by the shell
// (`omarchy-shell shell toggle homelab.desktop-widgets '{}'`); the shell
// injects `service` (the running Service.qml) so this reads the registry and
// the raw entries from it. Every save goes through `desktop-widgets write`
// (validated, .bak kept); the service's file watcher then updates the desktop.
Item {
  id: root
  property var service: null
  property var manifest: null
  property var shell: null
  property bool opened: false

  readonly property var registry: service ? service.registry : null
  readonly property var messages: service ? service.messages : []
  readonly property string cliPath: String(Qt.resolvedUrl("bin/desktop-widgets")).replace(/^file:\/\//, "")
  readonly property int pad: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(940), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(640), panel.height - Style.gapsOut * 2)
  readonly property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))

  // ---- document model
  property var doc: []
  property var saved: []
  property int selected: -1
  property bool applyOnChange: true
  property string statusText: ""
  property bool saving: false
  readonly property bool dirty: Model.dirty(doc, saved)
  readonly property var selectedEntry: selected >= 0 && selected < doc.length ? doc[selected] : null
  // Published pet names, computed like the service does: an entry with an
  // active validation error is treated as disabled (Pet.js stays pure — this
  // mirrors Service.qml excluding both disabled AND errored widgets from `widgets`).
  readonly property var publishedNames: Pet.uniqueNames(doc.map(function(e, i) { if (!e || Model.firstError(root.messages, i) === "") return e; var c = {}; for (var k in e) c[k] = e[k]; c.enabled = false; return c }))

  function loadFromService() {
    var raw = service && service.rawWidgets ? service.rawWidgets : []
    doc = JSON.parse(JSON.stringify(raw))
    saved = JSON.parse(JSON.stringify(raw))
    if (selected >= doc.length) selected = doc.length - 1
    if (selected < 0 && doc.length > 0) selected = 0
  }
  function open(payloadJson) {
    loadFromService()
    refreshPresets()
    applyOnChange = !(service && service.configHasComments)
    statusText = service && service.configHasComments ? "file has comments — saving from here drops them" : ""
    opened = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  function close() { opened = false }
  property bool confirmOpen: false
  function dismiss() {
    if (dirty && !applyOnChange && !confirmOpen) { confirmOpen = true; return }
    confirmOpen = false
    opened = false
    if (shell && typeof shell.hide === "function") shell.hide((manifest && manifest.id) || "homelab.desktop-widgets")
  }
  function touch() {
    doc = doc.slice()
    if (applyOnChange) saveTimer.restart()
  }
  function addWidget(type) { doc.push(Model.newEntry(type, registry)); selected = doc.length - 1; touch() }
  function removeSelected() { if (selected < 0) return; doc.splice(selected, 1); if (selected >= doc.length) selected = doc.length - 1; touch() }
  function duplicateSelected() { if (selected < 0) return; doc.splice(selected + 1, 0, JSON.parse(JSON.stringify(doc[selected]))); selected += 1; touch() }
  function moveSelected(dir) { if (selected < 0) return; selected = Model.moveEntry(doc, selected, dir); touch() }
  function toggleEnabled(i) { var e = doc[i]; Model.setValue(e, "enabled", e.enabled === false, registry); touch() }
  function setField(key, value) { if (!selectedEntry) return; Model.setValue(doc[selected], key, value, registry); touch() }
  function revert() { loadFromService(); statusText = "reverted to the saved file" }
  function initExample() { if (!initProc.running) { statusText = "writing the example layout…"; initProc.running = true } }

  // ---- presets: listed by the CLI on open, applied through the CLI (one writer); the panel then follows the file.
  property var presets: []
  function refreshPresets() { if (!presetList.running) presetList.running = true }
  function applyPreset(name) {
    if (!name || presetApply.running) return
    if (dirty) { statusText = "save or revert first, then apply a preset"; return }
    presetApply.presetName = String(name)
    statusText = "applying preset " + name + "…"
    presetApply.running = true
  }
  Process {
    id: presetList
    command: [root.cliPath, "preset", "list", "--json"]
    stdout: StdioCollector { id: presetOut }
    onExited: function(code) {
      var list = []
      try { list = JSON.parse(String(presetOut.text || "{}")).presets || [] } catch (e) {}
      root.presets = list
    }
  }
  Process {
    id: presetApply
    property string presetName: ""
    command: [root.cliPath, "preset", "apply", presetName]
    stderr: StdioCollector { id: presetErr }
    onExited: function(code) {
      root.statusText = code === 0 ? "applied preset " + presetApply.presetName + " (previous layout in desktop-widgets.json.bak)"
                                   : "ERROR " + String(presetErr.text || "").trim().split("\n")[0]
      if (code === 0) Qt.callLater(root.loadFromService)
    }
  }
  Process {
    id: initProc
    command: [root.cliPath, "init", "--force"]
    onExited: function(code) { root.statusText = code === 0 ? "example layout written" : "ERROR init failed (" + code + ")"; if (code === 0) Qt.callLater(root.loadFromService) }
  }

  // `omarchy-shell shell call homelab.desktop-widgets call '{"op":"add","type":"clock"}'`
  // ops: select{index} add{type} remove duplicate move{dir} set{key,value} toggleEnabled{index} save saveClose revert applyOnChange{value} preset{name} presets state
  function call(arg) {
    var c
    try { c = JSON.parse(String(arg || "{}")) } catch (e) { return "bad json" }
    switch (String(c.op || "")) {
      case "select": selected = Number(c.index); return "ok"
      case "add": if (!registry || !registry.types[c.type]) return "unknown type"; addWidget(String(c.type)); return "ok"
      case "remove": removeSelected(); return "ok"
      case "duplicate": duplicateSelected(); return "ok"
      case "move": moveSelected(Number(c.dir) || 1); return "ok"
      case "set": setField(String(c.key), c.value); return "ok"
      case "toggleEnabled": toggleEnabled(Number(c.index)); return "ok"
      case "save": save(); return "ok"
      case "saveClose": saveAndClose(); return "ok"
      case "revert": revert(); return "ok"
      case "applyOnChange": applyOnChange = c.value === true; return "ok"
      case "arrange": if (!service) return "no service"; service.setArranging(c.value !== false); dismiss(); return "ok"
      case "init": initExample(); return "ok"
      case "preset": applyPreset(String(c.name || "")); return "ok"
      case "presets": return JSON.stringify(presets.map(function(p) { return p.name }))
      case "grid": if (!service) return "no service"; service.setGrid(c.enabled !== false, c.size || service.grid.size); return "ok"
      case "state": return JSON.stringify({ selected: selected, dirty: dirty, saving: saving, status: statusText, count: doc.length, applyOnChange: applyOnChange, presets: presets.length, opened: opened, savedAt: savedAt })
      default: return "unknown op"
    }
  }
  property bool closeAfterSave: false
  property bool savedFlash: false     // brief accent-coloured confirmation after a successful save
  property string savedAt: ""
  function save() {
    if (saving) { saveTimer.restart(); return }
    saving = true
    savedFlash = false
    statusText = "saving…"
    writer.running = true
  }
  function saveAndClose() {
    if (!dirty) { close(); return }
    closeAfterSave = true
    save()
  }
  Timer { id: flashTimer; interval: 2500; onTriggered: root.savedFlash = false }

  Timer { id: saveTimer; interval: 250; onTriggered: root.save() }

  // Follow the file when it changes underneath us (init, CLI, arrange mode)
  // unless there are unsaved edits waiting for Save.
  Connections {
    target: root.service
    function onRawWidgetsChanged() { if (root.opened && (!root.dirty || root.applyOnChange) && !root.saving) root.loadFromService() }
  }

  Process {
    id: writer
    command: [root.cliPath, "write"]
    stdinEnabled: true
    onStarted: {
      writer.write(JSON.stringify({ version: 1, widgets: root.doc }, null, 2) + "\n")
      writer.stdinEnabled = false
    }
    stderr: StdioCollector { id: writerErr }
    onExited: function(code) {
      root.saving = false
      writer.stdinEnabled = true
      if (code === 0) {
        root.saved = JSON.parse(JSON.stringify(root.doc))
        root.savedAt = Qt.formatTime(new Date(), "HH:mm:ss")
        root.statusText = "✓ Saved " + root.savedAt + " — " + root.doc.length + " widget" + (root.doc.length === 1 ? "" : "s") + " written to desktop-widgets.json"
        root.savedFlash = true; flashTimer.restart()
        if (root.closeAfterSave) { root.closeAfterSave = false; root.close() }
      } else {
        root.closeAfterSave = false
        root.statusText = "ERROR " + (String(writerErr.text || "").trim().split("\n")[0].replace(/^ERROR\s+/, "") || ("write failed (" + code + ")"))
      }
    }
  }

  // ---- window
  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "homelab-desktop-widgets-editor"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Util.alpha(Color.background, 0.55) }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      anchors.centerIn: parent
      color: Color.popups.background
      borderSpec: root.borderSpec
      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        anchors.margins: root.pad
        focus: true
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (root.confirmOpen) { if (discardConfirm.handleKey(event)) event.accepted = true; return }
          if (event.key === Qt.Key_Escape) { root.dismiss(); event.accepted = true }
          else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier)) { root.saveAndClose(); event.accepted = true }
          else if (event.key === Qt.Key_S && (event.modifiers & Qt.ControlModifier)) { if (root.dirty) root.save(); event.accepted = true }
          else if (event.key === Qt.Key_J || event.key === Qt.Key_Down) { if (root.selected < root.doc.length - 1) root.selected += 1; event.accepted = true }
          else if (event.key === Qt.Key_K || event.key === Qt.Key_Up) { if (root.selected > 0) root.selected -= 1; event.accepted = true }
        }

        ColumnLayout {
          anchors.fill: parent
          spacing: Style.spacing.lg

          RowLayout {
            Layout.fillWidth: true
            Text { text: "Desktop widgets"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.title; font.weight: Font.DemiBold }
            Text { visible: !root.service; text: "· plugin service not running"; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.body }
            Button { visible: !root.service; text: "Enable plugin"; bordered: true; onClicked: Quickshell.execDetached(["omarchy", "plugin", "enable", "homelab.desktop-widgets"]) }
            Item { Layout.fillWidth: true }
            Button { text: "Arrange on desktop"; iconText: "󰆾"; bordered: true; tooltipText: "Drag widgets into place; Esc finishes"; enabled: !!root.service; onClicked: { root.service.setArranging(true); root.dismiss() } }
            Button {
              readonly property var g: root.service ? root.service.grid : { enabled: false, size: 24 }
              text: "Grid " + (g.enabled ? g.size + "px" : "off"); iconText: "󰝘"; bordered: true; selected: g.enabled
              tooltipText: "Snap dragged widgets to a grid (click: on/off · right-click: bigger · middle: smaller). `desktop-widgets grid <px>` sets any size"
              enabled: !!root.service
              onClicked: root.service.setGrid(!g.enabled, g.size)
              MouseArea { anchors.fill: parent; acceptedButtons: Qt.RightButton | Qt.MiddleButton
                onClicked: function(m) { var g = root.service.grid; root.service.setGrid(true, m.button === Qt.RightButton ? Math.min(256, g.size * 2) : Math.max(4, g.size / 2)) } }
            }
            Text { text: "j/k select · ctrl+s save · esc closes"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
          }

          RowLayout {
            Layout.fillWidth: true; Layout.fillHeight: true
            spacing: Style.spacing.xl

            ColumnLayout {
              Layout.preferredWidth: Style.space(300); Layout.maximumWidth: Style.space(300); Layout.fillWidth: false; Layout.fillHeight: true
              spacing: Style.spacing.sm
              ListView {
                id: list
                Layout.fillWidth: true; Layout.fillHeight: true
                clip: true
                model: root.doc
                spacing: Style.spacing.xs
                delegate: Rectangle {
                  required property var modelData
                  required property int index
                  width: ListView.view.width
                  height: Style.spacing.controlHeight
                  radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
                  color: index === root.selected ? Color.menu.selectedBackground : "transparent"
                  MouseArea { anchors.fill: parent; onClicked: root.selected = index }
                  RowLayout {
                    anchors.fill: parent; anchors.leftMargin: Style.spacing.sm; anchors.rightMargin: Style.spacing.sm
                    spacing: Style.spacing.sm
                    Text {
                      text: modelData.enabled === false ? "○" : "●"
                      color: modelData.enabled === false ? Color.muted : Color.accent
                      font.pixelSize: Style.font.body
                      MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.toggleEnabled(index) }
                    }
                    Text { text: Model.entryLabel(modelData, root.registry); color: index === root.selected ? Color.menu.selectedText : Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { visible: Number(modelData.z || 0) !== 0; text: "z " + Number(modelData.z || 0); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    Text { text: String(modelData.corner || "top-right"); color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                    Text { visible: Model.firstError(root.messages, index) !== ""; text: "⚠"; color: Color.urgent; font.pixelSize: Style.font.body }
                  }
                }
              }
              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.spacing.sm
                RowLayout {
                  spacing: Style.spacing.sm
                  Dropdown {
                    id: addType
                    showLabel: false
                    implicitWidth: Style.space(150)
                    value: ""
                    options: {
                      var o = [{ value: "", label: "+ Add…" }]
                      var t = root.registry ? root.registry.types : {}
                      for (var k in t) o.push({ value: k, label: t[k].displayName || k })
                      return o
                    }
                    onChanged: function(v) { if (v) { root.addWidget(v); addType.value = "" } }
                  }
                  Button { text: "↑"; bordered: true; tooltipText: "Move up"; enabled: root.selected > 0; onClicked: root.moveSelected(-1) }
                  Button { text: "↓"; bordered: true; tooltipText: "Move down"; enabled: !!root.selectedEntry && root.selected < root.doc.length - 1; onClicked: root.moveSelected(1) }
                }
                RowLayout {
                  spacing: Style.spacing.sm
                  Button { text: "Duplicate"; bordered: true; enabled: !!root.selectedEntry; onClicked: root.duplicateSelected() }
                  Button { text: "Remove"; bordered: true; enabled: !!root.selectedEntry; onClicked: root.removeSelected() }
                }
                RowLayout {
                  spacing: Style.spacing.sm
                  Dropdown {
                    id: presetPick
                    showLabel: false
                    implicitWidth: Style.space(150)
                    enabled: !root.dirty && !presetApply.running
                    value: ""
                    options: {
                      var o = [{ value: "", label: root.dirty ? "Presets (save first)" : "Presets…" }]
                      for (var i = 0; i < root.presets.length; i++) {
                        var p = root.presets[i]
                        if (p.valid === false) continue
                        o.push({ value: p.name, label: p.name + " · " + p.widgets + (p.origin === "user" ? " · yours" : "") })
                      }
                      return o
                    }
                    onChanged: function(v) { if (v) { root.applyPreset(v); presetPick.value = "" } }
                  }
                  Text { text: "replaces the layout; `desktop-widgets preset save <name>` keeps yours"; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                }
              }
            }

            Rectangle { width: 1; Layout.fillHeight: true; color: Util.alpha(Color.popups.border, 0.35) }

            Item {
              Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumWidth: Style.space(360)
              EditorForm {
                anchors.fill: parent
                visible: root.doc.length > 0
                entry: root.selectedEntry
                registry: root.registry
                looks: root.selectedEntry && String(root.selectedEntry.type) === "pet" && root.service && root.service.petStates[Pet.petName(root.selectedEntry)] ? (root.service.petStates[Pet.petName(root.selectedEntry)].looks || null) : null
                publishedName: root.selected >= 0 ? (root.publishedNames[root.selected] || "") : ""
                onEdited: function(key, value) { root.setField(key, value) }
              }
              ColumnLayout {
                visible: root.doc.length === 0
                anchors.centerIn: parent
                spacing: Style.spacing.md
                Text { text: "No widgets yet."; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.title; Layout.alignment: Qt.AlignHCenter }
                Text { text: "Start from the example layout (clock, stats, uptime, Claude session, load), or add one on the left."; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.body; Layout.alignment: Qt.AlignHCenter }
                Button { text: "Start with the example layout"; bordered: true; selected: true; Layout.alignment: Qt.AlignHCenter; onClicked: root.initExample() }
              }
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md
            ToggleSwitch { checked: root.applyOnChange; onToggled: { root.applyOnChange = !root.applyOnChange; if (root.applyOnChange && root.dirty) root.save() } }
            Text { text: "Apply on change"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
            Text {
              Layout.fillWidth: true
              readonly property string err: root.selectedEntry ? Model.firstError(root.messages, root.selected) : ""
              text: err !== "" ? "⚠ widget " + root.selected + ": " + err : root.statusText
              color: err !== "" || root.statusText.indexOf("ERROR") === 0 ? Color.urgent : (root.savedFlash ? Color.accent : Color.muted)
              font.weight: root.savedFlash && err === "" ? Font.DemiBold : Font.Normal
              font.family: Style.font.family; font.pixelSize: Style.font.caption; elide: Text.ElideRight
            }
            Button { text: "Revert"; bordered: true; enabled: root.dirty; onClicked: root.revert() }
            Button { text: root.savedFlash && !root.dirty ? "Saved ✓" : "Save"; bordered: true; selected: root.dirty || root.savedFlash; enabled: root.dirty && !root.saving; tooltipText: "Ctrl+S"; onClicked: root.save() }
            Button { text: "Save & close"; bordered: true; enabled: !root.saving; tooltipText: "Ctrl+Shift+S — saves if needed, then closes"; onClicked: root.saveAndClose() }
          }
        }

        ConfirmDialog {
          id: discardConfirm
          anchors.fill: parent
          anchors.margins: -root.pad
          z: 10
          opened: root.confirmOpen
          message: "Discard unsaved changes?"
          confirmText: "Discard"
          onCanceled: root.confirmOpen = false
          onConfirmed: { root.confirmOpen = false; root.doc = JSON.parse(JSON.stringify(root.saved)); root.dismiss() }
        }
      }
    }
  }
}
