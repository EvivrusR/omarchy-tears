import QtQuick
import QtQuick.Controls
import qs.Commons

// A scrollbar that stays on screen whenever there is something to scroll
// (the Basic style only shows one while it moves), themed like the rest of
// the kit. Click the track to page, drag the handle to scroll.
ScrollBar {
  id: bar
  policy: size < 1.0 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
  interactive: true
  minimumSize: 0.08
  readonly property int thickness: Style.space(8)
  implicitWidth: orientation === Qt.Vertical ? thickness : 0
  implicitHeight: orientation === Qt.Horizontal ? thickness : 0
  padding: Style.space(1)
  background: Rectangle { radius: bar.thickness / 2; color: Util.alpha(Color.popups.text, 0.08) }
  contentItem: Rectangle {
    radius: bar.thickness / 2
    color: bar.pressed ? Color.accent : Util.alpha(bar.hovered ? Color.accent : Color.popups.text, bar.hovered ? 0.8 : 0.35)
    Behavior on color { ColorAnimation { duration: 120 } }
  }
}
