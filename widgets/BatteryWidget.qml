import QtQuick
import Quickshell.Io
import qs.Commons
import "Monitor.js" as Monitor

// Battery: glyph + percent + time to empty/full, from bin/dw-sample.
WidgetCard {
  id: root
  readonly property string style_: String(config.style || "outline")
  readonly property bool showPercent: config.showPercent !== false
  readonly property bool showTime: config.showTime !== false
  readonly property int warnAt: Number(config.warnAt !== undefined ? config.warnAt : 20)
  readonly property int intervalSec: Math.max(5, parseInt(config.intervalSec) || 30)
  property var batt: null
  property bool sampled: false

  readonly property bool charging: !!batt && (batt.status === "Charging" || batt.status === "Full")
  readonly property bool low: !!batt && !charging && batt.pct <= warnAt
  readonly property color glyphColor: low ? Color.urgent : root.textColor
  readonly property string timeText: {
    if (!batt || batt.hours === null || batt.hours === undefined || batt.hours > 48) return batt && batt.status === "Full" ? "full" : ""
    return Monitor.fmtHours(batt.hours) + (charging ? " to full" : " left")
  }

  Process {
    id: sampler
    command: [String(Qt.resolvedUrl("../bin/dw-sample")).replace(/^file:\/\//, "")]
    stdout: StdioCollector { onStreamFinished: { try { root.batt = JSON.parse(text).battery } catch (e) { root.batt = null } root.sampled = true } }
  }
  Timer { interval: root.intervalSec * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!sampler.running) sampler.running = true }

  Row {
    spacing: Math.round(Style.space(10) * root.scale_)
    visible: !!root.batt || !root.sampled
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: root.batt ? Monitor.batteryGlyph(root.batt.pct, root.charging, root.style_) : "…"
      color: root.glyphColor
      font.family: root.style_ === "pixel" ? "monospace" : Style.font.resolvedFamily
      font.pixelSize: Math.round((root.style_ === "outline" ? Style.font.displayLarge * 1.6 : Style.font.heading * 1.2) * root.scale_)
      anchors.verticalCenter: parent.verticalCenter
    }
    Column {
      visible: root.style_ !== "text"
      anchors.verticalCenter: parent.verticalCenter
      spacing: Math.round(Style.space(2) * root.scale_)
      WidgetText {
        visible: root.showPercent
        outlineColor: root.outlineColor; halo: root.halo
        text: root.batt ? root.batt.pct + "%" : ""
        color: root.glyphColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.heading * root.scale_); font.weight: Font.DemiBold
      }
      WidgetText {
        visible: root.showTime && root.timeText !== ""
        outlineColor: root.outlineColor; halo: root.halo
        text: root.timeText
        color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_)
      }
    }
    WidgetText {
      visible: root.style_ === "text" && root.showTime && root.timeText !== ""
      anchors.verticalCenter: parent.verticalCenter
      outlineColor: root.outlineColor; halo: root.halo
      text: root.timeText; color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_)
    }
  }
}
