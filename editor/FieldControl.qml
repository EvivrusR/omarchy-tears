import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// One registry field → one control. `value` is the effective value (entry
// value or registry default); edits are reported via edited(), never applied
// locally, so the panel's doc stays the single source of truth.
RowLayout {
  id: root
  property var field: ({})
  property var value
  signal edited(string key, var value)
  spacing: Style.spacing.md
  readonly property string kind: String(field.type || "string")

  ColumnLayout {
    Layout.preferredWidth: Style.space(190)
    Layout.minimumWidth: Style.space(190)
    Layout.maximumWidth: Style.space(190)
    Layout.alignment: Qt.AlignTop
    spacing: 0
    Text { text: root.field.label || root.field.key; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body; elide: Text.ElideRight; Layout.fillWidth: true }
    Text { visible: !!root.field.description; text: root.field.description || ""; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; Layout.fillWidth: true }
  }

  Loader {
    id: control
    readonly property bool wide: root.kind === "string" || root.kind === "path" || root.kind === "command" || root.kind === "color" || root.kind === "multi-enum" || root.kind === "rows" || root.kind === "apps" || root.kind === "text"
    Layout.fillWidth: wide
    Layout.alignment: Qt.AlignVCenter
    sourceComponent: {
      switch (root.kind) {
        case "boolean": return boolComp
        case "integer": return intComp
        case "number": return numberComp
        case "enum": return root.field.key === "corner" ? cornerComp : enumComp
        case "multi-enum": return multiComp
        case "apps": return appsComp
        case "text": return multilineComp
        case "rows": return rowsComp
        default: return textComp
      }
    }
  }

  Item { visible: !control.wide; Layout.fillWidth: true }

  Component {
    id: boolComp
    Item {
      implicitHeight: sw.implicitHeight; implicitWidth: sw.implicitWidth
      ToggleSwitch { id: sw; checked: root.value === true; onToggled: root.edited(root.field.key, !(root.value === true)) }
    }
  }
  Component {
    id: intComp
    NumberField {
      value: Number(root.value || 0)
      from: root.field.min !== undefined ? root.field.min : -100000
      to: root.field.max !== undefined ? root.field.max : 100000
      stepSize: 1
      onModified: function(v) { root.edited(root.field.key, v) }
    }
  }
  Component {
    id: numberComp
    TextField {
      implicitWidth: Style.spacing.numberFieldWidth
      text: String(root.value === undefined ? "" : root.value)
      onEditingFinished: { var v = parseFloat(text); if (!isNaN(v) && v !== Number(root.value)) root.edited(root.field.key, v) }
      Keys.onEscapePressed: function(e) { focus = false; e.accepted = true }
    }
  }
  Component {
    id: cornerComp
    ButtonGroup {
      value: String(root.value || "top-right")
      options: [{ value: "top-left", label: "TL" }, { value: "top-right", label: "TR" }, { value: "bottom-left", label: "BL" }, { value: "bottom-right", label: "BR" }]
      onChanged: function(v) { root.edited(root.field.key, v) }
    }
  }
  Component {
    id: enumComp
    Dropdown {
      showLabel: false
      value: String(root.value || "")
      options: (root.field.options || []).map(function(o) { return { value: o, label: o } })
      onChanged: function(v) { root.edited(root.field.key, v) }
    }
  }
  Component {
    id: multiComp
    MultiSelect {
      showLabel: false
      values: Array.isArray(root.value) ? root.value : []
      options: (root.field.options || []).map(function(o) { return { value: o, label: o } })
      onChanged: function(vals) { root.edited(root.field.key, vals) }
    }
  }

  // text: a multi-line, monospace box (ASCII art); commits when focus leaves.
  Component {
    id: multilineComp
    Rectangle {
      implicitHeight: Math.max(Style.space(120), edit.contentHeight + Style.spacing.inputPaddingY * 2 + Style.space(8))
      radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
      color: Util.alpha(Color.popups.background, 0.6)
      border.width: 1; border.color: edit.activeFocus ? Color.accent : Util.alpha(Color.popups.text, 0.3)
      Flickable {
        anchors.fill: parent; anchors.margins: Style.spacing.inputPaddingY
        contentWidth: width; contentHeight: edit.contentHeight
        clip: true; boundsBehavior: Flickable.StopAtBounds
        TextEdit {
          id: edit
          width: parent.width
          text: String(root.value === undefined ? "" : root.value)
          color: Color.popups.text; selectionColor: Util.alpha(Color.accent, 0.5)
          font.family: "monospace"; font.pixelSize: Style.font.body
          wrapMode: TextEdit.NoWrap
          selectByMouse: true
          property string committed: text
          onActiveFocusChanged: if (!activeFocus && text !== committed) { committed = text; root.edited(root.field.key, text) }
          Keys.onEscapePressed: function(e) { focus = false; e.accepted = true }
        }
      }
      Text { visible: edit.text === ""; anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Style.spacing.inputPaddingY; text: "paste ASCII art…"; color: Color.muted; font.family: "monospace"; font.pixelSize: Style.font.body }
    }
  }

  // apps: the same desktop entries the Apps menu shows (minus Omarchy's hide list).
  property var hides: ({})
  FileView { path: "/usr/share/omarchy/default/omarchy/launcher.hides"; blockLoading: false; printErrors: false
    onLoaded: { var h = {}; String(text()).split("\n").forEach(function(l) { l = l.trim(); if (l && l[0] !== "#") h[l] = true }); root.hides = h } }
  Component {
    id: appsComp
    MultiSelect {
      showLabel: false
      placeholderText: "Search apps…"
      values: Array.isArray(root.value) ? root.value : (root.value && typeof root.value.length === "number" ? Array.prototype.slice.call(root.value) : [])
      options: {
        var out = []
        var list = DesktopEntries.applications.values || []
        for (var i = 0; i < list.length; i++) {
          var e = list[i]
          if (e.noDisplay || root.hides[e.id]) continue
          out.push({ value: e.id, label: e.name })
        }
        out.sort(function(a, b) { return a.label.toLowerCase() < b.label.toLowerCase() ? -1 : 1 })
        return out
      }
      onChanged: function(vals) { root.edited(root.field.key, vals) }
    }
  }

  // rows: a small editor for template rows — kind dropdown + that kind's keys.
  readonly property var rowKeys: ({ heading: ["text"], text: ["text"], kv: ["label", "value"], bar: ["label", "value", "text", "max", "warnAt"], spacer: ["height"],
    when: ["if", "state", "say"], on: ["if", "state", "beat", "say"],
    range: ["signal", "min", "max", "look", "beat", "say", "and"], flag: ["signal", "is", "look", "beat", "say", "and"], keyword: ["signal", "words", "match", "look", "beat", "say", "and"], pet: ["pet", "look", "then", "beat", "say"],
    image: ["image", "z", "x", "y", "scale"], sheet: ["sheet", "z", "x", "y", "scale", "follow"], command: ["key", "command"] })
  readonly property var numericKeys: ({ warnAt: true, height: true, min: true, max: true, beat: true })
  property var rowContext: ({ looks: [], signals: [], pets: [] })
  property var warnings: []
  function hint(k) { var rf = root.field.rowFields || {}; return rf[k] || null }
  function enumFor(k, current) {
    var h = hint(k), list = []
    if (!h) return null
    if (h.options) list = h.options.slice()
    else if (h.enum === "looks") list = (root.rowContext.looks || []).slice()
    else if (h.enum === "signals") list = (root.rowContext.signals || []).slice()
    else if (h.enum === "pets") list = (root.rowContext.pets || []).slice()
    if (!list.length && !h.options) return null                       // nothing known yet: fall back to a text box
    if (current !== "" && list.indexOf(current) === -1) list.unshift(current)
    return list.map(function(o) { return { value: o, label: o } })
  }
  function newRow(kind) {
    switch (kind) {
      case "range": return { kind: "range", signal: "cpu", min: 60, look: "running" }
      case "flag": return { kind: "flag", signal: "battery.charging", is: true, look: "running" }
      case "keyword": return { kind: "keyword", signal: "claude.label", words: "", match: "any", look: "review" }
      case "pet": return { kind: "pet", pet: (root.rowContext.pets || [])[0] || "", look: "failed", then: "waving", beat: 2 }
      case "when": return { kind: "when", if: "", state: "idle" }
      case "command": return { kind: "command", key: "", command: "" }
      case "image": return { kind: "image", image: "" }
      case "sheet": return { kind: "sheet", sheet: "" }
      default: return { kind: kind, text: "" }
    }
  }
  function rowsArray() {
    var v = root.value
    var a = []
    if (v && typeof v === "object" && typeof v.length === "number") for (var i = 0; i < v.length; i++) a.push(JSON.parse(JSON.stringify(v[i])))
    return a
  }
  function emitRows(a) { root.edited(root.field.key, a) }
  Component {
    id: rowsComp
    ColumnLayout {
      spacing: Style.spacing.xs
      Repeater {
        model: root.rowsArray()
        delegate: RowLayout {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          spacing: Style.spacing.xs
          Dropdown {
            showLabel: false
            implicitWidth: Style.space(96)
            value: String(modelData.kind || "text")
            options: (root.field.options || []).map(function(o) { return { value: o, label: o } })
            onChanged: function(v) { var a = root.rowsArray(); a[index] = { kind: v }; root.emitRows(a) }
          }
          Repeater {
            model: root.rowKeys[String(modelData.kind || "text")] || ["text"]
            delegate: Loader {
              required property var modelData
              readonly property string k: String(modelData)
              readonly property var rowRef: parent.modelData
              readonly property int rowIndex: parent.index
              readonly property string current: rowRef[k] === undefined ? "" : String(rowRef[k])
              readonly property var opts: root.enumFor(k, current)
              readonly property bool isBool: (root.hint(k) || {}).type === "boolean"
              Layout.fillWidth: !opts && !isBool && (k === "text" || k === "value" || k === "label" || k === "if" || k === "words" || k === "and" || k === "command")
              Layout.preferredWidth: Layout.fillWidth ? -1 : (opts ? Style.space(120) : Style.space(64))
              function commit(v) {
                var a = root.rowsArray(); var row = a[rowIndex]
                if (v === "" || v === undefined) delete row[k]
                else if (root.numericKeys[k]) { var n = parseFloat(v); if (!isNaN(n)) row[k] = n }
                else row[k] = v
                if (JSON.stringify(a[rowIndex]) !== JSON.stringify(root.rowsArray()[rowIndex])) root.emitRows(a)
              }
              sourceComponent: isBool ? rowBool : (opts ? rowEnum : rowText)
              Component { id: rowBool; Item { implicitWidth: sw.implicitWidth + hintText.implicitWidth + Style.spacing.xs; implicitHeight: sw.implicitHeight
                RowLayout { spacing: Style.spacing.xs; Text { id: hintText; text: k; color: Color.muted; font.family: Style.font.family; font.pixelSize: Style.font.caption }
                  ToggleSwitch { id: sw; checked: rowRef[k] !== false && rowRef[k] !== "false"; onToggled: commit(!(rowRef[k] !== false && rowRef[k] !== "false")) } } } }
              Component { id: rowEnum; Dropdown { showLabel: false; value: current; options: opts; onChanged: function(v) { commit(v) } } }
              Component { id: rowText; TextField { placeholderText: k; text: current
                onEditingFinished: commit(text)
                Keys.onEscapePressed: function(e) { focus = false; e.accepted = true } } }
            }
          }
          Button { text: "↑"; bordered: true; enabled: index > 0; onClicked: { var a = root.rowsArray(); var t = a[index - 1]; a[index - 1] = a[index]; a[index] = t; root.emitRows(a) } }
          Button { text: "↓"; bordered: true; enabled: index < root.rowsArray().length - 1; onClicked: { var a = root.rowsArray(); var t = a[index + 1]; a[index + 1] = a[index]; a[index] = t; root.emitRows(a) } }
          Button { text: "✕"; bordered: true; onClicked: { var a = root.rowsArray(); a.splice(index, 1); root.emitRows(a) } }
        }
      }
      Repeater {
        model: root.warnings
        delegate: Text { required property var modelData; text: "row " + modelData.row + ": " + modelData.message; color: Color.urgent; font.family: Style.font.family; font.pixelSize: Style.font.caption; wrapMode: Text.WordWrap; Layout.fillWidth: true }
      }
      RowLayout {
        spacing: Style.spacing.xs
        Repeater {
          model: (root.field.options || []).indexOf("range") !== -1 ? ["range", "flag", "keyword", "pet", "when"] : [String((root.field.options || [])[0] || "text")]
          delegate: Button {
            required property var modelData
            text: "+ " + modelData; bordered: true
            onClicked: { var a = root.rowsArray(); a.push(root.newRow(String(modelData))); root.emitRows(a) }
          }
        }
      }
    }
  }
  Component {
    id: textComp
    RowLayout {
      spacing: Style.spacing.sm
      Rectangle {
        visible: root.kind === "color"
        width: Style.space(16); height: width; radius: width / 2
        color: {
          if (root.kind !== "color") return "transparent"
          var v = String(root.value || "")
          var tok = { foreground: Color.foreground, background: Color.background, accent: Color.accent, muted: Color.muted, urgent: Color.urgent }
          if (tok[v] !== undefined) return tok[v]
          var c = Qt.color(v || "transparent")
          return c.valid === false ? "transparent" : c
        }
        border.width: 1; border.color: Util.alpha(Color.popups.text, 0.3)
      }
      TextField {
        Layout.fillWidth: true
        text: String(root.value === undefined ? "" : root.value)
        onEditingFinished: if (text !== String(root.value === undefined ? "" : root.value)) root.edited(root.field.key, text)
        Keys.onEscapePressed: function(e) { focus = false; e.accepted = true }
      }
    }
  }
}
