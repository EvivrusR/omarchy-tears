import QtQuick
import Quickshell.Io
import qs.Commons

// Runs a shell command on an interval and shows its stdout.
WidgetCard {
  id: root
  readonly property string command: String(config.command || "")
  readonly property string title: String(config.title || "")
  readonly property int intervalSec: Math.max(1, parseInt(config.intervalSec) || 60)
  readonly property int timeoutSec: Math.max(1, parseInt(config.timeoutSec) || 10)
  readonly property int maxLines: Math.max(1, parseInt(config.maxLines) || 8)
  readonly property int maxWidth: Math.round(Number(config.maxWidth || 420) * scale_)

  property string output: ""
  property bool failed: false

  function clip(text) {
    var lines = String(text || "").replace(/\s+$/, "").split("\n")
    if (lines.length > maxLines) lines = lines.slice(0, maxLines)
    return lines.join("\n")
  }

  Process {
    id: proc
    command: ["bash", "-lc", "timeout " + root.timeoutSec + "s bash -lc " + Util.shellQuote(root.command)]
    stdout: StdioCollector { id: out }
    onExited: function(code) {
      root.failed = code !== 0
      if (code === 0 || root.output === "") root.output = root.clip(out.text)
    }
  }

  Timer {
    interval: root.intervalSec * 1000; running: root.command !== ""; repeat: true; triggeredOnStart: true
    onTriggered: if (!proc.running) proc.running = true
  }

  Column {
    spacing: Math.round(Style.space(4) * root.scale_)
    Row {
      visible: root.title !== ""
      spacing: Math.round(Style.space(6) * root.scale_)
      WidgetText {
        outlineColor: root.outlineColor; halo: root.halo
        text: root.title
        color: root.mutedColor
        font.family: Style.font.resolvedFamily
        font.pixelSize: Math.round(Style.font.caption * root.scale_)
        font.letterSpacing: 1
      }
      WidgetText {
        outlineColor: root.outlineColor; halo: root.halo
        visible: root.failed
        text: "!"
        color: Color.urgent
        font.family: Style.font.resolvedFamily
        font.pixelSize: Math.round(Style.font.caption * root.scale_)
      }
    }
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: root.command === "" ? "no command configured" : (root.output === "" ? "…" : root.output)
      color: root.textColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.body * root.scale_)
      width: Math.min(implicitWidth, root.maxWidth)
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
      maximumLineCount: root.maxLines
    }
  }
}
