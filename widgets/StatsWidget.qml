import QtQuick
import Quickshell.Io
import qs.Commons
import "Stats.js" as Stats

WidgetCard {
  id: root
  readonly property var show: listOf(config.show) || ["cpu", "mem", "disk", "battery"]
  readonly property int intervalSec: Math.max(1, parseInt(config.intervalSec) || 3)
  readonly property string diskPath: String(config.diskPath || "/")
  readonly property int barWidth: Math.round(Style.space(120) * scale_)

  property var prevCpu: null
  property var cpu: null
  property var mem: null
  property var disk: null
  property var batt: null

  function ingest(text) {
    var s = Stats.parseSample(text)
    if (s.cpu) { cpu = Stats.cpuPercent(prevCpu, s.cpu); prevCpu = s.cpu }
    mem = Stats.memPercent(s.mem)
    disk = s.disk
    batt = s.batt
  }

  readonly property var rows: {
    var out = []
    for (var i = 0; i < show.length; i++) {
      switch (String(show[i])) {
        case "cpu": out.push({ label: "cpu", pct: cpu, text: cpu === null ? "…" : cpu + "%" }); break
        case "mem": out.push({ label: "mem", pct: mem, text: mem === null ? "…" : mem + "%" }); break
        case "disk": out.push({ label: "disk", pct: disk, text: disk === null ? "…" : disk + "%" }); break
        case "battery":
          if (batt) out.push({ label: "batt", pct: batt.pct, text: Stats.batteryLabel(batt) })
          break
      }
    }
    return out
  }

  Process {
    id: sampler
    command: ["bash", "-c",
      "head -1 /proc/stat; " +
      "awk '/^MemTotal/{t=$2} /^MemAvailable/{a=$2} END{print \"mem\", t, a}' /proc/meminfo; " +
      "echo disk $(df --output=pcent " + Util.shellQuote(root.diskPath) + " 2>/dev/null | tail -1); " +
      "for b in /sys/class/power_supply/BAT*; do [ -r \"$b/capacity\" ] && echo batt $(cat \"$b/capacity\") $(cat \"$b/status\") && break; done; true"]
    stdout: StdioCollector { onStreamFinished: root.ingest(text) }
  }

  Timer {
    interval: root.intervalSec * 1000; running: true; repeat: true; triggeredOnStart: true
    onTriggered: if (!sampler.running) sampler.running = true
  }

  Column {
    spacing: Math.round(Style.space(6) * root.scale_)
    Repeater {
      model: root.rows
      Row {
        required property var modelData
        spacing: Math.round(Style.space(8) * root.scale_)
        WidgetText {
          outlineColor: root.outlineColor; halo: root.halo
          width: Math.round(Style.space(40) * root.scale_)
          text: modelData.label
          color: root.mutedColor
          font.family: Style.font.resolvedFamily
          font.pixelSize: Math.round(Style.font.body * root.scale_)
          anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
          width: root.barWidth
          height: Math.max(3, Math.round(Style.space(5) * root.scale_))
          radius: height / 2
          color: root.outlineColor.a > 0 ? Util.alpha(root.outlineColor, 0.25) : Util.alpha(root.textColor, 0.15)
          border.width: root.outlineColor.a > 0 ? 1 : 0
          border.color: Util.alpha(root.outlineColor, 0.85)
          anchors.verticalCenter: parent.verticalCenter
          Rectangle {
            width: modelData.pct === null ? 0 : parent.width * modelData.pct / 100
            height: parent.height
            radius: parent.radius
            color: modelData.pct !== null && modelData.pct >= 90 ? Color.urgent : root.textColor
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
          }
        }
        WidgetText {
          outlineColor: root.outlineColor; halo: root.halo
          width: Math.round(Style.space(40) * root.scale_)
          text: modelData.text
          color: root.textColor
          font.family: Style.font.resolvedFamily
          font.pixelSize: Math.round(Style.font.body * root.scale_)
          horizontalAlignment: Text.AlignRight
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }
  }
}
