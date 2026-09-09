import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Agents.js" as Agents

// Current AI-agent session: percent of the rolling window used and when it
// ends. Display-only: it watches the record omarchy-agent-usage-update
// maintains for the shell's own Agents bar widget. Set refreshIntervalSec
// to have this widget trigger a limits refresh itself (e.g. when the bar
// widget is disabled); otherwise the bar's 15-minute refresh feeds it.
WidgetCard {
  id: root
  readonly property string agent: String(config.agent || "claude")
  readonly property bool showWeekly: config.showWeekly === true
  readonly property int refreshIntervalSec: Math.max(0, parseInt(config.refreshIntervalSec) || 0)
  readonly property string recordPath: Quickshell.env("HOME") + "/.local/state/omarchy/agents/usage/" + agent + ".json"
  readonly property int barWidth: Math.round(Style.space(150) * scale_)

  property var record: null
  property double nowMs: Date.now()

  readonly property var session: Agents.sessionWindow(record)
  readonly property var weekly: showWeekly ? Agents.weeklyWindow(record) : null
  readonly property string heading: {
    if (!record) return String(config.title || agent.toUpperCase())
    var name = String(config.title || record.name || agent).toUpperCase()
    return record.tierLabel ? name + " · " + record.tierLabel : name
  }
  readonly property string status: {
    if (!record) return "no usage record yet"
    if (String(record.usageStatusText || "") !== "") return String(record.usageStatusText)
    if (!session) return "no session window reported"
    return ""
  }

  function clock(d) { return Qt.formatTime(d, String(config.timeFormat || "HH:mm")) }
  function pctText(w) { return Math.round(w.percent * 100) + "%" }

  FileView {
    path: root.recordPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.record = JSON.parse(String(text() || "")) } catch (e) { root.record = null }
    }
    onLoadFailed: root.record = null
  }

  Timer { interval: 30000; running: true; repeat: true; onTriggered: root.nowMs = Date.now() }

  Process {
    id: refresher
    command: ["omarchy-agent-usage-update", "--limits-only"]
  }
  Timer {
    interval: root.refreshIntervalSec * 1000; running: root.refreshIntervalSec > 0; repeat: true
    onTriggered: if (!refresher.running) refresher.running = true
  }

  component LimitRow: Column {
    property var window: null
    spacing: Math.round(Style.space(3) * root.scale_)
    visible: !!window
    Row {
      spacing: Math.round(Style.space(8) * root.scale_)
      WidgetText {
        outlineColor: root.outlineColor; halo: root.halo
        text: window ? window.title : ""
        color: root.mutedColor
        font.family: Style.font.resolvedFamily
        font.pixelSize: Math.round(Style.font.body * root.scale_)
        width: Math.round(Style.space(56) * root.scale_)
        anchors.verticalCenter: parent.verticalCenter
      }
      WidgetText {
        outlineColor: root.outlineColor; halo: root.halo
        text: window ? root.pctText(window) : ""
        color: window && window.percent >= 0.9 ? Color.urgent : root.textColor
        font.family: Style.font.resolvedFamily
        font.pixelSize: Math.round(Style.font.heading * root.scale_)
        font.weight: Font.DemiBold
        anchors.verticalCenter: parent.verticalCenter
      }
      WidgetText {
        outlineColor: root.outlineColor; halo: root.halo
        text: window ? Agents.resetSummary(window.resetAt, root.nowMs, root.clock) : ""
        color: root.mutedColor
        font.family: Style.font.resolvedFamily
        font.pixelSize: Math.round(Style.font.body * root.scale_)
        anchors.verticalCenter: parent.verticalCenter
      }
    }
    Rectangle {
      width: root.barWidth
      height: Math.max(3, Math.round(Style.space(5) * root.scale_))
      radius: height / 2
      color: root.outlineColor.a > 0 ? Util.alpha(root.outlineColor, 0.25) : Util.alpha(root.textColor, 0.15)
      border.width: root.outlineColor.a > 0 ? 1 : 0
      border.color: Util.alpha(root.outlineColor, 0.85)
      Rectangle {
        width: window ? parent.width * Math.min(1, window.percent) : 0
        height: parent.height
        radius: parent.radius
        color: window && window.percent >= 0.9 ? Color.urgent : root.textColor
        Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
      }
    }
  }

  Column {
    spacing: Math.round(Style.space(6) * root.scale_)
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      text: root.heading
      color: root.mutedColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.caption * root.scale_)
      font.letterSpacing: 1
    }
    WidgetText {
      outlineColor: root.outlineColor; halo: root.halo
      visible: root.status !== ""
      text: root.status
      color: root.textColor
      font.family: Style.font.resolvedFamily
      font.pixelSize: Math.round(Style.font.body * root.scale_)
    }
    LimitRow { window: root.session }
    LimitRow { window: root.weekly }
  }
}
