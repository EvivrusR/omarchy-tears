import QtQuick
import Quickshell.Io
import qs.Commons
import "Series.js" as Series
import "Monitor.js" as Monitor
import "Stream.js" as Stream

// Stats v2: chosen rows sampled every intervalSec, kept for windowSec, drawn
// as sparklines (filled), bars, or numbers only.
WidgetCard {
  id: root
  readonly property var rowKeys: listOf(config.rows) || ["cpu", "mem", "net-down", "net-up"]
  readonly property int intervalSec: Math.max(2, parseInt(config.intervalSec) || 10)
  readonly property int windowSec: Math.max(30, parseInt(config.windowSec) || 300)
  readonly property string graph: String(config.graph || "sparkline")
  readonly property int graphH: Math.round(Number(config.graphHeight || 28) * scale_)
  readonly property int graphW: Math.round(Number(config.graphWidth || 200) * scale_)
  readonly property string iface: String(config.iface || "")
  readonly property string title: String(config.title || "")
  readonly property color downColor: resolveColor(config.downColor || "accent", Color.accent)
  readonly property color upColor: resolveColor(config.upColor || "urgent", Color.urgent)

  property var prev: null
  property var sample: null
  property var rate: null
  property var series: ({})
  property int tick: 0     // bumps so bindings re-read the mutable series

  function colorFor(key) { return key === "net-down" ? downColor : key === "net-up" ? upColor : textColor }
  function seriesFor(key) {
    if (!series[key] || series[key].windowSec !== windowSec) series[key] = Series.create(windowSec)
    return series[key]
  }
  property var service: null        // injected: its shared stream replaces our own sampler
  // Decided after the Loader has had its chance to inject the service (it does so after completion).
  property bool standalone: false
  Component.onCompleted: Qt.callLater(function() { root.standalone = !root.service })
  property double lastT: 0
  function ingestText(text) { try { ingest(JSON.parse(text)) } catch (e) {} }
  function ingest(s) {
    if (!s) return
    if (iface !== "" && s.nets) { var c = ({}); for (var k in s) c[k] = s[k]; c.net = s.nets[iface] || null; s = c }
    lastT = s.t
    rate = Monitor.netRate(prev, s)
    prev = sample; sample = s
    for (var i = 0; i < rowKeys.length; i++) {
      var k = String(rowKeys[i])
      Series.push(seriesFor(k), s.t, Monitor.rowValue(k, s, rate))
    }
    prev = s
    tick += 1
  }

  Process {
    id: sampler
    command: {
      var c = [String(Qt.resolvedUrl("../bin/dw-sample")).replace(/^file:\/\//, "")]
      if (root.iface !== "") c = c.concat(["--iface", root.iface])
      return c
    }
    stdout: StdioCollector { onStreamFinished: root.ingestText(text) }
  }
  Connections {
    target: root.service
    function onSampleChanged() { var s = root.service.sample; if (s && Stream.due(root.lastT, s.t, root.intervalSec, root.service.streamInterval)) root.ingest(s) }
  }
  onServiceChanged: if (service && service.sample) ingest(service.sample)
  Timer { interval: root.intervalSec * 1000; running: root.standalone; repeat: true; triggeredOnStart: true; onTriggered: if (!sampler.running) sampler.running = true }

  Column {
    spacing: Math.round(Style.space(6) * root.scale_)
    WidgetText {
      visible: root.title !== ""
      outlineColor: root.outlineColor; halo: root.halo
      text: root.title; color: root.mutedColor
      font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_); font.letterSpacing: 1
    }
    Repeater {
      model: root.rowKeys
      Column {
        required property var modelData
        readonly property string key: String(modelData)
        readonly property var def: Monitor.ROWS[key] || { label: key, max: null, fmt: function(v) { return String(v) } }
        readonly property var ser: { root.tick; return root.seriesFor(key) }
        readonly property var value: { root.tick; return Series.latest(ser) }
        readonly property bool unavailable: { root.tick; return root.sample !== null && value === null && key === "gpu" }
        spacing: Math.round(Style.space(2) * root.scale_)
        Item {
          width: root.graphW
          height: Math.round(Style.font.body * 1.3 * root.scale_)
          WidgetText {
            outlineColor: root.outlineColor; halo: root.halo
            anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
            text: def.label; color: root.mutedColor
            font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_)
          }
          WidgetText {
            outlineColor: root.outlineColor; halo: root.halo
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: unavailable ? "n/a" : def.fmt(value)
            color: unavailable ? root.mutedColor : (def.max === 100 && value !== null && value >= 90 ? Color.urgent : root.colorFor(key))
            font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.body * root.scale_)
          }
        }
        Sparkline {
          visible: root.graph === "sparkline" && !unavailable
          width: root.graphW; height: root.graphH
          points: { root.tick; return Series.polyline(ser, root.sample ? root.sample.t : 0, def.max) }
          lineColor: root.colorFor(key); outlineColor: root.outlineColor
        }
        Rectangle {
          visible: root.graph === "bars" && !unavailable
          width: root.graphW; height: Math.max(3, Math.round(Style.space(5) * root.scale_)); radius: height / 2
          color: root.outlineColor.a > 0 ? Util.alpha(root.outlineColor, 0.25) : Util.alpha(root.textColor, 0.15)
          border.width: root.outlineColor.a > 0 ? 1 : 0; border.color: Util.alpha(root.outlineColor, 0.85)
          Rectangle {
            readonly property real scaleTop: def.max > 0 ? def.max : Math.max(1, Series.maxOf(ser))
            width: value === null ? 0 : parent.width * Math.min(1, value / scaleTop); height: parent.height; radius: parent.radius
            color: root.colorFor(key)
            Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
          }
        }
      }
    }
  }
}
