import QtQuick
import Quickshell.Io
import qs.Commons

// fastfetch-style block: logo / your own ASCII art beside a key: value table.
WidgetCard {
  id: root
  readonly property string logoChoice: String(config.logo === undefined ? "omarchy" : config.logo)
  readonly property bool custom: logoChoice === "custom"
  readonly property string customArt: custom ? String(config.art || "") : ""
  readonly property string artFile: custom ? String(config.artFile || "") : ""
  readonly property string logo: custom ? (String(config.logoName || "").trim() || "none") : logoChoice
  readonly property bool above: String(config.logoPosition || "left") === "above"
  readonly property color logoColor: resolveColor(config.logoColor || "accent", Color.accent)
  readonly property var fields: listOf(config.fields) || ["os", "kernel", "uptime", "packages", "shell", "wm", "cpu", "memory", "disk"]
  readonly property bool showTitle: config.title !== false
  readonly property bool swatches: config.swatches !== false
  readonly property int intervalSec: Math.max(10, parseInt(config.intervalSec) || 60)
  property var info: ({})
  property string fileArt: ""

  readonly property var artLines: {
    if (customArt !== "") return customArt.split("\n")
    if (fileArt !== "") return fileArt.replace(/\s+$/, "").split("\n")
    return info.logo || []
  }
  readonly property var rows: {
    var labels = { os: "OS", host: "Host", kernel: "Kernel", uptime: "Uptime", packages: "Packages", shell: "Shell", wm: "WM", cpu: "CPU", gpu: "GPU", memory: "Memory", disk: "Disk", ip: "IP", battery: "Battery" }
    var out = []
    for (var i = 0; i < fields.length; i++) {
      var k = String(fields[i]), v = info[k]
      if (v !== undefined && v !== null && String(v) !== "") out.push({ label: labels[k] || k, value: String(v) })
    }
    return out
  }

  Process {
    id: fetcher
    command: [String(Qt.resolvedUrl("../bin/dw-sysinfo")).replace(/^file:\/\//, ""), "--logo", root.customArt !== "" || root.artFile !== "" ? "none" : root.logo]
    stdout: StdioCollector { onStreamFinished: { try { root.info = JSON.parse(text) } catch (e) { root.info = { error: String(e) } } } }
  }
  Timer { interval: root.intervalSec * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!fetcher.running) fetcher.running = true }
  FileView { path: root.artFile; blockLoading: false; printErrors: false; onLoaded: root.fileArt = text(); onLoadFailed: root.fileArt = "" }

  readonly property int fontPx: Math.round(Style.font.body * root.scale_)

  Grid {
    columns: root.above ? 1 : 2
    rows: root.above ? 2 : 1
    columnSpacing: Math.round(Style.space(16) * root.scale_)
    rowSpacing: Math.round(Style.space(8) * root.scale_)
    verticalItemAlignment: Grid.AlignTop

    WidgetText {
      visible: root.artLines.length > 0
      outlineColor: root.outlineColor; halo: root.halo
      text: root.artLines.join("\n")
      color: root.logoColor
      font.family: "monospace"; font.pixelSize: root.fontPx
      lineHeight: 1.0
    }

    Column {
      spacing: Math.round(Style.space(2) * root.scale_)
      WidgetText {
        visible: root.showTitle
        outlineColor: root.outlineColor; halo: root.halo
        text: (root.info.user || "") + "@" + (root.info.host || "")
        color: root.logoColor; font.family: Style.font.resolvedFamily; font.pixelSize: root.fontPx; font.weight: Font.DemiBold
      }
      WidgetText {
        visible: root.showTitle
        outlineColor: root.outlineColor; halo: root.halo
        text: { var n = ((root.info.user || "") + "@" + (root.info.host || "")).length; var s = ""; for (var i = 0; i < Math.max(8, n); i++) s += "─"; return s }
        color: root.mutedColor; font.family: "monospace"; font.pixelSize: root.fontPx
      }
      Repeater {
        model: root.rows
        Row {
          required property var modelData
          spacing: Math.round(Style.space(8) * root.scale_)
          WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: modelData.label + ":"; color: root.logoColor; font.family: Style.font.resolvedFamily; font.pixelSize: root.fontPx; width: Math.round(Style.space(70) * root.scale_) }
          WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: modelData.value; color: root.textColor; font.family: Style.font.resolvedFamily; font.pixelSize: root.fontPx }
        }
      }
      Item { width: 1; height: Math.round(Style.space(6) * root.scale_); visible: root.swatches }
      Row {
        visible: root.swatches
        spacing: Math.round(Style.space(2) * root.scale_)
        Repeater {
          model: [Color.background, Color.urgent, Color.accent, Color.muted, root.textColor, root.logoColor, root.mutedColor, Color.foreground]
          Rectangle {
            required property var modelData
            width: Math.round(Style.space(18) * root.scale_); height: Math.round(Style.space(10) * root.scale_)
            radius: 2; color: modelData
            border.width: 1; border.color: Util.alpha(root.outlineColor, 0.85)
          }
        }
      }
      WidgetText {
        visible: !!root.info.error
        outlineColor: root.outlineColor; halo: root.halo
        text: "sysinfo: " + (root.info.error || ""); color: Color.urgent; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_)
      }
    }
  }
}
