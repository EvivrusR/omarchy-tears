import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Pet.js" as Pet

// A pet: a Hermes/petdex sprite sheet (192×208 cells, 8 columns, one row per
// state) driven by rules over signals from bin/dw-signals. The sheet carries
// no logic; Pet.js decides the row, Qt's AnimatedSprite does the frames.
WidgetCard {
  id: root
  pad: 0
  readonly property string sheetPath: String(config.sheet || "").replace(/^~/, Quickshell.env("HOME"))
  readonly property url sheetUrl: sheetPath ? "file://" + sheetPath : ""
  readonly property string watch: String(config.watch || "claude")
  readonly property var rules: Pet.rulesFor(watch, listOf(config.rules))
  readonly property int size: Math.round(Number(config.size || 96) * scale_)
  readonly property int fps: Math.max(2, Math.min(12, parseInt(config.fps) || 6))
  readonly property bool bubble: config.bubble !== false
  readonly property bool flip: config.flip === true
  readonly property int intervalSec: Math.max(2, parseInt(config.intervalSec) || 5)
  topInset: bubble ? Math.round((Style.font.caption + Style.space(16)) * scale_) : 0

  property var engine: null
  property string petState: "idle"
  property string say: ""
  property int sheetRows: 9
  property var counts: []
  readonly property int row: Pet.rowFor(petState, sheetRows * Pet.FRAME_H, flip)
  readonly property int frames: counts[row] || Pet.FRAMES

  function apply(text) {
    var s
    try { s = JSON.parse(text) } catch (e) { return }
    engine = Pet.step(rules, s, engine, Date.now())
    petState = engine.state; say = engine.say
    if (engine.beatUntil > Date.now()) { beatEnd.interval = Math.max(50, engine.beatUntil - Date.now() + 30); beatEnd.restart() }
  }
  Process {
    id: signals
    command: [String(Qt.resolvedUrl("../bin/dw-signals")).replace(/^file:\/\//, "")]
    stdout: StdioCollector { onStreamFinished: root.apply(text) }
  }
  Timer { interval: root.intervalSec * 1000; running: root.sheetPath !== ""; repeat: true; triggeredOnStart: true; onTriggered: if (!signals.running) signals.running = true }
  // Re-evaluate when a beat ends so the pet doesn't linger until the next poll.
  Timer { id: beatEnd; repeat: false; onTriggered: if (root.engine) { root.engine = Pet.step(root.rules, root.engine.signals, root.engine, Date.now()); root.petState = root.engine.state; root.say = root.engine.say } }

  // Sheet geometry + padding trim (Hermes rule: a cell whose max alpha ≤ 8 is
  // blank padding). Done once through a hidden canvas, then released.
  Image { id: probe; parent: root; source: root.sheetUrl; visible: false; asynchronous: true; width: 1; height: 1
    onStatusChanged: if (status === Image.Ready) { root.sheetRows = Math.max(1, Math.round(sourceSize.height / Pet.FRAME_H)); trim.width = sourceSize.width; trim.height = sourceSize.height; trim.loadImage(root.sheetUrl) } }
  Canvas {
    id: trim
    parent: root   // outside the card's content so its size never counts
    visible: false; renderTarget: Canvas.Image; renderStrategy: Canvas.Immediate
    onImageLoaded: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height); ctx.drawImage(root.sheetUrl, 0, 0)
      var alpha = [], rows = Math.round(height / Pet.FRAME_H)
      for (var r = 0; r < rows; r++) for (var c = 0; c < Pet.COLS; c++) {
        var d = ctx.getImageData(c * Pet.FRAME_W, r * Pet.FRAME_H, Pet.FRAME_W, Pet.FRAME_H).data, m = 0
        for (var i = 3; i < d.length; i += 4 * 5) if (d[i] > m) { m = d[i]; if (m > 8) break }
        alpha.push(m)
      }
      root.counts = Pet.trimCounts(alpha, rows)
      unloadImage(root.sheetUrl)
    }
  }

  Item {
    width: root.size * Pet.FRAME_W / Pet.FRAME_H
    height: root.size
    visible: root.sheetPath !== ""
    AnimatedSprite {
      id: sprite
      anchors.fill: parent
      source: root.sheetUrl
      frameWidth: Pet.FRAME_W; frameHeight: Pet.FRAME_H
      frameX: 0; frameY: root.row * Pet.FRAME_H
      frameCount: root.frames
      frameDuration: Math.round(1000 / root.fps)
      interpolate: false
      running: true; loops: AnimatedSprite.Infinite
      transform: Scale { xScale: root.flip ? -1 : 1; origin.x: sprite.width / 2 }
      onFrameYChanged: restart()
      onFrameCountChanged: restart()
    }
  }
  WidgetText {
    visible: root.sheetPath === ""
    width: visible ? implicitWidth : 0; height: visible ? implicitHeight : 0   // hidden items still count in childrenRect
    outlineColor: root.outlineColor; halo: root.halo
    text: "pet: no sheet — `desktop-widgets pets` lists sprite sheets"; color: root.mutedColor
    font.family: Style.font.resolvedFamily; font.pixelSize: Math.round(Style.font.caption * root.scale_)
  }
  // Speech bubble in the card's top inset.
  Rectangle {
    parent: root
    visible: root.bubble && root.say !== ""
    x: Math.max(0, Math.min(root.width - width, root.width / 2 - width / 2))
    y: Math.max(0, root.topInset - height - Math.round(Style.space(2) * root.scale_))
    width: bubbleText.implicitWidth + Style.space(12) * root.scale_; height: bubbleText.implicitHeight + Style.space(6) * root.scale_
    radius: height / 2
    color: Util.alpha(Color.popups.background, 0.92); border.width: 1; border.color: Color.popups.border
    Text { id: bubbleText; anchors.centerIn: parent; text: root.say; color: root.textColor; font.family: Style.font.family; font.pixelSize: Math.round(Style.font.caption * root.scale_) }
  }
}
