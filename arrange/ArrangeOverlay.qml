import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "../widgets/Arrange.js" as Arrange

// Full-screen Top-layer window shown only while arrange mode is armed. Draws a
// dashed frame over every widget on this screen and handles the drag: the
// service's override moves the real widget live; release snaps and saves.
PanelWindow {
  id: win
  required property var service
  required property var screenRef
  screen: screenRef
  visible: service.arranging
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "homelab-desktop-widgets-arrange"
  WlrLayershell.layer: WlrLayer.Top
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  readonly property var frames: {
    var out = []
    var g = service.geometries
    for (var k in g) if (g[k].screen === screenRef.name) out.push({ key: k, index: g[k].index, rect: g[k].rect })
    return out
  }
  property var drag: null   // { key, index, startRect, pressX, pressY, rect }

  function typeOf(index) {
    var list = service.widgets || []
    for (var i = 0; i < list.length; i++) if (list[i].__index === index) return String(list[i].title || list[i].type || "")
    return ""
  }
  function frameAt(px, py) {
    for (var i = frames.length - 1; i >= 0; i--) {
      var r = frames[i].rect
      if (px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h) return frames[i]
    }
    return null
  }

  Item {
    anchors.fill: parent
    focus: true
    Keys.onPressed: function(e) {
      if (e.key === Qt.Key_Escape || e.key === Qt.Key_Return || e.key === Qt.Key_Enter) { win.service.setArranging(false); e.accepted = true }
    }
  }

  Repeater {
    model: win.frames
    delegate: Item {
      required property var modelData
      readonly property bool active: !!win.drag && win.drag.key === modelData.key
      x: active ? win.drag.rect.x : modelData.rect.x
      y: active ? win.drag.rect.y : modelData.rect.y
      width: modelData.rect.w
      height: modelData.rect.h
      Rectangle { anchors.fill: parent; color: Util.alpha(Color.accent, active ? 0.2 : 0.08); radius: Style.cornerRadius }
      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeColor: Color.accent; strokeWidth: 2; fillColor: "transparent"
          strokeStyle: ShapePath.DashLine; dashPattern: [4, 3]
          startX: 1; startY: 1
          PathLine { x: width - 1; y: 1 }
          PathLine { x: width - 1; y: height - 1 }
          PathLine { x: 1; y: height - 1 }
          PathLine { x: 1; y: 1 }
        }
      }
      Rectangle {
        anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Style.space(4)
        width: tag.implicitWidth + Style.space(10); height: tag.implicitHeight + Style.space(4)
        radius: Style.cornerRadius > 0 ? Style.cornerRadius / 2 : 0
        color: Util.alpha(Color.popups.background, 0.85)
        Text { id: tag; anchors.centerIn: parent; text: "#" + modelData.index + " " + win.typeOf(modelData.index); color: Color.accent; font.family: Style.font.family; font.pixelSize: Style.font.caption }
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: win.drag ? Qt.ClosedHandCursor : (win.frameAt(mouseX, mouseY) ? Qt.OpenHandCursor : Qt.ArrowCursor)
    onPressed: function(m) {
      var f = win.frameAt(m.x, m.y)
      if (!f) return
      win.drag = { key: f.key, index: f.index, startRect: f.rect, pressX: m.x, pressY: m.y, rect: f.rect }
      win.service.touchArrange()
    }
    onPositionChanged: function(m) {
      if (!win.drag) return
      var rect = Arrange.moveRect(win.drag.startRect, m.x - win.drag.pressX, m.y - win.drag.pressY, win.width, win.height)
      var d = win.drag; d.rect = rect; win.drag = d
      win.service.setOverride(d.key, Arrange.placeFor(rect, win.width, win.height))
    }
    onReleased: function(m) {
      if (!win.drag) return
      var d = win.drag; win.drag = null
      win.service.commitPlace(d.key, d.index, Arrange.placeFor(d.rect, win.width, win.height))
    }
  }

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: Style.space(28)
    width: hint.implicitWidth + Style.space(28); height: hint.implicitHeight + Style.space(14)
    radius: Style.cornerRadius; color: Color.popups.background; border.width: 1; border.color: Color.popups.border
    Text { id: hint; anchors.centerIn: parent; text: "Arrange mode — drag a widget; it snaps to the nearest corner · Esc or Enter to finish"; color: Color.popups.text; font.family: Style.font.family; font.pixelSize: Style.font.body }
  }
}
