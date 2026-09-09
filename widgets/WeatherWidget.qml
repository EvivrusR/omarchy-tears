import QtQuick
import Quickshell.Io
import qs.Commons

// Current conditions + next hours for a typed place (bin/dw-weather, Open-Meteo).
WidgetCard {
  id: root
  readonly property string place: String(config.place || "Tokyo, Japan")
  readonly property string units: String(config.units || "metric")
  readonly property int refreshMin: Math.max(5, parseInt(config.refreshMin) || 15)
  readonly property bool inline: String(config.layout || "stacked") === "inline"
  readonly property var show: listOf(config.show) || ["place", "feels", "humidity", "wind", "hours", "attribution"]
  readonly property int hours: Math.max(0, Math.min(12, parseInt(config.hours !== undefined ? config.hours : 6)))
  function has(k) { return show.indexOf(k) !== -1 }
  property var data: ({})
  readonly property var cur: data.current || null
  readonly property string tempUnit: data.units ? data.units.temp : "°"
  function deg(v) { return v === null || v === undefined ? "…" : Math.round(Number(v)) + "°" }

  Process {
    id: fetcher
    command: [String(Qt.resolvedUrl("../bin/dw-weather")).replace(/^file:\/\//, ""), "--place", root.place, "--units", root.units, "--hours", String(Math.max(1, root.hours)), "--max-age-min", String(Math.max(1, root.refreshMin - 1))]
    stdout: StdioCollector { onStreamFinished: { try { root.data = JSON.parse(text) } catch (e) { root.data = { error: String(e) } } } }
  }
  Timer { interval: root.refreshMin * 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!fetcher.running) fetcher.running = true }

  readonly property int bodyPx: Math.round(Style.font.body * root.scale_)

  Grid {
    columns: root.inline ? 2 : 1
    columnSpacing: Math.round(Style.space(16) * root.scale_)
    rowSpacing: Math.round(Style.space(4) * root.scale_)
    verticalItemAlignment: Grid.AlignVCenter
    horizontalItemAlignment: root.align === "right" ? Grid.AlignRight : Grid.AlignLeft

    Row {
      spacing: Math.round(Style.space(10) * root.scale_)
      WidgetText {
        outlineColor: root.outlineColor; halo: root.halo
        text: root.cur ? root.cur.icon : "\U000f0590"
        color: root.textColor; font.family: Style.font.resolvedFamily
        font.pixelSize: Math.round(Style.font.displayLarge * 1.6 * root.scale_)
        anchors.verticalCenter: parent.verticalCenter
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Math.round(Style.space(1) * root.scale_)
        WidgetText {
          outlineColor: root.outlineColor; halo: root.halo
          text: root.cur ? root.deg(root.cur.temp) : (root.data.error ? "!" : "…")
          color: root.textColor; font.family: Style.font.resolvedFamily
          font.pixelSize: Math.round(Style.font.displayLarge * 1.3 * root.scale_); font.weight: Font.Light
        }
        WidgetText {
          outlineColor: root.outlineColor; halo: root.halo
          text: root.cur ? root.cur.desc : (root.data.error ? String(root.data.error).slice(0, 40) : "loading")
          color: root.cur ? root.mutedColor : Color.urgent; font.family: Style.font.resolvedFamily; font.pixelSize: root.bodyPx
        }
      }
    }

    Column {
      spacing: Math.round(Style.space(2) * root.scale_)
      WidgetText {
        visible: root.has("place")
        outlineColor: root.outlineColor; halo: root.halo
        text: root.data.place ? (root.data.place.name || root.place) + (root.data.place.country ? ", " + root.data.place.country : "") : root.place
        color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_); font.letterSpacing: 1
      }
      WidgetText {
        visible: !!root.cur && (root.has("feels") || root.has("humidity") || root.has("wind"))
        outlineColor: root.outlineColor; halo: root.halo
        text: {
          if (!root.cur) return ""
          var bits = []
          if (root.has("feels")) bits.push("feels " + root.deg(root.cur.feels))
          if (root.has("humidity") && root.cur.humidity !== null) bits.push(root.cur.humidity + "%")
          if (root.has("wind") && root.cur.wind !== null) bits.push(Math.round(root.cur.wind) + " " + (root.data.units ? root.data.units.wind : ""))
          return bits.join(" · ")
        }
        color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: root.bodyPx
      }
      Row {
        visible: root.has("hours") && root.hours > 0 && (root.data.hourly || []).length > 0
        spacing: Math.round(Style.space(10) * root.scale_)
        Repeater {
          model: (root.data.hourly || []).slice(0, root.hours)
          Column {
            required property var modelData
            spacing: 0
            WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: modelData.time; color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_); anchors.horizontalCenter: parent.horizontalCenter }
            WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: modelData.icon; color: root.textColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.heading * root.scale_); anchors.horizontalCenter: parent.horizontalCenter }
            WidgetText { outlineColor: root.outlineColor; halo: root.halo; text: root.deg(modelData.temp); color: root.textColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_); anchors.horizontalCenter: parent.horizontalCenter }
          }
        }
      }
      WidgetText {
        visible: root.has("attribution")
        outlineColor: root.outlineColor; halo: root.halo
        text: (root.data.attribution || "Weather data by Open-Meteo.com") + (root.data.stale ? " · offline, last known" : "")
        color: root.mutedColor; font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * 0.85 * root.scale_)
      }
    }
  }
}
