import QtQuick
import Quickshell.Io
import qs.Commons
import "Weather.js" as Weather

// Full-screen animated ASCII weather (rain, snow, clouds, fog, stars, storm
// flashes) for a weather widget with `effect: true`. Reads the same cached
// forecast the widget fetched; one Text for the particle field, a few sprite
// Texts for clouds/sun; the timer only runs while something moves.
Item {
  id: fx
  property var config: ({})
  readonly property real scale_: Math.max(0.25, Number(config.scale || 1))
  readonly property string place: String(config.place || "Tokyo, Japan")
  readonly property string units: String(config.units || "metric")
  readonly property int refreshMin: Math.max(5, parseInt(config.refreshMin) || 15)
  readonly property real userOpacity: config.effectOpacity === undefined ? 0.4 : Math.max(0, Math.min(1, Number(config.effectOpacity)))
  readonly property real density: Math.max(0.2, Math.min(3, Number(config.effectDensity || 1)))
  readonly property int fps: Math.max(2, Math.min(12, parseInt(config.effectFps) || 6))
  readonly property color inkColor: {
    var v = String(config.effectColor || "foreground")
    switch (v) { case "foreground": return Color.foreground; case "background": return Color.background; case "accent": return Color.accent; case "muted": return Color.muted; case "urgent": return Color.urgent }
    var c = Qt.color(v); return c.valid === false ? Color.foreground : c
  }

  property var data: ({})
  readonly property var effect: data.current ? Weather.effectFor(data.current.group, data.current.isDay, data.current.wind) : Weather.EFFECTS.none
  readonly property real alpha: userOpacity * (effect.opacity || 0)
  readonly property bool moving: effect.kind === "fall" || effect.kind === "fog" || effect.kind === "clouds" || effect.kind === "twinkle" || !!effect.flash

  readonly property int cellPx: Math.round(16 * scale_)
  readonly property int cellW: Math.max(4, Math.round(metrics.advanceWidth("M")))
  readonly property int cellH: Math.max(6, cellPx)
  readonly property int cols: Math.max(10, Math.floor(width / cellW))
  readonly property int rows: Math.max(5, Math.floor(height / cellH))
  FontMetrics { id: metrics; font.family: "monospace"; font.pixelSize: fx.cellPx }

  property var state: null
  property var rand: Weather.makeRand(Date.now() % 100000)
  property string fieldText: ""
  property var spriteList: []
  property bool flashOn: false
  function rebuild() {
    state = Weather.init(effect, cols, rows, density, rand)
    frame()
  }
  function frame() {
    if (!state) return
    Weather.step(state, effect, rand, fps)
    fieldText = Weather.render(state, effect).join("\n")
    spriteList = Weather.sprites(state)
    flashOn = state.flash > 0
  }
  onEffectChanged: rebuild()
  onColsChanged: rebuild()
  onRowsChanged: rebuild()

  Process {
    id: fetcher
    command: [String(Qt.resolvedUrl("../bin/dw-weather")).replace(/^file:\/\//, ""), "--place", fx.place, "--units", fx.units, "--hours", "1", "--max-age-min", String(Math.max(1, fx.refreshMin - 1))]
    stdout: StdioCollector { onStreamFinished: { try { fx.data = JSON.parse(text) } catch (e) { fx.data = {} } } }
  }
  Timer { interval: fx.refreshMin * 60000; running: true; repeat: true; triggeredOnStart: true; onTriggered: if (!fetcher.running) fetcher.running = true }
  Timer { interval: Math.round(1000 / fx.fps); running: fx.moving && fx.alpha > 0 && fx.visible; repeat: true; onTriggered: fx.frame() }

  Text {
    id: field
    x: 0; y: 0
    text: fx.fieldText
    color: fx.inkColor
    opacity: fx.alpha
    font.family: "monospace"; font.pixelSize: fx.cellPx
    lineHeight: fx.cellH; lineHeightMode: Text.FixedHeight
    textFormat: Text.PlainText; renderType: Text.NativeRendering
  }
  Repeater {
    model: fx.spriteList
    Text {
      required property var modelData
      x: modelData.c * fx.cellW; y: modelData.r * fx.cellH
      text: modelData.lines.join("\n")
      color: fx.inkColor; opacity: fx.alpha * 1.4
      font.family: "monospace"; font.pixelSize: fx.cellPx
      lineHeight: fx.cellH; lineHeightMode: Text.FixedHeight
      textFormat: Text.PlainText; renderType: Text.NativeRendering
    }
  }
  Text {
    visible: !!fx.effect.sun
    x: fx.width - (12 * fx.cellW) - fx.cellW * 4; y: fx.cellH * 3
    text: Weather.SUN.join("\n")
    color: fx.inkColor; opacity: fx.alpha * 1.6
    font.family: "monospace"; font.pixelSize: fx.cellPx
    lineHeight: fx.cellH; lineHeightMode: Text.FixedHeight
    textFormat: Text.PlainText; renderType: Text.NativeRendering
  }
  Rectangle { anchors.fill: parent; color: "white"; opacity: fx.flashOn ? Math.min(0.6, fx.userOpacity * 0.5) : 0; Behavior on opacity { NumberAnimation { duration: 120 } } }
}
