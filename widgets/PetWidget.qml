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
  property var service: null                       // injected by the service: other pets' states live there
  readonly property string petName: service && service.petNameFor(config.__index) ? service.petNameFor(config.__index) : Pet.petName(config)
  readonly property var layers: Pet.layerSpecs(listOf(config.layers))
  readonly property real cellScale: size / Pet.FRAME_H    // cell px → screen px
  function layerUrl(src) { var p = String(src).replace(/^~/, Quickshell.env("HOME")); return p.charAt(0) === "/" ? "file://" + p : p }
  topInset: bubble ? Math.round((Style.font.caption + Style.space(16)) * scale_) : 0

  property var engine: null
  property string petState: "idle"
  property string say: ""
  property int sheetRows: 9
  property var counts: []
  property var present: []
  readonly property var looksList: Pet.looks(sheetRows * Pet.FRAME_H, { counts: counts, present: present })
  readonly property int row: Pet.rowFor(petState, sheetRows * Pet.FRAME_H, flip, present.length ? present : null)
  readonly property int frames: counts[row] || Pet.FRAMES

  function publish() { if (service) service.publishPet(petName, { state: petState, say: say, watch: watch, looks: looksList }) }
  function apply(text) {
    var s
    try { s = JSON.parse(text) } catch (e) { return }
    s.pets = service ? service.petStates : {}            // previous tick's states of every pet, this one included
    engine = Pet.step(rules, s, engine, Date.now())
    petState = engine.state; say = engine.say
    publish()
    if (engine.beatUntil > Date.now()) { beatEnd.interval = Math.max(50, engine.beatUntil - Date.now() + 30); beatEnd.restart() }
  }
  Process {
    id: signals
    command: [String(Qt.resolvedUrl("../bin/dw-signals")).replace(/^file:\/\//, "")]
    stdout: StdioCollector { onStreamFinished: root.apply(text) }
  }
  Timer { interval: root.intervalSec * 1000; running: root.sheetPath !== ""; repeat: true; triggeredOnStart: true; onTriggered: if (!signals.running) signals.running = true }
  // Re-evaluate when a beat ends so the pet doesn't linger until the next poll.
  Timer { id: beatEnd; repeat: false; onTriggered: if (root.engine) { root.engine = Pet.step(root.rules, root.engine.signals, root.engine, Date.now()); root.petState = root.engine.state; root.say = root.engine.say; root.publish() } }
  Component.onCompleted: publish()

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
      var info = Pet.trimInfo(alpha, rows)
      root.counts = info.counts; root.present = info.present
      root.publish()
      unloadImage(root.sheetUrl)
    }
  }

  // Layers may stick out of the body cell; the container grows to the union
  // and the body is offset so nothing is clipped by the window.
  property var layerSizes: ({})
  readonly property real bodyW: size * Pet.FRAME_W / Pet.FRAME_H
  readonly property var box: Pet.bounds(layers, bodyW, size, cellScale, layerSizes)

  // A layer: a static prop, or a sheet clipped to the body's current row and frame.
  component Layer: Item {
    property var spec: ({})
    property int index: -1
    readonly property bool isSheet: spec.kind === "sheet"
    readonly property int lrow: isSheet ? Pet.rowFor(root.petState, root.sheetRows * Pet.FRAME_H, root.flip, root.present.length ? root.present : null) : 0
    x: spec.x * root.cellScale - root.box.x; y: spec.y * root.cellScale - root.box.y
    width: isSheet ? root.bodyW : img.implicitWidth * root.cellScale * spec.scale
    height: isSheet ? root.size : img.implicitHeight * root.cellScale * spec.scale
    Image {
      id: img
      anchors.fill: parent
      source: root.layerUrl(spec.source)
      onStatusChanged: if (status === Image.Ready && !parent.isSheet) { var n = ({}); for (var k in root.layerSizes) n[k] = root.layerSizes[k]; n[parent.index] = { w: implicitWidth, h: implicitHeight }; root.layerSizes = n }
      sourceClipRect: parent.isSheet ? Qt.rect(sprite.currentFrame * Pet.FRAME_W, parent.lrow * Pet.FRAME_H, Pet.FRAME_W, Pet.FRAME_H) : undefined
      fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; asynchronous: true
      transform: Scale { xScale: root.flip && parent.isSheet ? -1 : 1; origin.x: img.width / 2 }
    }
  }

  Item {
    width: root.box.w
    height: root.box.h
    visible: root.sheetPath !== ""
    Repeater { model: root.layers.map(function(l, i) { return { spec: l, i: i } }).filter(function(e) { return !e.spec.front }); Layer { required property var modelData; spec: modelData.spec; index: modelData.i } }
    AnimatedSprite {
      id: sprite
      x: -root.box.x; y: -root.box.y
      width: root.bodyW; height: root.size
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
    Repeater { model: root.layers.map(function(l, i) { return { spec: l, i: i } }).filter(function(e) { return e.spec.front }); Layer { required property var modelData; spec: modelData.spec; index: modelData.i } }
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
