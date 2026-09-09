import QtQuick
import Quickshell.Io
import qs.Commons
import "Template.js" as Template

// Rows rendered from a command's JSON output. No code needed: describe the
// rows in the config, use {placeholders} (see Template.js for filters).
WidgetCard {
  id: root
  readonly property string command: String(config.command || "")
  readonly property int intervalSec: Math.max(1, parseInt(config.intervalSec) || 60)
  readonly property int timeoutSec: Math.max(1, parseInt(config.timeoutSec) || 10)
  readonly property int maxWidth: Math.round(Number(config.maxWidth || 420) * scale_)
  readonly property var rows: listOf(config.rows) || []
  readonly property int barWidth: Math.round(Style.space(120) * scale_)

  property var data: ({ output: "", lines: [] })
  property bool haveData: false
  property bool failed: false

  Process {
    id: proc
    command: ["bash", "-lc", "timeout " + root.timeoutSec + "s bash -lc " + Util.shellQuote(root.command)]
    stdout: StdioCollector { id: out }
    onExited: function(code) {
      root.failed = code !== 0
      if (code === 0 || !root.haveData) { root.data = Template.parseOutput(out.text); root.haveData = true }
    }
  }
  Timer {
    interval: root.intervalSec * 1000; running: root.command !== ""; repeat: true; triggeredOnStart: true
    onTriggered: if (!proc.running) proc.running = true
  }

  function txt(v) { return Template.render(v, root.data) }

  Column {
    spacing: Math.round(Style.space(4) * root.scale_)

    WidgetText {
      visible: root.command === "" || root.rows.length === 0
      outlineColor: root.outlineColor; halo: root.halo
      text: root.command === "" ? "template: no command" : "template: no rows"
      color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_)
    }

    Repeater {
      model: root.rows
      delegate: Loader {
        required property var modelData
        required property int index
        readonly property string kind: String(modelData.kind || "text")
        sourceComponent: kind === "heading" ? headingComp : kind === "kv" ? kvComp : kind === "bar" ? barComp : kind === "spacer" ? spacerComp : textComp
        property var row: modelData
      }
    }
  }

  Component {
    id: headingComp
    Row {
      spacing: Math.round(Style.space(6) * root.scale_)
      WidgetText {
        outlineColor: root.outlineColor; halo: root.halo
        text: root.txt(row.text)
        color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_); font.letterSpacing: 1
      }
      WidgetText { visible: root.failed && index === 0; outlineColor: root.outlineColor; halo: root.halo; text: "!"; color: Color.urgent; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_) }
    }
  }
  Component {
    id: textComp
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: root.txt(row.text)
      color: root.textColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_)
      width: Math.min(implicitWidth, root.maxWidth); elide: Text.ElideRight
    }
  }
  Component {
    id: kvComp
    Row {
      spacing: Math.round(Style.space(10) * root.scale_)
      WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: root.txt(row.label); color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_); width: Math.max(implicitWidth, Math.round(Style.space(Number(row.labelWidth || 0)) * root.scale_)) }
      WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: root.txt(row.value); color: root.textColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_) }
    }
  }
  Component {
    id: barComp
    Row {
      spacing: Math.round(Style.space(8) * root.scale_)
      readonly property real frac: Template.barFraction(row, root.data)
      readonly property real warnAt: row.warnAt !== undefined ? Number(row.warnAt) : 0.9
      WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: root.txt(row.label); color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_); width: Math.max(implicitWidth, Math.round(Style.space(Number(row.labelWidth || 40)) * root.scale_)); anchors.verticalCenter: parent.verticalCenter }
      Rectangle {
        width: root.barWidth; height: Math.max(3, Math.round(Style.space(5) * root.scale_)); radius: height / 2
        color: root.outlineColor.a > 0 ? Util.alpha(root.outlineColor, 0.25) : Util.alpha(root.textColor, 0.15)
        border.width: root.outlineColor.a > 0 ? 1 : 0; border.color: Util.alpha(root.outlineColor, 0.85)
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          width: parent.parent.frac < 0 ? 0 : parent.width * parent.parent.frac; height: parent.height; radius: parent.radius
          color: parent.parent.frac >= parent.parent.warnAt ? Color.urgent : root.textColor
          Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
        }
      }
      WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: root.txt(row.text !== undefined ? row.text : row.value) + String(row.suffix || ""); color: root.textColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_); anchors.verticalCenter: parent.verticalCenter }
    }
  }
  Component {
    id: spacerComp
    Item { width: 1; height: Math.round(Number(row.height !== undefined ? row.height : 6) * root.scale_) }
  }
}
